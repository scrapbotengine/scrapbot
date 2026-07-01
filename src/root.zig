const std = @import("std");
const Io = std.Io;
const render = @import("render.zig");
const render_verify = @import("render_verify.zig");
const runtime = @import("runtime.zig");
const script = @import("script.zig");

pub const version = "0.1.0-dev";
pub const project_file_name = "project.machina.toml";
pub const default_scene_path = "scenes/main.scene.toml";

pub const renderDemoBmp = render.renderDemoBmp;
pub const runDemoWindow = render.runDemoWindow;
pub const WindowOptions = render.WindowOptions;
pub const RenderScene = render.Scene;
pub const RenderVerification = render_verify.Verification;
pub const RenderVerificationOptions = render_verify.VerificationOptions;
pub const World = runtime.World;
pub const EntityHandle = runtime.EntityHandle;
pub const Transform = runtime.Transform;
pub const CubeRenderer = runtime.CubeRenderer;
pub const Spin = runtime.Spin;
pub const ComponentRegistry = runtime.ComponentRegistry;
pub const ComponentDefinition = runtime.ComponentDefinition;
pub const ComponentFieldDefinition = runtime.ComponentFieldDefinition;
pub const FieldType = runtime.FieldType;
pub const SystemDefinition = runtime.SystemDefinition;
pub const SystemPhase = runtime.SystemPhase;
pub const SystemSchedule = runtime.SystemSchedule;
pub const ScheduleError = runtime.ScheduleError;
pub const TypeIdError = runtime.TypeIdError;
pub const RegistryError = runtime.RegistryError;
pub const ScriptError = script.ScriptError;
pub const validateTypeId = runtime.validateTypeId;
pub const validateProjectTypeId = runtime.validateProjectTypeId;
pub const validatePackageTypeId = runtime.validatePackageTypeId;
pub const validateEngineTypeId = runtime.validateEngineTypeId;
pub const verifyRenderBmp = render_verify.verifyBmp;

pub const Project = struct {
    root_path: []const u8,
    name: []const u8,
    default_scene: []const u8,
    scripts: []const []const u8,
};

pub const Scene = struct {
    name: []const u8,
    world: World,

    pub fn renderScene(self: *const Scene) RenderScene {
        return .{ .world = &self.world };
    }

    pub fn entityCount(self: Scene) usize {
        return self.world.entityCount();
    }

    pub fn renderableCubeCount(self: Scene) usize {
        return self.world.renderableCubeCount();
    }
};

pub const Diagnostic = struct {
    path: []const u8,
    message: []const u8,
};

pub const CheckResult = struct {
    project: Project,
};

const SourceFileStamp = struct {
    size: u64,
    mtime: Io.Timestamp,

    fn eql(self: SourceFileStamp, other: SourceFileStamp) bool {
        return self.size == other.size and self.mtime.nanoseconds == other.mtime.nanoseconds;
    }
};

const LoadedSource = struct {
    path: []const u8,
    stamp: SourceFileStamp,
};

pub const ReloadInfo = struct {
    project_reloaded: bool,
    scene_reloaded: bool,
    scripts_reloaded: bool,
    project_name: []const u8,
    scene_path: []const u8,
    entity_count: usize,
    renderable_cube_count: usize,
    script_count: usize,
    system_batch_count: usize,
};

pub const ReloadResult = union(enum) {
    unchanged,
    reloaded: ReloadInfo,
};

