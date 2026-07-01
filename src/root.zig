const std = @import("std");
const Io = std.Io;
const render = @import("render.zig");
const render_verify = @import("render_verify.zig");
const runtime = @import("runtime.zig");

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
pub const verifyRenderBmp = render_verify.verifyBmp;

pub const Project = struct {
    root_path: []const u8,
    name: []const u8,
    default_scene: []const u8,
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
    const cwd = Io.Dir.cwd();
    const root_dir = cwd.openDir(io, root_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ProjectError.InvalidProject,
        else => return err,
    };
    defer root_dir.close(io);

    const project = try loadProjectFile(io, allocator, root_path, root_dir);
    errdefer freeProject(allocator, project);
    if (!fileExists(io, root_dir, project.default_scene)) {
        return ProjectError.MissingDefaultScene;
    }

    const scene = try loadSceneFile(io, allocator, root_dir, project.default_scene);
    defer freeScene(allocator, scene);

    return .{ .project = project };
}

pub fn freeProject(allocator: std.mem.Allocator, project: Project) void {
    allocator.free(project.root_path);
    allocator.free(project.name);
    allocator.free(project.default_scene);
}

pub fn loadDefaultScene(io: Io, allocator: std.mem.Allocator, project: Project) !Scene {
    const cwd = Io.Dir.cwd();
    const root_dir = try cwd.openDir(io, project.root_path, .{});
    defer root_dir.close(io);

    return loadSceneFile(io, allocator, root_dir, project.default_scene);
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

    const version_value = readRequiredInt(contents, "version") orelse return ProjectError.UnsupportedProjectVersion;
    if (version_value != 1) {
        return ProjectError.UnsupportedProjectVersion;
    }

    return .{
        .root_path = try allocator.dupe(u8, root_path),
        .name = name,
        .default_scene = default_scene,
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