pub const LiveProject = struct {
    io: Io,
    allocator: std.mem.Allocator,
    root_path: []const u8,
    project: Project,
    scene: Scene,
    registry: ComponentRegistry,
    schedule: SystemSchedule,
    project_source: LoadedSource,
    scene_source: LoadedSource,
    script_sources: []LoadedSource,
    last_failed_project_stamp: ?SourceFileStamp = null,
    last_failed_scene_stamp: ?SourceFileStamp = null,
    last_failed_script_index: ?usize = null,
    last_failed_script_stamp: ?SourceFileStamp = null,

    pub fn init(io: Io, allocator: std.mem.Allocator, root_path: []const u8) !LiveProject {
        const project = try loadProject(io, allocator, root_path);
        errdefer freeProject(allocator, project);

        const scene = try loadDefaultScene(io, allocator, project);
        errdefer freeScene(allocator, scene);

        var registry = try loadProjectScriptRegistry(io, allocator, project);
        errdefer registry.deinit();

        var schedule = try buildProjectUpdateSchedule(allocator, registry);
        errdefer schedule.deinit();

        const script_sources = try statProjectScripts(io, allocator, project);
        errdefer freeLoadedSources(allocator, script_sources);

        return .{
            .io = io,
            .allocator = allocator,
            .root_path = project.root_path,
            .project = project,
            .scene = scene,
            .registry = registry,
            .schedule = schedule,
            .project_source = .{
                .path = project_file_name,
                .stamp = try statProjectFile(io, project.root_path),
            },
            .scene_source = .{
                .path = project.default_scene,
                .stamp = try statProjectResource(io, project, project.default_scene, ProjectError.MissingDefaultScene),
            },
            .script_sources = script_sources,
        };
    }

    pub fn deinit(self: *LiveProject) void {
        freeLoadedSources(self.allocator, self.script_sources);
        self.schedule.deinit();
        self.registry.deinit();
        freeScene(self.allocator, self.scene);
        freeProject(self.allocator, self.project);
        self.* = undefined;
    }

    pub fn renderScene(self: *const LiveProject) RenderScene {
        return self.scene.renderScene();
    }

    pub fn pollLoadedSources(self: *LiveProject) !ReloadResult {
        const project_stamp = try statProjectFile(self.io, self.root_path);
        if (!project_stamp.eql(self.project_source.stamp)) {
            if (self.reloadProject(project_stamp)) |result| {
                return result;
            } else |err| {
                if (self.last_failed_project_stamp) |failed_stamp| {
                    if (failed_stamp.eql(project_stamp)) {
                        return self.pollSceneSource();
                    }
                }
                self.last_failed_project_stamp = project_stamp;
                return err;
            }
        }

        return self.pollSceneSource();
    }

    fn pollSceneSource(self: *LiveProject) !ReloadResult {
        const scene_stamp = try statProjectResource(self.io, self.project, self.scene_source.path, ProjectError.MissingDefaultScene);
        if (scene_stamp.eql(self.scene_source.stamp)) {
            return self.pollScriptSources();
        }

        return self.reloadScene(scene_stamp) catch |err| {
            if (self.last_failed_scene_stamp) |failed_stamp| {
                if (failed_stamp.eql(scene_stamp)) {
                    return .unchanged;
                }
            }
            self.last_failed_scene_stamp = scene_stamp;
            return err;
        };
    }

    fn pollScriptSources(self: *LiveProject) !ReloadResult {
        for (self.script_sources, 0..) |loaded_script, index| {
            const script_stamp = try statProjectResource(self.io, self.project, loaded_script.path, ProjectError.MissingScript);
            if (script_stamp.eql(loaded_script.stamp)) {
                continue;
            }

            return self.reloadScripts(index, script_stamp) catch |err| {
                if (self.last_failed_script_index) |failed_index| {
                    if (failed_index == index) {
                        if (self.last_failed_script_stamp) |failed_stamp| {
                            if (failed_stamp.eql(script_stamp)) {
                                return .unchanged;
                            }
                        }
                    }
                }
                self.last_failed_script_index = index;
                self.last_failed_script_stamp = script_stamp;
                return err;
            };
        }

        return .unchanged;
    }

    fn reloadProject(self: *LiveProject, project_stamp: SourceFileStamp) !ReloadResult {
        const next_project = try loadProject(self.io, self.allocator, self.root_path);
        errdefer freeProject(self.allocator, next_project);

        const next_scene = try loadDefaultScene(self.io, self.allocator, next_project);
        errdefer freeScene(self.allocator, next_scene);

        var next_registry = try loadProjectScriptRegistry(self.io, self.allocator, next_project);
        errdefer next_registry.deinit();

        var next_schedule = try buildProjectUpdateSchedule(self.allocator, next_registry);
        errdefer next_schedule.deinit();

        const next_script_sources = try statProjectScripts(self.io, self.allocator, next_project);
        errdefer freeLoadedSources(self.allocator, next_script_sources);

        const scene_stamp = try statProjectResource(self.io, next_project, next_project.default_scene, ProjectError.MissingDefaultScene);
        const info = ReloadInfo{
            .project_reloaded = true,
            .scene_reloaded = true,
            .scripts_reloaded = true,
            .project_name = next_project.name,
            .scene_path = next_project.default_scene,
            .entity_count = next_scene.entityCount(),
            .renderable_cube_count = next_scene.renderableCubeCount(),
            .script_count = next_project.scripts.len,
            .system_batch_count = next_schedule.batchCount(),
        };

        freeLoadedSources(self.allocator, self.script_sources);
        self.schedule.deinit();
        self.registry.deinit();
        freeScene(self.allocator, self.scene);
        freeProject(self.allocator, self.project);
        self.root_path = next_project.root_path;
        self.project = next_project;
        self.scene = next_scene;
        self.registry = next_registry;
        self.schedule = next_schedule;
        self.project_source.stamp = project_stamp;
        self.scene_source = .{
            .path = self.project.default_scene,
            .stamp = scene_stamp,
        };
        self.script_sources = next_script_sources;
        self.last_failed_project_stamp = null;
        self.last_failed_scene_stamp = null;
        self.last_failed_script_index = null;
        self.last_failed_script_stamp = null;
        return .{ .reloaded = info };
    }

    fn reloadScene(self: *LiveProject, scene_stamp: SourceFileStamp) !ReloadResult {
        const next_scene = try loadDefaultScene(self.io, self.allocator, self.project);
        const info = ReloadInfo{
            .project_reloaded = false,
            .scene_reloaded = true,
            .scripts_reloaded = false,
            .project_name = self.project.name,
            .scene_path = self.project.default_scene,
            .entity_count = next_scene.entityCount(),
            .renderable_cube_count = next_scene.renderableCubeCount(),
            .script_count = self.project.scripts.len,
            .system_batch_count = self.schedule.batchCount(),
        };

        freeScene(self.allocator, self.scene);
        self.scene = next_scene;
        self.scene_source.stamp = scene_stamp;
        self.last_failed_scene_stamp = null;
        return .{ .reloaded = info };
    }

    fn reloadScripts(self: *LiveProject, changed_index: usize, script_stamp: SourceFileStamp) !ReloadResult {
        var next_registry = try loadProjectScriptRegistry(self.io, self.allocator, self.project);
        errdefer next_registry.deinit();

        var next_schedule = try buildProjectUpdateSchedule(self.allocator, next_registry);
        errdefer next_schedule.deinit();

        const info = ReloadInfo{
            .project_reloaded = false,
            .scene_reloaded = false,
            .scripts_reloaded = true,
            .project_name = self.project.name,
            .scene_path = self.project.default_scene,
            .entity_count = self.scene.entityCount(),
            .renderable_cube_count = self.scene.renderableCubeCount(),
            .script_count = self.project.scripts.len,
            .system_batch_count = next_schedule.batchCount(),
        };

        self.schedule.deinit();
        self.registry.deinit();
        self.registry = next_registry;
        self.schedule = next_schedule;
        self.script_sources[changed_index].stamp = script_stamp;
        self.last_failed_script_index = null;
        self.last_failed_script_stamp = null;
        return .{ .reloaded = info };
    }
};

pub const LiveScene = LiveProject;

pub const ProjectError = error{
    AlreadyExists,
    InvalidProject,
    MissingProjectFile,
    MissingDefaultScene,
    UnsupportedProjectVersion,
    InvalidProjectName,
    InvalidDefaultScene,
    InvalidSceneEntity,
    DuplicateSceneEntityId,
    InvalidSceneNumber,
    MissingSceneContent,
    MissingScript,
    InvalidScript,
};

pub fn initProject(io: Io, allocator: std.mem.Allocator, root_path: []const u8, name: []const u8) !void {
    const cwd = Io.Dir.cwd();
    cwd.createDirPath(io, root_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    if (fileExists(io, root_dir, project_file_name)) {
        return ProjectError.AlreadyExists;
    }

    try root_dir.createDirPath(io, "scenes");

    const escaped_name = try encodeTomlBasicString(allocator, name);
    defer allocator.free(escaped_name);

    const project_contents = try std.fmt.allocPrint(
        allocator,
        "name = \"{s}\"\nversion = 1\ndefault_scene = \"{s}\"\n",
        .{ escaped_name, default_scene_path },
    );
    defer allocator.free(project_contents);

    {
        try root_dir.writeFile(io, .{
            .sub_path = project_file_name,
            .data = project_contents,
            .flags = .{ .exclusive = true },
        });
    }

    {
        try root_dir.writeFile(io, .{
            .sub_path = default_scene_path,
            .data =
            \\name = "Main"
            \\version = 1
            \\
            \\[[entities]]
            \\id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001"
            \\name = "Demo Cube"
            \\kind = "cube"
            \\position = [0.0, 0.0, 0.0]
            \\rotation = [0.0, 0.0, 0.0]
            \\scale = [1.0, 1.0, 1.0]
            \\color = [0.0, 0.56, 1.0]
            \\spin = [0.62, 1.0, 0.0]
            \\
            ,
            .flags = .{ .exclusive = true },
        });
    }
}

pub fn checkProject(io: Io, allocator: std.mem.Allocator, root_path: []const u8) !CheckResult {
    const project = try loadProject(io, allocator, root_path);
    errdefer freeProject(allocator, project);
    const cwd = Io.Dir.cwd();
    const root_dir = try cwd.openDir(io, project.root_path, .{});
    defer root_dir.close(io);

    if (!fileExists(io, root_dir, project.default_scene)) {
        return ProjectError.MissingDefaultScene;
    }

    const scene = try loadSceneFile(io, allocator, root_dir, project.default_scene);
    defer freeScene(allocator, scene);

    var registry = try loadProjectScriptRegistry(io, allocator, project);
    defer registry.deinit();
    var schedule = buildProjectUpdateSchedule(allocator, registry) catch |err| switch (err) {
        ProjectError.InvalidScript => return ProjectError.InvalidScript,
        else => return err,
    };
    defer schedule.deinit();

    return .{ .project = project };
}

pub fn freeProject(allocator: std.mem.Allocator, project: Project) void {
    allocator.free(project.root_path);
    allocator.free(project.name);
    allocator.free(project.default_scene);
    freeStringList(allocator, project.scripts);
}

fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| {
        allocator.free(value);
    }
    allocator.free(values);
}

pub fn loadProject(io: Io, allocator: std.mem.Allocator, root_path: []const u8) !Project {
    const cwd = Io.Dir.cwd();
    const root_dir = cwd.openDir(io, root_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ProjectError.InvalidProject,
        else => return err,
    };
    defer root_dir.close(io);

    return loadProjectFile(io, allocator, root_path, root_dir);
}

pub fn loadDefaultScene(io: Io, allocator: std.mem.Allocator, project: Project) !Scene {
    const cwd = Io.Dir.cwd();
    const root_dir = try cwd.openDir(io, project.root_path, .{});
    defer root_dir.close(io);

    return loadSceneFile(io, allocator, root_dir, project.default_scene);
}

fn statProjectFile(io: Io, root_path: []const u8) !SourceFileStamp {
    const cwd = Io.Dir.cwd();
    const root_dir = cwd.openDir(io, root_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ProjectError.InvalidProject,
        else => return err,
    };
    defer root_dir.close(io);

    return statFile(io, root_dir, project_file_name, ProjectError.MissingProjectFile);
}

fn statProjectResource(io: Io, project: Project, path: []const u8, missing_error: ProjectError) !SourceFileStamp {
    const cwd = Io.Dir.cwd();
    const root_dir = try cwd.openDir(io, project.root_path, .{});
    defer root_dir.close(io);

    return statFile(io, root_dir, path, missing_error);
}

fn statProjectScripts(io: Io, allocator: std.mem.Allocator, project: Project) ![]LoadedSource {
    const sources = try allocator.alloc(LoadedSource, project.scripts.len);
    errdefer allocator.free(sources);

    var initialized: usize = 0;
    errdefer {
        for (sources[0..initialized]) |source| {
            allocator.free(source.path);
        }
    }

    for (project.scripts, 0..) |script_path, index| {
        sources[index] = .{
            .path = try allocator.dupe(u8, script_path),
            .stamp = try statProjectResource(io, project, script_path, ProjectError.MissingScript),
        };
        initialized += 1;
    }

    return sources;
}

fn freeLoadedSources(allocator: std.mem.Allocator, sources: []LoadedSource) void {
    for (sources) |source| {
        allocator.free(source.path);
    }
    allocator.free(sources);
}

fn statFile(io: Io, dir: Io.Dir, path: []const u8, missing_error: ProjectError) !SourceFileStamp {
    const stat = dir.statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return missing_error,
        else => return err,
    };
    return .{
        .size = stat.size,
        .mtime = stat.mtime,
    };
}

pub fn freeScene(allocator: std.mem.Allocator, scene: Scene) void {
    allocator.free(scene.name);
    var world = scene.world;
    world.deinit();
}

fn loadProjectFile(io: Io, allocator: std.mem.Allocator, root_path: []const u8, root_dir: Io.Dir) !Project {
    const contents = root_dir.readFileAlloc(io, project_file_name, allocator, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return ProjectError.MissingProjectFile,
        else => return err,
    };
    defer allocator.free(contents);

    const name = try readRequiredString(allocator, contents, "name") orelse return ProjectError.InvalidProjectName;
    errdefer allocator.free(name);

    const default_scene = try readRequiredString(allocator, contents, "default_scene") orelse return ProjectError.InvalidDefaultScene;
    errdefer allocator.free(default_scene);
    if (!isSafeProjectRelativePath(default_scene)) {
        return ProjectError.InvalidDefaultScene;
    }

    const scripts = try readOptionalStringArray(allocator, contents, "scripts");
    errdefer freeStringList(allocator, scripts);
    for (scripts) |script_path| {
        if (!isSafeProjectRelativePath(script_path)) {
            return ProjectError.InvalidScript;
        }
    }

    const version_value = readRequiredInt(contents, "version") orelse return ProjectError.UnsupportedProjectVersion;
    if (version_value != 1) {
        return ProjectError.UnsupportedProjectVersion;
    }

    return .{
        .root_path = try allocator.dupe(u8, root_path),
        .name = name,
        .default_scene = default_scene,
        .scripts = scripts,
    };
}

pub fn loadProjectScriptRegistry(io: Io, allocator: std.mem.Allocator, project: Project) !ComponentRegistry {
    const cwd = Io.Dir.cwd();
    const root_dir = try cwd.openDir(io, project.root_path, .{});
    defer root_dir.close(io);

    return script.loadProjectRegistry(io, allocator, root_dir, project.scripts) catch |err| switch (err) {
        error.FileNotFound => ProjectError.MissingScript,
        error.InvalidFieldName,
        error.DuplicateComponentField,
        error.DuplicateComponentType,
        error.DuplicateSystemType,
        error.UnknownComponentType,
        error.DuplicateSystemAccess,
        error.InvalidTypeId,
        error.ReservedTypeId,
        error.InvalidScript,
        error.UnsupportedScript,
        error.UnknownFieldType,
        error.UnknownSystemPhase,
        => ProjectError.InvalidScript,
        else => err,
    };
}

fn buildProjectUpdateSchedule(allocator: std.mem.Allocator, registry: ComponentRegistry) !SystemSchedule {
    return script.buildUpdateSchedule(allocator, registry) catch |err| switch (err) {
        error.CyclicSystemOrder => ProjectError.InvalidScript,
        else => err,
    };
}

fn loadSceneFile(io: Io, allocator: std.mem.Allocator, root_dir: Io.Dir, scene_path: []const u8) !Scene {
    const contents = root_dir.readFileAlloc(io, scene_path, allocator, .limited(256 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return ProjectError.MissingDefaultScene,
        else => return err,
    };
    defer allocator.free(contents);

    const name = try readRequiredRootString(allocator, contents, "name") orelse return ProjectError.InvalidProject;
    errdefer allocator.free(name);

    const version_value = readRequiredRootInt(contents, "version") orelse return ProjectError.UnsupportedProjectVersion;
    if (version_value != 1) {
        return ProjectError.UnsupportedProjectVersion;
    }

    var parser = SceneParser{
        .allocator = allocator,
        .world = World.init(allocator),
    };
    return .{
        .name = name,
        .world = try parser.parse(contents),
    };
}

const SceneParser = struct {
    allocator: std.mem.Allocator,
    world: World,
    active_entity: ?EntityDraft = null,

    fn parse(self: *SceneParser, contents: []const u8) !World {
        errdefer self.world.deinit();

        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') {
                continue;
            }

            if (std.mem.eql(u8, trimmed, "[[entities]]")) {
                try self.flushEntity();
                self.active_entity = .{};
                continue;
            }

            if (trimmed[0] == '[') {
                return ProjectError.InvalidSceneEntity;
            }

            if (self.active_entity) |*entity| {
                try entity.readProperty(trimmed);
            }
        }

        try self.flushEntity();
        if (self.world.entityCount() == 0) {
            return ProjectError.MissingSceneContent;
        }

        const world = self.world;
        self.world = World.init(self.allocator);
        return world;
    }

    fn flushEntity(self: *SceneParser) !void {
        const entity = self.active_entity orelse return;
        self.active_entity = null;
        if (!entity.id_seen or !entity.name_seen or !entity.kind_seen or !entity.kind_cube) {
            return ProjectError.InvalidSceneEntity;
        }
        const handle = self.world.createEntity(entity.id, entity.name) catch |err| switch (err) {
            runtime.WorldError.DuplicateEntityId => return ProjectError.DuplicateSceneEntityId,
            else => return err,
        };
        try self.world.setTransform(handle, entity.transform);
        try self.world.setCubeRenderer(handle, entity.cube_renderer);
        try self.world.setSpin(handle, entity.spin);
    }
};

const EntityDraft = struct {
    id_seen: bool = false,
    name_seen: bool = false,
    kind_seen: bool = false,
    kind_cube: bool = false,
    id: []const u8 = "",
    name: []const u8 = "",
    transform: Transform = .{},
    cube_renderer: CubeRenderer = .{},
    spin: Spin = .{},

    fn readProperty(self: *EntityDraft, line: []const u8) !void {
        const eq_index = std.mem.indexOfScalar(u8, line, '=') orelse return ProjectError.InvalidSceneEntity;
        const key = std.mem.trim(u8, line[0..eq_index], " \t");
        const value = std.mem.trim(u8, line[eq_index + 1 ..], " \t");

        if (std.mem.eql(u8, key, "id")) {
            self.id = stringValue(value) orelse return ProjectError.InvalidSceneEntity;
            self.id_seen = true;
        } else if (std.mem.eql(u8, key, "name")) {
            self.name = stringValue(value) orelse return ProjectError.InvalidSceneEntity;
            self.name_seen = true;
        } else if (std.mem.eql(u8, key, "kind")) {
            const kind = stringValue(value) orelse return ProjectError.InvalidSceneEntity;
            self.kind_seen = true;
            self.kind_cube = std.mem.eql(u8, kind, "cube");
        } else if (std.mem.eql(u8, key, "position")) {
            self.transform.position = try readVec3(value);
        } else if (std.mem.eql(u8, key, "rotation")) {
            self.transform.rotation = try readVec3(value);
        } else if (std.mem.eql(u8, key, "scale")) {
            self.transform.scale = try readVec3(value);
        } else if (std.mem.eql(u8, key, "color")) {
            self.cube_renderer.color = try readVec3(value);
        } else if (std.mem.eql(u8, key, "spin")) {
            self.spin.angular_velocity = try readVec3(value);
        } else {
            return ProjectError.InvalidSceneEntity;
        }
    }
};

fn stringValue(value: []const u8) ?[]const u8 {
    if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') {
        return null;
    }
    return value[1 .. value.len - 1];
}

fn readVec3(value: []const u8) ![3]f32 {
    if (value.len < 5 or value[0] != '[' or value[value.len - 1] != ']') {
        return ProjectError.InvalidSceneNumber;
    }

    var result: [3]f32 = undefined;
    var count: usize = 0;
    var parts = std.mem.splitScalar(u8, value[1 .. value.len - 1], ',');
    while (parts.next()) |part| {
        if (count >= result.len) {
            return ProjectError.InvalidSceneNumber;
        }
        const trimmed = std.mem.trim(u8, part, " \t\r");
        if (trimmed.len == 0) {
            return ProjectError.InvalidSceneNumber;
        }
        result[count] = std.fmt.parseFloat(f32, trimmed) catch return ProjectError.InvalidSceneNumber;
        count += 1;
    }

    if (count != result.len) {
        return ProjectError.InvalidSceneNumber;
    }
    return result;
}

fn readRequiredString(allocator: std.mem.Allocator, contents: []const u8, key: []const u8) !?[]const u8 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const found_key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, found_key, key)) {
            continue;
        }

        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') {
            return null;
        }
        return try decodeTomlBasicString(allocator, value[1 .. value.len - 1]);
    }

    return null;
}

fn readOptionalStringArray(allocator: std.mem.Allocator, contents: []const u8, key: []const u8) ![]const []const u8 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const found_key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, found_key, key)) {
            continue;
        }

        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        if (value.len < 2 or value[0] != '[' or value[value.len - 1] != ']') {
            return ProjectError.InvalidProject;
        }

        var strings: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (strings.items) |string| {
                allocator.free(string);
            }
            strings.deinit(allocator);
        }

        var index: usize = 1;
        while (index < value.len - 1) {
            while (index < value.len - 1 and (value[index] == ' ' or value[index] == '\t' or value[index] == ',')) {
                index += 1;
            }
            if (index >= value.len - 1) {
                break;
            }
            if (value[index] != '"') {
                return ProjectError.InvalidProject;
            }
            index += 1;
            const start = index;
            var escaped = false;
            while (index < value.len - 1) : (index += 1) {
                if (escaped) {
                    escaped = false;
                    continue;
                }
                if (value[index] == '\\') {
                    escaped = true;
                    continue;
                }
                if (value[index] == '"') {
                    break;
                }
            }
            if (index >= value.len - 1 or value[index] != '"') {
                return ProjectError.InvalidProject;
            }

            try strings.append(allocator, try decodeTomlBasicString(allocator, value[start..index]));
            index += 1;

            while (index < value.len - 1 and (value[index] == ' ' or value[index] == '\t')) {
                index += 1;
            }
            if (index < value.len - 1 and value[index] != ',') {
                return ProjectError.InvalidProject;
            }
        }

        return try strings.toOwnedSlice(allocator);
    }

    return try allocator.alloc([]const u8, 0);
}

fn readRequiredRootString(allocator: std.mem.Allocator, contents: []const u8, key: []const u8) !?[]const u8 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }
        if (trimmed[0] == '[') {
            break;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const found_key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, found_key, key)) {
            continue;
        }

        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') {
            return null;
        }
        return try decodeTomlBasicString(allocator, value[1 .. value.len - 1]);
    }

    return null;
}

fn encodeTomlBasicString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    for (value) |byte| {
        switch (byte) {
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '"' => try out.appendSlice(allocator, "\\\""),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, byte),
        }
    }

    return try out.toOwnedSlice(allocator);
}

fn decodeTomlBasicString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        const byte = value[index];
        if (byte != '\\') {
            try out.append(allocator, byte);
            continue;
        }

        index += 1;
        if (index >= value.len) {
            return ProjectError.InvalidProject;
        }

        switch (value[index]) {
            '\\' => try out.append(allocator, '\\'),
            '"' => try out.append(allocator, '"'),
            'n' => try out.append(allocator, '\n'),
            'r' => try out.append(allocator, '\r'),
            't' => try out.append(allocator, '\t'),
            else => return ProjectError.InvalidProject,
        }
    }

    return try out.toOwnedSlice(allocator);
}

fn hasRequiredString(contents: []const u8, key: []const u8) bool {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const found_key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, found_key, key)) {
            continue;
        }

        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        return value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"';
    }

    return false;
}

fn readRequiredInt(contents: []const u8, key: []const u8) ?u32 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const found_key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, found_key, key)) {
            continue;
        }

        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        return std.fmt.parseInt(u32, value, 10) catch null;
    }

    return null;
}

fn readRequiredRootInt(contents: []const u8, key: []const u8) ?u32 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }
        if (trimmed[0] == '[') {
            break;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const found_key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, found_key, key)) {
            continue;
        }

        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        return std.fmt.parseInt(u32, value, 10) catch null;
    }

    return null;
}

fn isSafeProjectRelativePath(path: []const u8) bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, '\\') != null) {
        return false;
    }

    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) {
            return false;
        }
    }

    return true;
}

fn fileExists(io: Io, dir: Io.Dir, path: []const u8) bool {
    dir.access(io, path, .{}) catch return false;
    return true;
}

test "initProject creates project metadata and default scene" {
    const root_path = ".zig-cache/test-init-project";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Demo");

    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try std.testing.expect(fileExists(io, root_dir, project_file_name));
    try std.testing.expect(fileExists(io, root_dir, default_scene_path));
}

test "checkProject validates a project directory" {
    const root_path = ".zig-cache/test-check-project";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");

    const result = try checkProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, result.project);

    try std.testing.expectEqualStrings("Game", result.project.name);
    try std.testing.expectEqualStrings(default_scene_path, result.project.default_scene);
}

test "loadDefaultScene reads cube entities from scene data" {
    const root_path = ".zig-cache/test-load-scene-data";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");

    const result = try checkProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, result.project);

    const scene = try loadDefaultScene(io, std.testing.allocator, result.project);
    defer freeScene(std.testing.allocator, scene);

    try std.testing.expectEqualStrings("Main", scene.name);
    try std.testing.expectEqual(@as(usize, 1), scene.entityCount());
    try std.testing.expectEqual(@as(usize, 1), scene.renderableCubeCount());

    const entity = scene.world.findEntityById("018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001") orelse return error.TestExpectedEqual;
    const cube = scene.world.renderableCubeAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(entity.index, cube.entity.index);
    try std.testing.expectEqual(@as(f32, 0.56), cube.color[1]);
}

test "checkProject rejects invalid scene numeric data" {
    const root_path = ".zig-cache/test-invalid-scene-number";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try root_dir.writeFile(io, .{
        .sub_path = default_scene_path,
        .data =
        \\name = "Main"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001"
        \\name = "Bad Cube"
        \\kind = "cube"
        \\position = [0.0, nope, 0.0]
        \\
        ,
    });

    try std.testing.expectError(
        ProjectError.InvalidSceneNumber,
        checkProject(io, std.testing.allocator, root_path),
    );
}

test "checkProject rejects duplicate scene entity ids" {
    const root_path = ".zig-cache/test-duplicate-scene-entity-id";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try root_dir.writeFile(io, .{
        .sub_path = default_scene_path,
        .data =
        \\name = "Main"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "same-id"
        \\name = "One"
        \\kind = "cube"
        \\
        \\[[entities]]
        \\id = "same-id"
        \\name = "Two"
        \\kind = "cube"
        \\
        ,
    });

    try std.testing.expectError(
        ProjectError.DuplicateSceneEntityId,
        checkProject(io, std.testing.allocator, root_path),
    );
}

test "checkProject validates script declarations and builds a system schedule" {
    const root_path = ".zig-cache/test-project-scripts";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try root_dir.createDirPath(io, "scripts");

    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n",
    });
    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\ecs.component("health", {
        \\  fields = {
        \\    current = "f32",
        \\    max = "f32",
        \\  },
        \\})
        \\
        \\ecs.system("observe_health", {
        \\  reads = { "health" },
        \\})
        \\
        \\ecs.system("health_regen", {
        \\  writes = { "health" },
        \\  after = { "observe_health" },
        \\})
        ,
    });

    const result = try checkProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, result.project);

    var registry = try loadProjectScriptRegistry(io, std.testing.allocator, result.project);
    defer registry.deinit();
    var schedule = try buildProjectUpdateSchedule(std.testing.allocator, registry);
    defer schedule.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.project.scripts.len);
    try std.testing.expect(registry.findComponent("health") != null);
    try std.testing.expect(registry.findSystem("health_regen") != null);
    try std.testing.expectEqual(@as(usize, 2), schedule.batchCount());
}

test "checkProject rejects invalid script declarations" {
    const root_path = ".zig-cache/test-invalid-project-script";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try root_dir.createDirPath(io, "scripts");

    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n",
    });
    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\ecs.component("machina.bad", {
        \\  fields = {
        \\    value = "f32",
        \\  },
        \\})
        ,
    });

    try std.testing.expectError(ProjectError.InvalidScript, checkProject(io, std.testing.allocator, root_path));
}

test "LiveProject reloads changed active scene and keeps last good state on failure" {
    const root_path = ".zig-cache/test-live-scene-reload";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();
    try std.testing.expectEqual(@as(usize, 1), live_project.scene.entityCount());
    try std.testing.expectEqual(ReloadResult.unchanged, try live_project.pollLoadedSources());

    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try root_dir.writeFile(io, .{
        .sub_path = default_scene_path,
        .data =
        \\name = "Main"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "one"
        \\name = "One"
        \\kind = "cube"
        \\
        \\[[entities]]
        \\id = "two"
        \\name = "Two"
        \\kind = "cube"
        \\
        ,
    });

    const reload = try live_project.pollLoadedSources();
    try std.testing.expect(!reload.reloaded.project_reloaded);
    try std.testing.expect(reload.reloaded.scene_reloaded);
    try std.testing.expectEqual(@as(usize, 2), reload.reloaded.entity_count);
    try std.testing.expectEqual(@as(usize, 2), live_project.scene.entityCount());

    try root_dir.writeFile(io, .{
        .sub_path = default_scene_path,
        .data =
        \\name = "Main"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "same"
        \\name = "One"
        \\kind = "cube"
        \\
        \\[[entities]]
        \\id = "same"
        \\name = "Two"
        \\kind = "cube"
        \\
        ,
    });

    try std.testing.expectError(ProjectError.DuplicateSceneEntityId, live_project.pollLoadedSources());
    try std.testing.expectEqual(@as(usize, 2), live_project.scene.entityCount());
    try std.testing.expectEqual(ReloadResult.unchanged, try live_project.pollLoadedSources());
}

test "LiveProject reloads changed scripts and keeps last good registry on failure" {
    const root_path = ".zig-cache/test-live-script-reload";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try root_dir.createDirPath(io, "scripts");

    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n",
    });
    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\ecs.component("health", {
        \\  fields = {
        \\    current = "f32",
        \\  },
        \\})
        \\
        \\ecs.system("observe_health", {
        \\  reads = { "health" },
        \\})
        ,
    });

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();
    try std.testing.expect(live_project.registry.findComponent("health") != null);
    try std.testing.expect(live_project.registry.findComponent("mood") == null);
    try std.testing.expectEqual(@as(usize, 1), live_project.schedule.systemCount());

    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\ecs.component("health", {
        \\  fields = {
        \\    current = "f32",
        \\  },
        \\})
        \\
        \\ecs.component("mood", {
        \\  fields = {
        \\    value = "string",
        \\  },
        \\})
        \\
        \\ecs.system("observe_health", {
        \\  reads = { "health" },
        \\})
        \\
        \\ecs.system("observe_mood", {
        \\  reads = { "mood" },
        \\})
        ,
    });

    const reload = try live_project.pollLoadedSources();
    try std.testing.expect(!reload.reloaded.project_reloaded);
    try std.testing.expect(!reload.reloaded.scene_reloaded);
    try std.testing.expect(reload.reloaded.scripts_reloaded);
    try std.testing.expect(live_project.registry.findComponent("mood") != null);
    try std.testing.expectEqual(@as(usize, 2), live_project.schedule.systemCount());

    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\ecs.component("machina.bad", {
        \\  fields = {
        \\    value = "f32",
        \\  },
        \\})
        ,
    });

    try std.testing.expectError(ProjectError.InvalidScript, live_project.pollLoadedSources());
    try std.testing.expect(live_project.registry.findComponent("mood") != null);
    try std.testing.expectEqual(@as(usize, 2), live_project.schedule.systemCount());
    try std.testing.expectEqual(ReloadResult.unchanged, try live_project.pollLoadedSources());
}

test "LiveProject reloads project metadata and follows default scene changes" {
    const root_path = ".zig-cache/test-live-project-reload";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");

    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try root_dir.writeFile(io, .{
        .sub_path = "scenes/alternate.scene.toml",
        .data =
        \\name = "Alternate"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "alternate-one"
        \\name = "Alternate One"
        \\kind = "cube"
        \\
        \\[[entities]]
        \\id = "alternate-two"
        \\name = "Alternate Two"
        \\kind = "cube"
        \\
        ,
    });

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();
    try std.testing.expectEqualStrings(default_scene_path, live_project.project.default_scene);
    try std.testing.expectEqual(@as(usize, 1), live_project.scene.entityCount());

    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Game Reloaded\"\nversion = 1\ndefault_scene = \"scenes/alternate.scene.toml\"\n",
    });

    const project_reload = try live_project.pollLoadedSources();
    try std.testing.expect(project_reload.reloaded.project_reloaded);
    try std.testing.expect(project_reload.reloaded.scene_reloaded);
    try std.testing.expectEqualStrings("Game Reloaded", live_project.project.name);
    try std.testing.expectEqualStrings("scenes/alternate.scene.toml", live_project.project.default_scene);
    try std.testing.expectEqual(@as(usize, 2), live_project.scene.entityCount());

    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Broken Game\"\nversion = 1\ndefault_scene = \"scenes/missing.scene.toml\"\n",
    });

    try std.testing.expectError(ProjectError.MissingDefaultScene, live_project.pollLoadedSources());
    try std.testing.expectEqualStrings("Game Reloaded", live_project.project.name);
    try std.testing.expectEqualStrings("scenes/alternate.scene.toml", live_project.project.default_scene);
    try std.testing.expectEqual(@as(usize, 2), live_project.scene.entityCount());
    try std.testing.expectEqual(ReloadResult.unchanged, try live_project.pollLoadedSources());

    try root_dir.writeFile(io, .{
        .sub_path = "scenes/alternate.scene.toml",
        .data =
        \\name = "Alternate"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "alternate-one"
        \\name = "Alternate One"
        \\kind = "cube"
        \\
        ,
    });

    const fallback_scene_reload = try live_project.pollLoadedSources();
    try std.testing.expect(!fallback_scene_reload.reloaded.project_reloaded);
    try std.testing.expectEqualStrings("Game Reloaded", live_project.project.name);
    try std.testing.expectEqualStrings("scenes/alternate.scene.toml", live_project.project.default_scene);
    try std.testing.expectEqual(@as(usize, 1), live_project.scene.entityCount());

    try root_dir.writeFile(io, .{
        .sub_path = "scenes/missing.scene.toml",
        .data =
        \\name = "Recovered"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "recovered-one"
        \\name = "Recovered One"
        \\kind = "cube"
        \\
        ,
    });

    const recovered_reload = try live_project.pollLoadedSources();
    try std.testing.expect(recovered_reload.reloaded.project_reloaded);
    try std.testing.expectEqualStrings("Broken Game", live_project.project.name);
    try std.testing.expectEqualStrings("scenes/missing.scene.toml", live_project.project.default_scene);
    try std.testing.expectEqual(@as(usize, 1), live_project.scene.entityCount());
}

test "initProject escapes project names in metadata" {
    const root_path = ".zig-cache/test-escaped-project-name";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Agent \"One\"");

    const result = try checkProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, result.project);

    try std.testing.expectEqualStrings("Agent \"One\"", result.project.name);
}

test "checkProject rejects default scenes outside the project" {
    const root_path = ".zig-cache/test-scene-escape";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try cwd.createDirPath(io, root_path);
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Game\"\nversion = 1\ndefault_scene = \"../outside.scene.toml\"\n",
    });

    try std.testing.expectError(
        ProjectError.InvalidDefaultScene,
        checkProject(io, std.testing.allocator, root_path),
    );
}

test "checkProject rejects platform separators in project resource paths" {
    const root_path = ".zig-cache/test-scene-backslash";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try cwd.createDirPath(io, root_path);
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes\\\\main.scene.toml\"\n",
    });

    try std.testing.expectError(
        ProjectError.InvalidDefaultScene,
        checkProject(io, std.testing.allocator, root_path),
    );
}

test "checkProject rejects unsupported metadata version" {
    const root_path = ".zig-cache/test-unsupported-version";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try cwd.createDirPath(io, root_path);
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Game\"\nversion = 99\ndefault_scene = \"scenes/main.scene.toml\"\n",
    });

    try std.testing.expectError(
        ProjectError.UnsupportedProjectVersion,
        loadProjectFile(io, std.testing.allocator, ".", root_dir),
    );
}
