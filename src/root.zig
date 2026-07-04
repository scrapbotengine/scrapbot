const std = @import("std");
const Io = std.Io;
const render = @import("render.zig");
const render_verify = @import("render_verify.zig");
const geometry = @import("geometry.zig");
const native = @import("native.zig");
const runtime = @import("runtime.zig");
const script = @import("script.zig");
const ui_layout = @import("ui_layout.zig");

pub const version = "0.1.0-dev";
pub const project_file_name = "project.machina.toml";
pub const default_scene_path = "scenes/main.scene.toml";

pub const renderDemoBmp = render.renderDemoBmp;
pub const renderStats = render.stats;
pub const runDemoWindow = render.runDemoWindow;
pub const WindowOptions = render.WindowOptions;
pub const FrameInput = render.FrameInput;
pub const PointerInput = render.PointerInput;
pub const EditorFrameState = render.EditorFrameState;
pub const EditorState = render.EditorState;
pub const RenderScene = render.Scene;
pub const RenderStats = render.Stats;
pub const RenderVerification = render_verify.Verification;
pub const RenderVerificationOptions = render_verify.VerificationOptions;
pub const World = runtime.World;
pub const EntityHandle = runtime.EntityHandle;
pub const Transform = runtime.Transform;
pub const CubeRenderer = runtime.CubeRenderer;
pub const GeometryPrimitive = runtime.GeometryPrimitive;
pub const SurfaceMaterial = runtime.SurfaceMaterial;
pub const Camera = runtime.Camera;
pub const DirectionalLight = runtime.DirectionalLight;
pub const UiRect = runtime.UiRectComponent;
pub const UiText = runtime.UiTextComponent;
pub const UiCommand = runtime.UiCommandComponent;
pub const UiCommandEvent = runtime.UiCommandEvent;
pub const InputPointer = runtime.InputPointerComponent;
pub const InputKeyboard = runtime.InputKeyboardComponent;
pub const InputFrame = runtime.InputFrameComponent;
pub const Spin = runtime.Spin;
pub const PrimitiveGeometry = geometry.Primitive;
pub const GeometryMesh = geometry.Mesh;
pub const ComponentRegistry = runtime.ComponentRegistry;
pub const ComponentDefinition = runtime.ComponentDefinition;
pub const ComponentFieldDefinition = runtime.ComponentFieldDefinition;
pub const ComponentValue = runtime.ComponentValue;
pub const FieldType = runtime.FieldType;
pub const SystemDefinition = runtime.SystemDefinition;
pub const SystemPhase = runtime.SystemPhase;
pub const SystemSchedule = runtime.SystemSchedule;
pub const SystemProfileSnapshot = runtime.SystemProfileSnapshot;
pub const ScheduleError = runtime.ScheduleError;
pub const TypeIdError = runtime.TypeIdError;
pub const RegistryError = runtime.RegistryError;
pub const ScriptError = script.ScriptError;
pub const ScriptProgram = script.Program;
pub const ScriptDiagnostic = script.Diagnostic;
pub const ScriptDiagnosticPosition = script.DiagnosticPosition;
pub const NativeExtension = script.NativeExtension;
pub const NativeSystemContext = script.NativeSystemContext;
pub const NativeSystemFn = script.NativeSystemFn;
pub const NativeSystemRegistration = script.NativeSystemRegistration;
pub const loadProjectProgramDetailedWithNative = script.loadProjectProgramDetailedWithNative;
pub const loadSourceProgramWithNative = script.loadSourceProgramWithNative;
pub const validateTypeId = runtime.validateTypeId;
pub const validateProjectTypeId = runtime.validateProjectTypeId;
pub const validatePackageTypeId = runtime.validatePackageTypeId;
pub const validateEngineTypeId = runtime.validateEngineTypeId;
pub const verifyRenderBmp = render_verify.verifyBmp;
pub const writeFrameInput = render.writeFrameInput;

pub const Project = struct {
    root_path: []const u8,
    name: []const u8,
    default_scene: []const u8,
    scripts: []const []const u8,
    native: ?[]const u8 = null,
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

    pub fn componentInstanceCount(self: Scene) usize {
        return self.world.componentInstanceCount();
    }

    pub fn renderableCubeCount(self: Scene) usize {
        return self.world.renderableCubeCount();
    }

    pub fn renderableMeshCount(self: Scene) usize {
        return self.world.renderableMeshCount();
    }
};

pub const Diagnostic = struct {
    path: []const u8,
    message: []const u8,
};

pub const CheckResult = struct {
    project: Project,
    schedule: CheckSchedule,
};

pub const CheckDetailedResult = union(enum) {
    ok: CheckResult,
    invalid: ScriptDiagnostic,
};

pub const CheckSystemRunner = enum {
    none,
    luau,
    native,
};

pub const CheckSystemSummary = struct {
    id: []const u8,
    phase: SystemPhase,
    runner: CheckSystemRunner,
    reads: []const []const u8 = &.{},
    writes: []const []const u8 = &.{},
    before: []const []const u8 = &.{},
    after: []const []const u8 = &.{},
};

pub const CheckScheduleBatch = struct {
    phase: SystemPhase,
    systems: []const CheckSystemSummary,
};

pub const CheckSchedule = struct {
    batches: []const CheckScheduleBatch = &.{},

    pub fn batchCount(self: CheckSchedule) usize {
        return self.batches.len;
    }

    pub fn systemCount(self: CheckSchedule) usize {
        var count: usize = 0;
        for (self.batches) |batch| {
            count += batch.systems.len;
        }
        return count;
    }
};

pub const StepOptions = struct {
    frames: u32 = 1,
    delta_seconds: f32 = 1.0 / 60.0,
};

pub const StepSummary = struct {
    frames: u32,
    completed_frames: u32,
    delta_seconds: f32,
};

pub const StepOk = struct {
    project: Project,
    scene: Scene,
    schedule: CheckSchedule,
    summary: StepSummary,
};

pub const StepRuntimeError = struct {
    project: Project,
    scene: Scene,
    schedule: CheckSchedule,
    summary: StepSummary,
    diagnostic: ScriptDiagnostic,
};

pub const StepDetailedResult = union(enum) {
    ok: StepOk,
    runtime_error: StepRuntimeError,
    invalid: ScriptDiagnostic,
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
    native_reloaded: bool,
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
    scripts: ScriptProgram,
    project_source: LoadedSource,
    scene_source: LoadedSource,
    script_sources: []LoadedSource,
    native_source: ?LoadedSource = null,
    last_failed_project_stamp: ?SourceFileStamp = null,
    last_failed_scene_stamp: ?SourceFileStamp = null,
    last_failed_script_index: ?usize = null,
    last_failed_script_stamp: ?SourceFileStamp = null,
    last_failed_native_stamp: ?SourceFileStamp = null,
    last_diagnostic: ?ScriptDiagnostic = null,
    editor_state: EditorState = .{},
    startup_ran: bool = false,

    pub fn init(io: Io, allocator: std.mem.Allocator, root_path: []const u8) !LiveProject {
        const project = try loadProject(io, allocator, root_path);
        errdefer freeProject(allocator, project);

        var scripts = try loadProjectScripts(io, allocator, project);
        errdefer scripts.deinit();

        const scene = try loadDefaultSceneWithRegistry(io, allocator, project, scripts.registry);
        errdefer freeScene(allocator, scene);

        const script_sources = try statProjectScripts(io, allocator, project);
        errdefer freeLoadedSources(allocator, script_sources);
        const native_source = try statProjectNative(io, allocator, project);
        errdefer if (native_source) |source| freeLoadedSource(allocator, source);

        return .{
            .io = io,
            .allocator = allocator,
            .root_path = project.root_path,
            .project = project,
            .scene = scene,
            .scripts = scripts,
            .project_source = .{
                .path = project_file_name,
                .stamp = try statProjectFile(io, project.root_path),
            },
            .scene_source = .{
                .path = project.default_scene,
                .stamp = try statProjectResource(io, project, project.default_scene, ProjectError.MissingDefaultScene),
            },
            .script_sources = script_sources,
            .native_source = native_source,
        };
    }

    pub fn deinit(self: *LiveProject) void {
        self.clearLastDiagnostic();
        if (self.native_source) |source| {
            freeLoadedSource(self.allocator, source);
        }
        freeLoadedSources(self.allocator, self.script_sources);
        self.scripts.deinit();
        freeScene(self.allocator, self.scene);
        freeProject(self.allocator, self.project);
        self.* = undefined;
    }

    pub fn renderScene(self: *const LiveProject) RenderScene {
        return self.scene.renderScene();
    }

    pub fn systemProfileSnapshots(self: *LiveProject) []const SystemProfileSnapshot {
        return self.scripts.systemProfileSnapshots();
    }

    pub fn editorFrameState(self: *const LiveProject) EditorFrameState {
        return render.editorFrameState(&self.scene.world, self.editor_state);
    }

    pub fn update(self: *LiveProject, delta_seconds: f32) void {
        self.updateWithInput(delta_seconds, .{});
    }

    pub fn updateWithInput(self: *LiveProject, delta_seconds: f32, input: FrameInput) void {
        self.clearLastDiagnostic();
        if (!self.runStartup()) {
            return;
        }
        var editor_input = input;
        const render_profile_count = input.system_profile_count_hint;
        editor_input.delta_seconds = delta_seconds;
        editor_input.editor = self.editorFrameState();
        editor_input.system_profiles = self.systemProfileSnapshots();
        editor_input.system_profile_count_hint = editor_input.system_profiles.len + render_profile_count;

        var routed_input = editor_input;
        const editor_update = render.updateEditorState(self.allocator, &self.scene.world, &self.editor_state, editor_input) catch |err| {
            if (std.fmt.allocPrint(self.allocator, "Editor interaction failed: {s}", .{@errorName(err)})) |message| {
                defer self.allocator.free(message);
                self.last_diagnostic = makeSyntheticRuntimeDiagnostic(self.allocator, message) catch null;
            } else |_| {
                self.last_diagnostic = makeSyntheticRuntimeDiagnostic(self.allocator, "Editor interaction failed") catch null;
            }
            return;
        };
        routed_input.editor = self.editorFrameState();
        if (editor_update.consumed_pointer) {
            routed_input.pointer.primary_down = false;
            routed_input.pointer.primary_pressed = false;
            routed_input.pointer.primary_released = false;
            routed_input.pointer.wheel_delta = .{ 0.0, 0.0 };
        }
        render.writeFrameInput(&self.scene.world, routed_input) catch |err| {
            if (std.fmt.allocPrint(self.allocator, "Input routing failed: {s}", .{@errorName(err)})) |message| {
                defer self.allocator.free(message);
                self.last_diagnostic = makeSyntheticRuntimeDiagnostic(self.allocator, message) catch null;
            } else |_| {
                self.last_diagnostic = makeSyntheticRuntimeDiagnostic(self.allocator, "Input routing failed") catch null;
            }
            return;
        };
        updateSceneUiScrollViews(&self.scene.world) catch |err| {
            if (std.fmt.allocPrint(self.allocator, "UI scroll routing failed: {s}", .{@errorName(err)})) |message| {
                defer self.allocator.free(message);
                self.last_diagnostic = makeSyntheticRuntimeDiagnostic(self.allocator, message) catch null;
            } else |_| {
                self.last_diagnostic = makeSyntheticRuntimeDiagnostic(self.allocator, "UI scroll routing failed") catch null;
            }
            return;
        };
        updateUiCommandEvents(&self.scene.world) catch |err| {
            if (std.fmt.allocPrint(self.allocator, "UI command routing failed: {s}", .{@errorName(err)})) |message| {
                defer self.allocator.free(message);
                self.last_diagnostic = makeSyntheticRuntimeDiagnostic(self.allocator, message) catch null;
            } else |_| {
                self.last_diagnostic = makeSyntheticRuntimeDiagnostic(self.allocator, "UI command routing failed") catch null;
            }
            return;
        };
        if (self.editor_state.paused and !editor_update.step_once) {
            return;
        }
        if (!self.scripts.update(&self.scene.world, delta_seconds)) {
            if (self.scripts.last_diagnostic) |diagnostic| {
                self.last_diagnostic = cloneScriptDiagnostic(self.allocator, diagnostic) catch null;
            }
        }
    }

    pub fn runStartup(self: *LiveProject) bool {
        if (self.startup_ran) {
            return true;
        }
        if (!self.scripts.startup(&self.scene.world)) {
            if (self.scripts.last_diagnostic) |diagnostic| {
                self.last_diagnostic = cloneScriptDiagnostic(self.allocator, diagnostic) catch null;
            }
            return false;
        }
        self.startup_ran = true;
        return true;
    }

    pub fn lastDiagnostic(self: *const LiveProject) ?*const ScriptDiagnostic {
        return if (self.last_diagnostic) |*diagnostic| diagnostic else null;
    }

    fn clearLastDiagnostic(self: *LiveProject) void {
        if (self.last_diagnostic) |*diagnostic| {
            diagnostic.deinit(self.allocator);
            self.last_diagnostic = null;
        }
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

        return self.pollNativeSource();
    }

    fn pollNativeSource(self: *LiveProject) !ReloadResult {
        const loaded_native = self.native_source orelse return .unchanged;
        const native_path = self.project.native orelse return .unchanged;
        const native_stamp = try statProjectResource(self.io, self.project, native_path, ProjectError.MissingScript);
        if (native_stamp.eql(loaded_native.stamp)) {
            return .unchanged;
        }

        return self.reloadNative(native_stamp) catch |err| {
            if (self.last_failed_native_stamp) |failed_stamp| {
                if (failed_stamp.eql(native_stamp)) {
                    return .unchanged;
                }
            }
            self.last_failed_native_stamp = native_stamp;
            return err;
        };
    }

    fn reloadProject(self: *LiveProject, project_stamp: SourceFileStamp) !ReloadResult {
        self.clearLastDiagnostic();
        const next_project = try loadProject(self.io, self.allocator, self.root_path);
        errdefer freeProject(self.allocator, next_project);

        const next_scripts_result = try loadProjectScriptsDetailed(self.io, self.allocator, next_project);
        var next_scripts = switch (next_scripts_result) {
            .program => |program| program,
            .diagnostic => |diagnostic| {
                self.last_diagnostic = diagnostic;
                return ProjectError.InvalidScript;
            },
        };
        errdefer next_scripts.deinit();

        const next_scene = try loadDefaultSceneWithRegistry(self.io, self.allocator, next_project, next_scripts.registry);
        errdefer freeScene(self.allocator, next_scene);

        const next_script_sources = try statProjectScripts(self.io, self.allocator, next_project);
        errdefer freeLoadedSources(self.allocator, next_script_sources);
        const next_native_source = try statProjectNative(self.io, self.allocator, next_project);
        errdefer if (next_native_source) |source| freeLoadedSource(self.allocator, source);

        const scene_stamp = try statProjectResource(self.io, next_project, next_project.default_scene, ProjectError.MissingDefaultScene);
        const info = ReloadInfo{
            .project_reloaded = true,
            .scene_reloaded = true,
            .scripts_reloaded = true,
            .native_reloaded = next_project.native != null,
            .project_name = next_project.name,
            .scene_path = next_project.default_scene,
            .entity_count = next_scene.entityCount(),
            .renderable_cube_count = next_scene.renderableCubeCount(),
            .script_count = next_project.scripts.len,
            .system_batch_count = next_scripts.schedule.batchCount(),
        };

        freeLoadedSources(self.allocator, self.script_sources);
        if (self.native_source) |source| {
            freeLoadedSource(self.allocator, source);
        }
        self.scripts.deinit();
        freeScene(self.allocator, self.scene);
        freeProject(self.allocator, self.project);
        self.root_path = next_project.root_path;
        self.project = next_project;
        self.scene = next_scene;
        self.scripts = next_scripts;
        self.project_source.stamp = project_stamp;
        self.scene_source = .{
            .path = self.project.default_scene,
            .stamp = scene_stamp,
        };
        self.script_sources = next_script_sources;
        self.native_source = next_native_source;
        self.last_failed_project_stamp = null;
        self.last_failed_scene_stamp = null;
        self.last_failed_script_index = null;
        self.last_failed_script_stamp = null;
        self.last_failed_native_stamp = null;
        self.startup_ran = false;
        return .{ .reloaded = info };
    }

    fn reloadScene(self: *LiveProject, scene_stamp: SourceFileStamp) !ReloadResult {
        self.clearLastDiagnostic();
        const next_scene = try loadDefaultSceneWithRegistry(self.io, self.allocator, self.project, self.scripts.registry);
        const info = ReloadInfo{
            .project_reloaded = false,
            .scene_reloaded = true,
            .scripts_reloaded = false,
            .native_reloaded = false,
            .project_name = self.project.name,
            .scene_path = self.project.default_scene,
            .entity_count = next_scene.entityCount(),
            .renderable_cube_count = next_scene.renderableCubeCount(),
            .script_count = self.project.scripts.len,
            .system_batch_count = self.scripts.schedule.batchCount(),
        };

        freeScene(self.allocator, self.scene);
        self.scene = next_scene;
        self.scene_source.stamp = scene_stamp;
        self.last_failed_scene_stamp = null;
        self.startup_ran = false;
        return .{ .reloaded = info };
    }

    fn reloadScripts(self: *LiveProject, changed_index: usize, script_stamp: SourceFileStamp) !ReloadResult {
        self.clearLastDiagnostic();
        const next_scripts_result = try loadProjectScriptsDetailed(self.io, self.allocator, self.project);
        var next_scripts = switch (next_scripts_result) {
            .program => |program| program,
            .diagnostic => |diagnostic| {
                self.last_diagnostic = diagnostic;
                return ProjectError.InvalidScript;
            },
        };
        errdefer next_scripts.deinit();

        const checked_scene = try loadDefaultSceneWithRegistry(self.io, self.allocator, self.project, next_scripts.registry);
        defer freeScene(self.allocator, checked_scene);
        const refreshed_native_stamp = if (self.native_source) |source|
            try statProjectResource(self.io, self.project, source.path, ProjectError.MissingScript)
        else
            null;

        const info = ReloadInfo{
            .project_reloaded = false,
            .scene_reloaded = false,
            .scripts_reloaded = true,
            .native_reloaded = false,
            .project_name = self.project.name,
            .scene_path = self.project.default_scene,
            .entity_count = self.scene.entityCount(),
            .renderable_cube_count = self.scene.renderableCubeCount(),
            .script_count = self.project.scripts.len,
            .system_batch_count = next_scripts.schedule.batchCount(),
        };

        self.scripts.deinit();
        self.scripts = next_scripts;
        self.script_sources[changed_index].stamp = script_stamp;
        if (refreshed_native_stamp) |stamp| {
            if (self.native_source) |*source| {
                source.stamp = stamp;
            }
        }
        self.last_failed_script_index = null;
        self.last_failed_script_stamp = null;
        self.last_failed_native_stamp = null;
        return .{ .reloaded = info };
    }

    fn reloadNative(self: *LiveProject, native_stamp: SourceFileStamp) !ReloadResult {
        self.clearLastDiagnostic();
        const next_scripts_result = try loadProjectScriptsDetailed(self.io, self.allocator, self.project);
        var next_scripts = switch (next_scripts_result) {
            .program => |program| program,
            .diagnostic => |diagnostic| {
                self.last_diagnostic = diagnostic;
                return ProjectError.InvalidScript;
            },
        };
        errdefer next_scripts.deinit();

        const checked_scene = try loadDefaultSceneWithRegistry(self.io, self.allocator, self.project, next_scripts.registry);
        defer freeScene(self.allocator, checked_scene);

        const info = ReloadInfo{
            .project_reloaded = false,
            .scene_reloaded = false,
            .scripts_reloaded = true,
            .native_reloaded = true,
            .project_name = self.project.name,
            .scene_path = self.project.default_scene,
            .entity_count = self.scene.entityCount(),
            .renderable_cube_count = self.scene.renderableCubeCount(),
            .script_count = self.project.scripts.len,
            .system_batch_count = next_scripts.schedule.batchCount(),
        };

        self.scripts.deinit();
        self.scripts = next_scripts;
        if (self.native_source) |*source| {
            source.stamp = native_stamp;
        }
        self.last_failed_native_stamp = null;
        return .{ .reloaded = info };
    }
};

const UiCommandHit = struct {
    command: []const u8,
    source: []const u8,
};

fn updateSceneUiScrollViews(world: *World) !void {
    const input_entity = world.findEntityById(runtime.input_entity_id) orelse return;
    const ui_visible = try world.getBoolean(input_entity, runtime.input_frame_component_id, "ui_visible");
    const has_position = try world.getBoolean(input_entity, runtime.input_pointer_component_id, "has_position");
    const wheel_delta = try world.getVec3(input_entity, runtime.input_pointer_component_id, "wheel_delta");
    if (!ui_visible or !has_position or wheel_delta[1] == 0.0) {
        return;
    }

    const pointer_position_vec3 = try world.getVec3(input_entity, runtime.input_pointer_component_id, "position");
    const pointer_position = try sceneUiPointerPosition(world, input_entity, .{ pointer_position_vec3[0], pointer_position_vec3[1] });
    _ = try routeUiScrollWheelAt(world, pointer_position, wheel_delta[1], 24.0);
}

fn updateUiCommandEvents(world: *World) !void {
    try clearUiCommandEvent(world);
    const input_entity = world.findEntityById(runtime.input_entity_id) orelse return;
    const ui_visible = try world.getBoolean(input_entity, runtime.input_frame_component_id, "ui_visible");
    const has_position = try world.getBoolean(input_entity, runtime.input_pointer_component_id, "has_position");
    const primary_released = try world.getBoolean(input_entity, runtime.input_pointer_component_id, "primary_released");
    if (!ui_visible or !has_position or !primary_released) {
        return;
    }
    const pointer_position_vec3 = try world.getVec3(input_entity, runtime.input_pointer_component_id, "position");
    const pointer_position = try sceneUiPointerPosition(world, input_entity, .{ pointer_position_vec3[0], pointer_position_vec3[1] });

    var selected: ?UiCommandHit = null;
    var cursor: usize = 0;
    const command_button_query = [_][]const u8{
        runtime.ui_rect_component_id,
        runtime.ui_button_component_id,
        runtime.ui_command_component_id,
    };
    while (world.queryNext(&command_button_query, &cursor)) |entity| {
        const position = try world.getVec3(entity, runtime.ui_rect_component_id, "position");
        const size = try world.getVec3(entity, runtime.ui_rect_component_id, "size");
        if ((try hitTestUiRect(world, entity, position, size, pointer_position)) == null) {
            continue;
        }

        const stored_entity = try world.entity(entity);
        selected = .{
            .command = try world.getString(entity, runtime.ui_command_component_id, "command"),
            .source = stored_entity.id,
        };
    }

    if (selected) |hit| {
        try emitUiCommandEvent(world, hit.command, hit.source);
    }
}

fn resolveUiLayout(world: *World, entity: runtime.EntityHandle, local_position: [3]f32) !ui_layout.ResolvedLayout {
    return ui_layout.resolve(world, entity, local_position) catch |err| return mapLayoutError(err);
}

fn resolveUiRect(world: *World, entity: runtime.EntityHandle, local_position: [3]f32, size: [3]f32) !ui_layout.ResolvedRect {
    return ui_layout.resolvedRect(world, entity, local_position, size) catch |err| return mapLayoutError(err);
}

fn hitTestUiRect(world: *World, entity: runtime.EntityHandle, local_position: [3]f32, size: [3]f32, point: [2]f32) !?ui_layout.ResolvedRect {
    return ui_layout.hitTestRect(world, entity, local_position, size, point) catch |err| return mapLayoutError(err);
}

fn sceneUiPointerPosition(world: *World, input_entity: runtime.EntityHandle, pointer_position: [2]f32) ![2]f32 {
    const debug_overlay_visible = try world.getBoolean(input_entity, runtime.input_frame_component_id, "debug_overlay_visible");
    const viewport = try world.getVec3(input_entity, runtime.input_frame_component_id, "viewport");
    return ui_layout.pointerToDesign(world, sceneUiTarget(viewport, debug_overlay_visible), pointer_position) catch |err| return mapLayoutError(err);
}

fn sceneUiTarget(viewport: [3]f32, debug_overlay_visible: bool) ui_layout.Target {
    if (debug_overlay_visible) {
        const bounds = render.editorGameViewportBounds(.{
            .debug_overlay_visible = true,
            .viewport_width = viewport[0],
            .viewport_height = viewport[1],
        });
        return .{ .x = bounds.x, .y = bounds.y, .width = bounds.width, .height = bounds.height };
    }
    return .{ .width = viewport[0], .height = viewport[1] };
}

fn routeUiScrollWheelAt(world: *World, pointer_position: [2]f32, wheel_delta_y: f32, pixels_per_wheel: f32) anyerror!?ui_layout.ScrollWheelRoute {
    return ui_layout.applyScrollWheelAt(world, pointer_position, wheel_delta_y, pixels_per_wheel) catch |err| return mapLayoutError(err);
}

fn mapLayoutError(err: anyerror) anyerror {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => ProjectError.InvalidSceneEntity,
    };
}

fn clearUiCommandEvent(world: *World) !void {
    const event_entity = world.findEntityById(runtime.ui_command_event_entity_id) orelse return;
    _ = try world.removeComponent(event_entity, runtime.ui_command_event_component_id);
}

fn emitUiCommandEvent(world: *World, command: []const u8, source: []const u8) !void {
    const event_entity = world.findEntityById(runtime.ui_command_event_entity_id) orelse try world.createEntity(runtime.ui_command_event_entity_id, "UI Command Event");
    try world.setUiCommandEvent(event_entity, .{
        .command = command,
        .source = source,
    });
}

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
            \\
            \\[entities.components."machina.transform"]
            \\position = [0.0, 0.0, 0.0]
            \\rotation = [0.0, 0.0, 0.0]
            \\scale = [1.0, 1.0, 1.0]
            \\
            \\[entities.components."machina.render.cube"]
            \\color = [0.0, 0.56, 1.0]
            \\
            \\[[entities]]
            \\id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0002"
            \\name = "Main Camera"
            \\
            \\[entities.components."machina.transform"]
            \\position = [0.0, 0.0, 4.8]
            \\rotation = [0.0, 0.0, 0.0]
            \\scale = [1.0, 1.0, 1.0]
            \\
            \\[entities.components."machina.camera"]
            \\fov_y_degrees = 48.0
            \\near = 0.1
            \\far = 100.0
            \\
            \\[[entities]]
            \\id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0003"
            \\name = "Key Light"
            \\
            \\[entities.components."machina.light.directional"]
            \\direction = [0.35, 0.68, 0.64]
            \\color = [1.0, 1.0, 1.0]
            \\intensity = 0.78
            \\ambient = 0.18
            \\
            ,
            .flags = .{ .exclusive = true },
        });
    }
}

pub fn checkProject(io: Io, allocator: std.mem.Allocator, root_path: []const u8) !CheckResult {
    var result = try checkProjectDetailed(io, allocator, root_path);
    switch (result) {
        .ok => |ok| return ok,
        .invalid => |*diagnostic| {
            diagnostic.deinit(allocator);
            return ProjectError.InvalidScript;
        },
    }
}

pub fn checkProjectDetailed(io: Io, allocator: std.mem.Allocator, root_path: []const u8) !CheckDetailedResult {
    const project = try loadProject(io, allocator, root_path);
    errdefer freeProject(allocator, project);
    const cwd = Io.Dir.cwd();
    const root_dir = try cwd.openDir(io, project.root_path, .{});
    defer root_dir.close(io);

    if (!fileExists(io, root_dir, project.default_scene)) {
        return ProjectError.MissingDefaultScene;
    }

    var scripts_result = try loadProjectScriptsDetailed(io, allocator, project);
    switch (scripts_result) {
        .program => |*scripts| {
            defer scripts.deinit();
            const scene = try loadSceneFile(io, allocator, root_dir, project.default_scene, scripts.registry);
            defer freeScene(allocator, scene);
            const schedule = try cloneCheckSchedule(allocator, scripts.registry, scripts.schedule);
            errdefer freeCheckSchedule(allocator, schedule);
            return .{ .ok = .{ .project = project, .schedule = schedule } };
        },
        .diagnostic => |diagnostic| {
            freeProject(allocator, project);
            return .{ .invalid = diagnostic };
        },
    }
}

pub fn stepProjectDetailed(
    io: Io,
    allocator: std.mem.Allocator,
    root_path: []const u8,
    options: StepOptions,
) !StepDetailedResult {
    const project = try loadProject(io, allocator, root_path);
    errdefer freeProject(allocator, project);
    const cwd = Io.Dir.cwd();
    const root_dir = try cwd.openDir(io, project.root_path, .{});
    defer root_dir.close(io);

    if (!fileExists(io, root_dir, project.default_scene)) {
        return ProjectError.MissingDefaultScene;
    }

    const scripts_result = try loadProjectScriptsDetailed(io, allocator, project);
    var scripts = switch (scripts_result) {
        .program => |program| program,
        .diagnostic => |diagnostic| {
            freeProject(allocator, project);
            return .{ .invalid = diagnostic };
        },
    };
    defer scripts.deinit();

    var scene = try loadSceneFile(io, allocator, root_dir, project.default_scene, scripts.registry);
    errdefer freeScene(allocator, scene);

    const schedule = try cloneCheckSchedule(allocator, scripts.registry, scripts.schedule);
    errdefer freeCheckSchedule(allocator, schedule);

    var completed_frames: u32 = 0;
    if (!scripts.startup(&scene.world)) {
        const diagnostic = if (scripts.last_diagnostic) |found|
            try cloneScriptDiagnostic(allocator, found)
        else
            try makeSyntheticRuntimeDiagnostic(allocator, "script startup failed without diagnostic");
        return .{ .runtime_error = .{
            .project = project,
            .scene = scene,
            .schedule = schedule,
            .summary = .{
                .frames = options.frames,
                .completed_frames = completed_frames,
                .delta_seconds = options.delta_seconds,
            },
            .diagnostic = diagnostic,
        } };
    }

    while (completed_frames < options.frames) {
        if (!scripts.update(&scene.world, options.delta_seconds)) {
            const diagnostic = if (scripts.last_diagnostic) |found|
                try cloneScriptDiagnostic(allocator, found)
            else
                try makeSyntheticRuntimeDiagnostic(allocator, "script runtime failed without diagnostic");
            return .{ .runtime_error = .{
                .project = project,
                .scene = scene,
                .schedule = schedule,
                .summary = .{
                    .frames = options.frames,
                    .completed_frames = completed_frames,
                    .delta_seconds = options.delta_seconds,
                },
                .diagnostic = diagnostic,
            } };
        }
        completed_frames += 1;
    }

    return .{ .ok = .{
        .project = project,
        .scene = scene,
        .schedule = schedule,
        .summary = .{
            .frames = options.frames,
            .completed_frames = completed_frames,
            .delta_seconds = options.delta_seconds,
        },
    } };
}

pub fn freeCheckResult(allocator: std.mem.Allocator, result: CheckResult) void {
    freeProject(allocator, result.project);
    freeCheckSchedule(allocator, result.schedule);
}

pub fn freeStepDetailedResult(allocator: std.mem.Allocator, result: StepDetailedResult) void {
    switch (result) {
        .ok => |ok| freeStepOk(allocator, ok),
        .runtime_error => |runtime_error| {
            var diagnostic = runtime_error.diagnostic;
            diagnostic.deinit(allocator);
            freeStepOk(allocator, .{
                .project = runtime_error.project,
                .scene = runtime_error.scene,
                .schedule = runtime_error.schedule,
                .summary = runtime_error.summary,
            });
        },
        .invalid => |diagnostic| {
            var owned = diagnostic;
            owned.deinit(allocator);
        },
    }
}

fn freeStepOk(allocator: std.mem.Allocator, ok: StepOk) void {
    freeCheckSchedule(allocator, ok.schedule);
    freeScene(allocator, ok.scene);
    freeProject(allocator, ok.project);
}

pub fn freeProject(allocator: std.mem.Allocator, project: Project) void {
    allocator.free(project.root_path);
    allocator.free(project.name);
    allocator.free(project.default_scene);
    freeStringList(allocator, project.scripts);
    if (project.native) |native_path| {
        allocator.free(native_path);
    }
}

pub fn freeCheckSchedule(allocator: std.mem.Allocator, schedule: CheckSchedule) void {
    for (schedule.batches) |batch| {
        for (batch.systems) |system| {
            freeCheckSystemSummary(allocator, system);
        }
        allocator.free(batch.systems);
    }
    allocator.free(schedule.batches);
}

fn freeCheckSystemSummary(allocator: std.mem.Allocator, system: CheckSystemSummary) void {
    allocator.free(system.id);
    freeStringList(allocator, system.reads);
    freeStringList(allocator, system.writes);
    freeStringList(allocator, system.before);
    freeStringList(allocator, system.after);
}

fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| {
        allocator.free(value);
    }
    allocator.free(values);
}

fn cloneCheckSchedule(
    allocator: std.mem.Allocator,
    registry: runtime.ComponentRegistry,
    schedule: runtime.SystemSchedule,
) !CheckSchedule {
    var batches: std.ArrayList(CheckScheduleBatch) = .empty;
    errdefer {
        for (batches.items) |batch| {
            for (batch.systems) |system| {
                freeCheckSystemSummary(allocator, system);
            }
            allocator.free(batch.systems);
        }
        batches.deinit(allocator);
    }

    for (schedule.batches) |batch| {
        var systems: std.ArrayList(CheckSystemSummary) = .empty;
        errdefer {
            for (systems.items) |system| {
                freeCheckSystemSummary(allocator, system);
            }
            systems.deinit(allocator);
        }

        for (batch.systems) |scheduled_system| {
            if (scheduled_system.registry_index >= registry.systems.items.len) {
                return ProjectError.InvalidScript;
            }
            const definition = registry.systems.items[scheduled_system.registry_index];
            try systems.append(allocator, try cloneCheckSystemSummary(allocator, definition));
        }

        const owned_systems = try systems.toOwnedSlice(allocator);
        var systems_transferred = false;
        errdefer if (!systems_transferred) {
            for (owned_systems) |system| {
                freeCheckSystemSummary(allocator, system);
            }
            allocator.free(owned_systems);
        };
        try batches.append(allocator, .{
            .phase = batch.phase,
            .systems = owned_systems,
        });
        systems_transferred = true;
    }

    return .{ .batches = try batches.toOwnedSlice(allocator) };
}

fn cloneCheckSystemSummary(allocator: std.mem.Allocator, definition: runtime.SystemDefinition) !CheckSystemSummary {
    const id = try allocator.dupe(u8, definition.id);
    errdefer allocator.free(id);

    const reads = try cloneStringList(allocator, definition.reads);
    errdefer freeStringList(allocator, reads);
    const writes = try cloneStringList(allocator, definition.writes);
    errdefer freeStringList(allocator, writes);
    const before = try cloneStringList(allocator, definition.before);
    errdefer freeStringList(allocator, before);
    const after = try cloneStringList(allocator, definition.after);
    errdefer freeStringList(allocator, after);

    return .{
        .id = id,
        .phase = definition.phase,
        .runner = switch (definition.runner) {
            .none => .none,
            .luau => .luau,
            .native => .native,
        },
        .reads = reads,
        .writes = writes,
        .before = before,
        .after = after,
    };
}

fn cloneStringList(allocator: std.mem.Allocator, values: []const []const u8) ![]const []const u8 {
    const owned = try allocator.alloc([]const u8, values.len);
    errdefer allocator.free(owned);

    var copied: usize = 0;
    errdefer {
        for (owned[0..copied]) |value| {
            allocator.free(value);
        }
    }

    for (values, 0..) |value, index| {
        owned[index] = try allocator.dupe(u8, value);
        copied += 1;
    }
    return owned;
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
    var scripts = try loadProjectScripts(io, allocator, project);
    defer scripts.deinit();
    return loadDefaultSceneWithRegistry(io, allocator, project, scripts.registry);
}

pub fn loadDefaultSceneWithRegistry(io: Io, allocator: std.mem.Allocator, project: Project, registry: runtime.ComponentRegistry) !Scene {
    const cwd = Io.Dir.cwd();
    const root_dir = try cwd.openDir(io, project.root_path, .{});
    defer root_dir.close(io);

    return loadSceneFile(io, allocator, root_dir, project.default_scene, registry);
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

fn statProjectNative(io: Io, allocator: std.mem.Allocator, project: Project) !?LoadedSource {
    const native_path = project.native orelse return null;
    const owned_path = try allocator.dupe(u8, native_path);
    errdefer allocator.free(owned_path);
    return .{
        .path = owned_path,
        .stamp = try statProjectResource(io, project, native_path, ProjectError.MissingScript),
    };
}

fn freeLoadedSource(allocator: std.mem.Allocator, source: LoadedSource) void {
    allocator.free(source.path);
}

fn freeLoadedSources(allocator: std.mem.Allocator, sources: []LoadedSource) void {
    for (sources) |source| {
        freeLoadedSource(allocator, source);
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

    const native_path = try readOptionalString(allocator, contents, "native");
    errdefer if (native_path) |path| allocator.free(path);
    if (native_path) |path| {
        if (!isSafeProjectRelativePath(path)) {
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
        .native = native_path,
    };
}

pub fn loadProjectScripts(io: Io, allocator: std.mem.Allocator, project: Project) !ScriptProgram {
    var result = try loadProjectScriptsDetailed(io, allocator, project);
    switch (result) {
        .program => |program| return program,
        .diagnostic => |*diagnostic| {
            diagnostic.deinit(allocator);
            return ProjectError.InvalidScript;
        },
    }
}

pub fn loadProjectScriptsDetailed(io: Io, allocator: std.mem.Allocator, project: Project) !script.LoadResult {
    const cwd = Io.Dir.cwd();
    const root_dir = try cwd.openDir(io, project.root_path, .{});
    defer root_dir.close(io);

    var native_extension: ?native.LoadedExtension = if (project.native) |native_path| blk: {
        const source_stamp = try statProjectResource(io, project, native_path, ProjectError.MissingScript);
        const native_result = try native.loadProjectExtensionDetailed(io, allocator, project.root_path, native_path, source_stamp);
        break :blk switch (native_result) {
            .extension => |extension| extension,
            .diagnostic => |diagnostic| return .{ .diagnostic = diagnostic },
        };
    } else null;
    var native_libraries_transferred = false;
    defer if (native_extension) |*extension| {
        extension.deinit(allocator, native_libraries_transferred);
    };

    const extension = if (native_extension) |loaded| loaded.nativeExtension() else script.NativeExtension{};
    const result = script.loadProjectProgramDetailedWithNative(io, allocator, root_dir, project.scripts, extension) catch |err| switch (err) {
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
        error.UnknownFieldType,
        error.UnknownSystemPhase,
        error.CyclicSystemOrder,
        => ProjectError.InvalidScript,
        else => err,
    };
    native_libraries_transferred = native_extension != null;
    return result;
}

fn cloneScriptDiagnostic(allocator: std.mem.Allocator, diagnostic: ScriptDiagnostic) !ScriptDiagnostic {
    const path = if (diagnostic.path) |path_value| try allocator.dupe(u8, path_value) else null;
    errdefer if (path) |path_value| allocator.free(path_value);
    const system_id = if (diagnostic.system_id) |system_id_value| try allocator.dupe(u8, system_id_value) else null;
    errdefer if (system_id) |system_id_value| allocator.free(system_id_value);
    return .{
        .stage = diagnostic.stage,
        .path = path,
        .system_id = system_id,
        .start = diagnostic.start,
        .end = diagnostic.end,
        .message = try allocator.dupe(u8, diagnostic.message),
    };
}

fn makeSyntheticRuntimeDiagnostic(allocator: std.mem.Allocator, message: []const u8) !ScriptDiagnostic {
    return .{
        .stage = .runtime,
        .message = try allocator.dupe(u8, message),
    };
}

fn loadSceneFile(io: Io, allocator: std.mem.Allocator, root_dir: Io.Dir, scene_path: []const u8, registry: runtime.ComponentRegistry) !Scene {
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
        .registry = registry,
    };
    return .{
        .name = name,
        .world = try parser.parse(contents),
    };
}

const SceneParser = struct {
    allocator: std.mem.Allocator,
    world: World,
    registry: runtime.ComponentRegistry,
    active_entity: ?EntityDraft = null,

    fn parse(self: *SceneParser, contents: []const u8) !World {
        errdefer {
            if (self.active_entity) |*entity| {
                entity.deinit();
                self.active_entity = null;
            }
            self.world.deinit();
        }

        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') {
                continue;
            }

            if (std.mem.eql(u8, trimmed, "[[entities]]")) {
                try self.flushEntity();
                self.active_entity = EntityDraft.init(self.allocator);
                continue;
            }

            if (trimmed[0] == '[') {
                if (self.active_entity) |*entity| {
                    const component_id = parseComponentTableHeader(trimmed) orelse return ProjectError.InvalidSceneEntity;
                    if (self.registry.findComponent(component_id) == null) {
                        return ProjectError.InvalidSceneEntity;
                    }
                    entity.active_component = component_id;
                    _ = try entity.ensureComponent(component_id);
                    continue;
                }
                return ProjectError.InvalidSceneEntity;
            }

            if (self.active_entity) |*entity| {
                try entity.readProperty(trimmed, self.registry);
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
        var entity = self.active_entity orelse return;
        defer entity.deinit();
        self.active_entity = null;
        if (!entity.id_seen or !entity.name_seen or entity.components.items.len == 0) {
            return ProjectError.InvalidSceneEntity;
        }
        const handle = self.world.createEntity(entity.id, entity.name) catch |err| switch (err) {
            runtime.WorldError.DuplicateEntityId => return ProjectError.DuplicateSceneEntityId,
            else => return err,
        };
        for (entity.components.items) |*component| {
            const definition = self.registry.findComponent(component.id) orelse return ProjectError.InvalidSceneEntity;
            try addSceneComponentDefaults(self.allocator, component);
            if (!componentHasEveryDefinedField(component.*, definition.*)) {
                return ProjectError.InvalidSceneEntity;
            }
            try self.world.setComponent(handle, component.id, component.fields.items);
        }
    }
};

fn addSceneComponentDefaults(allocator: std.mem.Allocator, component: *ComponentDraft) !void {
    if (std.mem.eql(u8, component.id, runtime.ui_canvas_component_id)) {
        try addSceneComponentDefaultField(allocator, component, "design_size", .{ .vec3 = .{ 0.0, 0.0, 0.0 } });
        try addSceneComponentDefaultField(allocator, component, "scale_mode", .{ .string = "none" });
    } else if (std.mem.eql(u8, component.id, runtime.ui_rect_component_id)) {
        try addSceneComponentDefaultField(allocator, component, "corner_radius", .{ .float = 0.0 });
    } else if (std.mem.eql(u8, component.id, runtime.ui_layout_item_component_id)) {
        try addSceneComponentDefaultField(allocator, component, "min_size", .{ .vec3 = .{ 0.0, 0.0, 0.0 } });
        try addSceneComponentDefaultField(allocator, component, "grow", .{ .float = 0.0 });
        try addSceneComponentDefaultField(allocator, component, "align", .{ .string = "start" });
        try addSceneComponentDefaultField(allocator, component, "margin", .{ .vec3 = .{ 0.0, 0.0, 0.0 } });
    }
}

fn addSceneComponentDefaultField(allocator: std.mem.Allocator, component: *ComponentDraft, name: []const u8, value: runtime.ComponentValue) !void {
    if (componentHasField(component.*, name)) {
        return;
    }
    try component.fields.append(allocator, .{
        .name = name,
        .value = value,
    });
}

const EntityDraft = struct {
    allocator: std.mem.Allocator,
    id_seen: bool = false,
    name_seen: bool = false,
    id: []const u8 = "",
    name: []const u8 = "",
    components: std.ArrayList(ComponentDraft) = .empty,
    active_component: ?[]const u8 = null,

    fn init(allocator: std.mem.Allocator) EntityDraft {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *EntityDraft) void {
        for (self.components.items) |*component| {
            component.deinit(self.allocator);
        }
        self.components.deinit(self.allocator);
    }

    fn readProperty(self: *EntityDraft, line: []const u8, registry: runtime.ComponentRegistry) !void {
        const eq_index = std.mem.indexOfScalar(u8, line, '=') orelse return ProjectError.InvalidSceneEntity;
        const key = std.mem.trim(u8, line[0..eq_index], " \t");
        const value = std.mem.trim(u8, line[eq_index + 1 ..], " \t");

        if (self.active_component) |component_id| {
            try self.readComponentProperty(component_id, key, value, registry);
        } else if (std.mem.eql(u8, key, "id")) {
            self.id = stringValue(value) orelse return ProjectError.InvalidSceneEntity;
            self.id_seen = true;
        } else if (std.mem.eql(u8, key, "name")) {
            self.name = stringValue(value) orelse return ProjectError.InvalidSceneEntity;
            self.name_seen = true;
        } else {
            return ProjectError.InvalidSceneEntity;
        }
    }

    fn readComponentProperty(self: *EntityDraft, component_id: []const u8, key: []const u8, value: []const u8, registry: runtime.ComponentRegistry) !void {
        const definition = registry.findComponent(component_id) orelse return ProjectError.InvalidSceneEntity;
        const field_definition = findComponentField(definition.*, key) orelse return ProjectError.InvalidSceneEntity;
        const component = try self.ensureComponent(component_id);
        for (component.fields.items) |field| {
            if (std.mem.eql(u8, field.name, key)) {
                return ProjectError.InvalidSceneEntity;
            }
        }
        const field_value = try readComponentValue(field_definition.value_type, value);
        try component.fields.append(self.allocator, .{
            .name = key,
            .value = field_value,
        });
    }

    fn ensureComponent(self: *EntityDraft, component_id: []const u8) !*ComponentDraft {
        for (self.components.items) |*component| {
            if (std.mem.eql(u8, component.id, component_id)) {
                return component;
            }
        }
        try self.components.append(self.allocator, .{ .id = component_id });
        return &self.components.items[self.components.items.len - 1];
    }
};

const ComponentDraft = struct {
    id: []const u8,
    fields: std.ArrayList(runtime.ComponentFieldValue) = .empty,

    fn deinit(self: *ComponentDraft, allocator: std.mem.Allocator) void {
        self.fields.deinit(allocator);
    }
};

fn parseComponentTableHeader(header: []const u8) ?[]const u8 {
    const prefix = "[entities.components.";
    if (!std.mem.startsWith(u8, header, prefix) or header[header.len - 1] != ']') {
        return null;
    }
    const raw_id = std.mem.trim(u8, header[prefix.len .. header.len - 1], " \t");
    if (raw_id.len >= 2 and raw_id[0] == '"' and raw_id[raw_id.len - 1] == '"') {
        return raw_id[1 .. raw_id.len - 1];
    }
    return raw_id;
}

fn findComponentField(definition: runtime.ComponentDefinition, field_name: []const u8) ?runtime.ComponentFieldDefinition {
    for (definition.fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return field;
        }
    }
    return null;
}

fn componentHasEveryDefinedField(component: ComponentDraft, definition: runtime.ComponentDefinition) bool {
    for (definition.fields) |field| {
        if (!componentHasField(component, field.name)) {
            return false;
        }
    }
    return true;
}

fn componentHasField(component: ComponentDraft, field_name: []const u8) bool {
    for (component.fields.items) |value| {
        if (std.mem.eql(u8, value.name, field_name)) {
            return true;
        }
    }
    return false;
}

fn readComponentValue(field_type: runtime.FieldType, value: []const u8) !runtime.ComponentValue {
    return switch (field_type) {
        .boolean => .{ .boolean = try readBool(value) },
        .int => .{ .int = std.fmt.parseInt(i32, value, 10) catch return ProjectError.InvalidSceneNumber },
        .float => .{ .float = std.fmt.parseFloat(f32, value) catch return ProjectError.InvalidSceneNumber },
        .vec3 => .{ .vec3 = try readVec3(value) },
        .string => .{ .string = stringValue(value) orelse return ProjectError.InvalidSceneEntity },
    };
}

fn readBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) {
        return true;
    }
    if (std.mem.eql(u8, value, "false")) {
        return false;
    }
    return ProjectError.InvalidSceneEntity;
}

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

fn readOptionalString(allocator: std.mem.Allocator, contents: []const u8, key: []const u8) !?[]const u8 {
    return readRequiredString(allocator, contents, key);
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
    defer freeCheckResult(std.testing.allocator, result);

    try std.testing.expectEqualStrings("Game", result.project.name);
    try std.testing.expectEqualStrings(default_scene_path, result.project.default_scene);
    try std.testing.expectEqual(@as(usize, 0), result.schedule.systemCount());
}

test "loadDefaultScene reads cube entities from scene data" {
    const root_path = ".zig-cache/test-load-scene-data";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");

    const result = try checkProject(io, std.testing.allocator, root_path);
    defer freeCheckResult(std.testing.allocator, result);

    const scene = try loadDefaultScene(io, std.testing.allocator, result.project);
    defer freeScene(std.testing.allocator, scene);

    try std.testing.expectEqualStrings("Main", scene.name);
    try std.testing.expectEqual(@as(usize, 3), scene.entityCount());
    try std.testing.expectEqual(@as(usize, 1), scene.renderableCubeCount());

    const entity = scene.world.findEntityById("018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001") orelse return error.TestExpectedEqual;
    const cube = scene.world.renderableCubeAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(entity.index, cube.entity.index);
    try std.testing.expectEqual(@as(f32, 0.56), cube.color[1]);

    const camera = scene.world.renderCamera() orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("Main Camera", camera.name);
    try std.testing.expectEqual(@as(f32, 4.8), camera.transform.position[2]);
    try std.testing.expectEqual(@as(f32, 48.0), camera.fov_y_degrees);

    const light = scene.world.renderDirectionalLight() orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("Key Light", light.name);
    try std.testing.expectEqual(@as(f32, 0.78), light.intensity);
}

test "loadDefaultScene stores script-declared component tables" {
    const root_path = ".zig-cache/test-load-script-component-scene-data";
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
    try writeSpinnerScene(io, root_dir);
    try writeRotateScript(io, root_dir, "dt");

    const project = try loadProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, project);
    const scene = try loadDefaultScene(io, std.testing.allocator, project);
    defer freeScene(std.testing.allocator, scene);

    const entity = scene.world.findEntityById("018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001") orelse return error.TestExpectedEqual;
    try std.testing.expect(try scene.world.hasComponent(entity, "spin"));
    const angular_velocity = try scene.world.getVec3(entity, "spin", "angular_velocity");
    try std.testing.expectEqual(@as(f32, 1.0), angular_velocity[0]);

    var cursor: usize = 0;
    const query = [_][]const u8{ "machina.transform", "spin" };
    try std.testing.expectEqual(entity.index, (scene.world.queryNext(&query, &cursor) orelse return error.TestExpectedEqual).index);
    try std.testing.expect(scene.world.queryNext(&query, &cursor) == null);
}

test "checkProject rejects scene components missing from the script registry" {
    const root_path = ".zig-cache/test-undeclared-scene-component";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try writeSpinnerScene(io, root_dir);

    try std.testing.expectError(
        ProjectError.InvalidSceneEntity,
        checkProject(io, std.testing.allocator, root_path),
    );
}

test "checkProject rejects duplicate component fields in scene data" {
    const root_path = ".zig-cache/test-duplicate-scene-component-field";
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
        \\id = "dupe-field"
        \\name = "Dupe Field"
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\position = [1.0, 0.0, 0.0]
        \\
        ,
    });

    try std.testing.expectError(
        ProjectError.InvalidSceneEntity,
        checkProject(io, std.testing.allocator, root_path),
    );
}

test "checkProject rejects missing required component fields in scene data" {
    const root_path = ".zig-cache/test-missing-scene-component-field";
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
        \\id = "missing-field"
        \\name = "Missing Field"
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\
        ,
    });

    try std.testing.expectError(
        ProjectError.InvalidSceneEntity,
        checkProject(io, std.testing.allocator, root_path),
    );
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
        \\
        \\[entities.components."machina.transform"]
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
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        \\[[entities]]
        \\id = "same-id"
        \\name = "Two"
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
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
        .sub_path = default_scene_path,
        .data =
        \\name = "Main"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001"
        \\name = "Spinner"
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        \\[entities.components.spin]
        \\angular_velocity = [1.0, 0.0, 0.0]
        \\
        ,
    });
    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local RenderCube = ecs.component<<MachinaRenderCube>>("machina.render.cube")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\local Spinners = ecs.query(Spin)
        \\local RenderedCubes = ecs.query(Transform, RenderCube)
        \\
        \\ecs.system("observe_spin", {
        \\  query = Spinners,
        \\  run = function(world, dt)
        \\  end,
        \\})
        \\
        \\ecs.system("observe_cubes", {
        \\  query = RenderedCubes,
        \\  after = { "observe_spin" },
        \\})
        ,
    });

    const result = try checkProject(io, std.testing.allocator, root_path);
    defer freeCheckResult(std.testing.allocator, result);

    try std.testing.expectEqual(@as(usize, 1), result.project.scripts.len);
    try std.testing.expectEqual(@as(usize, 2), result.schedule.batchCount());
    try std.testing.expectEqual(@as(usize, 2), result.schedule.systemCount());
    try std.testing.expectEqualStrings("observe_spin", result.schedule.batches[0].systems[0].id);
    try std.testing.expectEqual(CheckSystemRunner.luau, result.schedule.batches[0].systems[0].runner);
    try std.testing.expectEqual(@as(usize, 1), result.schedule.batches[0].systems[0].reads.len);
    try std.testing.expectEqualStrings("spin", result.schedule.batches[0].systems[0].reads[0]);
    try std.testing.expectEqualStrings("observe_cubes", result.schedule.batches[1].systems[0].id);
    try std.testing.expectEqual(@as(usize, 1), result.schedule.batches[1].systems[0].after.len);
    try std.testing.expectEqualStrings("observe_spin", result.schedule.batches[1].systems[0].after[0]);
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
    try writeSpinnerScene(io, root_dir);
    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\ecs.component("machina.bad", {
        \\  fields = ecs.fields({
        \\    value = "f32",
        \\  }),
        \\})
        ,
    });

    try std.testing.expectError(ProjectError.InvalidScript, checkProject(io, std.testing.allocator, root_path));
}

test "checkProjectDetailed returns script diagnostics" {
    const root_path = ".zig-cache/test-invalid-project-script-diagnostic";
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
        .data = "ecs.system(\"broken\", { run = function(world, dt) world.query( end })",
    });

    var result = try checkProjectDetailed(io, std.testing.allocator, root_path);
    switch (result) {
        .ok => return error.TestExpectedEqual,
        .invalid => |*diagnostic| {
            defer diagnostic.deinit(std.testing.allocator);
            try std.testing.expectEqual(script.DiagnosticStage.load, diagnostic.stage);
            try std.testing.expectEqualStrings("scripts/gameplay.luau", diagnostic.path orelse return error.TestExpectedEqual);
            try std.testing.expectEqual(@as(u32, 1), (diagnostic.start orelse return error.TestExpectedEqual).line);
            try std.testing.expect(diagnostic.message.len > 0);
        },
    }
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
    try std.testing.expectEqual(@as(usize, 3), live_project.scene.entityCount());
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
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        \\[[entities]]
        \\id = "two"
        \\name = "Two"
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
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
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        \\[[entities]]
        \\id = "same"
        \\name = "Two"
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
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
    try writeSpinnerScene(io, root_dir);
    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\--!strict
        \\
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\local Spinners = ecs.query(Spin)
        \\
        \\ecs.system("observe_spin", {
        \\  query = Spinners,
        \\})
        ,
    });

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();
    try std.testing.expect(live_project.scripts.registry.findComponent("spin") != null);
    try std.testing.expect(live_project.scripts.registry.findComponent("marker") == null);
    try std.testing.expectEqual(@as(usize, 1), live_project.scripts.schedule.systemCount());

    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\--!strict
        \\
        \\type Marker = {
        \\  enabled: boolean,
        \\}
        \\
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\
        \\local Marker = ecs.component<<Marker>>("marker", {
        \\  fields = ecs.fields({
        \\    enabled = "boolean",
        \\  }),
        \\})
        \\local Spinners = ecs.query(Spin)
        \\local Markers = ecs.query(Marker)
        \\
        \\ecs.system("observe_spin", {
        \\  query = Spinners,
        \\})
        \\
        \\ecs.system("observe_marker", {
        \\  query = Markers,
        \\})
        ,
    });

    const reload = try live_project.pollLoadedSources();
    try std.testing.expect(!reload.reloaded.project_reloaded);
    try std.testing.expect(!reload.reloaded.scene_reloaded);
    try std.testing.expect(reload.reloaded.scripts_reloaded);
    try std.testing.expect(live_project.scripts.registry.findComponent("marker") != null);
    try std.testing.expectEqual(@as(usize, 2), live_project.scripts.schedule.systemCount());

    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\ecs.component("machina.bad", {
        \\  fields = ecs.fields({
        \\    value = "f32",
        \\  }),
        \\})
        ,
    });

    try std.testing.expectError(ProjectError.InvalidScript, live_project.pollLoadedSources());
    const diagnostic = live_project.lastDiagnostic() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(script.DiagnosticStage.registration, diagnostic.stage);
    try std.testing.expectEqualStrings("scripts/gameplay.luau", diagnostic.path orelse return error.TestExpectedEqual);
    try std.testing.expectEqual(@as(u32, 1), (diagnostic.start orelse return error.TestExpectedEqual).line);
    try std.testing.expect(live_project.scripts.registry.findComponent("marker") != null);
    try std.testing.expectEqual(@as(usize, 2), live_project.scripts.schedule.systemCount());
    try std.testing.expectEqual(ReloadResult.unchanged, try live_project.pollLoadedSources());
}

test "LiveProject update runs the scheduled rotation system" {
    const root_path = ".zig-cache/test-live-project-update";
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
    try writeSpinnerScene(io, root_dir);
    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\local RotatingCubes = ecs.query(Transform, Spin)
        \\
        \\ecs.system("rotate_cubes", {
        \\  query = RotatingCubes,
        \\  writes = ecs.refs(Transform),
        \\  run = function(world, dt)
        \\    for _entity, transform, spin in RotatingCubes:iter(world) do
        \\      transform.rotation = {
        \\        transform.rotation[1] + spin.angular_velocity[1] * dt,
        \\        transform.rotation[2] + spin.angular_velocity[2] * dt,
        \\        transform.rotation[3] + spin.angular_velocity[3] * dt,
        \\      }
        \\    end
        \\  end,
        \\})
        ,
    });

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();

    const entity = live_project.scene.world.findEntityById("018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001") orelse return error.TestExpectedEqual;
    const before = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;

    live_project.update(0.5);

    const after = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expect(after.rotation[0] > before.rotation[0]);
    try std.testing.expect(after.rotation[1] > before.rotation[1]);
    try std.testing.expectEqual(before.rotation[2], after.rotation[2]);
}

test "LiveProject editor pause gates scheduled update systems" {
    const root_path = ".zig-cache/test-live-project-editor-pause";
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
    try writeSpinnerScene(io, root_dir);
    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\local RotatingCubes = ecs.query(Transform, Spin)
        \\
        \\ecs.system("rotate_cubes", {
        \\  query = RotatingCubes,
        \\  writes = ecs.refs(Transform),
        \\  run = function(world, dt)
        \\    for _entity, transform, spin in RotatingCubes:iter(world) do
        \\      transform.rotation = {
        \\        transform.rotation[1] + spin.angular_velocity[1] * dt,
        \\        transform.rotation[2] + spin.angular_velocity[2] * dt,
        \\        transform.rotation[3] + spin.angular_velocity[3] * dt,
        \\      }
        \\    end
        \\  end,
        \\})
        ,
    });

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();

    const entity = live_project.scene.world.findEntityById("018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001") orelse return error.TestExpectedEqual;
    const before = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;

    live_project.editor_state.paused = true;
    live_project.updateWithInput(0.5, .{});

    const paused_after = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(before.rotation[0], paused_after.rotation[0]);
    try std.testing.expectEqual(before.rotation[1], paused_after.rotation[1]);
    try std.testing.expectEqual(before.rotation[2], paused_after.rotation[2]);

    live_project.editor_state.paused = false;
    live_project.updateWithInput(0.5, .{});

    const running_after = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expect(running_after.rotation[0] > paused_after.rotation[0]);
    try std.testing.expect(running_after.rotation[1] > paused_after.rotation[1]);
    try std.testing.expectEqual(paused_after.rotation[2], running_after.rotation[2]);
}

test "LiveProject editor scrolling uses render system profile count hint" {
    const root_path = ".zig-cache/test-live-project-editor-scroll-profile-hint";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();

    const profiles = [_]SystemProfileSnapshot{};
    live_project.updateWithInput(0.016, .{
        .debug_overlay_visible = true,
        .system_profile_count_hint = 9,
        .pointer = .{
            .position = render.editorSystemListHitTestPoint(&profiles, 9),
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expectApproxEqAbs(@as(f32, 18.0), live_project.editor_state.system_scroll_target_y, 0.001);
    try std.testing.expect(live_project.editor_state.system_scroll_y > 0.0);
    try std.testing.expect(live_project.editor_state.system_scroll_y < live_project.editor_state.system_scroll_target_y);
}

test "scene UI pointer transform targets editor game viewport when editor is visible" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const input = try world.createEntity(runtime.input_entity_id, "Input");
    try world.setInputFrame(input, .{
        .viewport = .{ 1280.0, 720.0, 0.0 },
        .ui_visible = true,
        .debug_overlay_visible = true,
    });

    const canvas = try world.createEntity("canvas", "Canvas");
    try world.setUiCanvas(canvas, .{
        .design_size = .{ 640.0, 480.0, 0.0 },
        .scale_mode = "fit",
    });

    const bounds = render.editorGameViewportBounds(.{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    });
    const scale = @min(bounds.width / 640.0, bounds.height / 480.0);
    const design_point = [2]f32{ 48.0, 36.0 };
    const pointer = [2]f32{
        bounds.x + (bounds.width - 640.0 * scale) * 0.5 + design_point[0] * scale,
        bounds.y + (bounds.height - 480.0 * scale) * 0.5 + design_point[1] * scale,
    };

    const resolved = try sceneUiPointerPosition(&world, input, pointer);
    try std.testing.expectApproxEqAbs(design_point[0], resolved[0], 0.001);
    try std.testing.expectApproxEqAbs(design_point[1], resolved[1], 0.001);
}

test "LiveProject emits UI command events before scheduled scripts run" {
    const root_path = ".zig-cache/test-live-project-ui-command";
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
        .sub_path = "scenes/main.scene.toml",
        .data =
        \\name = "Main"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "canvas"
        \\name = "Canvas"
        \\
        \\[entities.components."machina.ui.canvas"]
        \\design_size = [640.0, 480.0, 0.0]
        \\scale_mode = "fit"
        \\
        \\[[entities]]
        \\id = "button"
        \\name = "Button"
        \\
        \\[entities.components."machina.ui.rect"]
        \\position = [32.0, 24.0, 0.0]
        \\size = [120.0, 48.0, 0.0]
        \\color = [0.0, 0.2, 0.4]
        \\
        \\[entities.components."machina.ui.button"]
        \\
        \\[entities.components."machina.ui.command"]
        \\command = "activate_flag"
        \\
        \\[[entities]]
        \\id = "flag"
        \\name = "Flag"
        \\
        \\[entities.components.flag]
        \\active = false
        \\
        ,
    });
    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\--!strict
        \\
        \\local CommandEvent = ecs.component<<MachinaUiCommandEvent>>("machina.ui.command_event")
        \\local Flag = ecs.component("flag", {
        \\  fields = ecs.fields({
        \\    active = "boolean",
        \\  }),
        \\})
        \\local CommandEvents = ecs.query(CommandEvent)
        \\local Flags = ecs.query(Flag)
        \\
        \\ecs.system("handle_ui_commands", {
        \\  query = CommandEvents,
        \\  reads = ecs.refs(CommandEvent),
        \\  writes = ecs.refs(Flag),
        \\  run = function(world, _dt)
        \\    for _event_entity, event in CommandEvents:iter(world) do
        \\      if event.command == "activate_flag" then
        \\        for _flag_entity, flag in Flags:iter(world) do
        \\          flag.active = true
        \\        end
        \\      end
        \\    end
        \\  end,
        \\})
        ,
    });

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();

    const button = live_project.scene.world.findEntityById("button") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 0.0), try live_project.scene.world.getFloat(button, runtime.ui_rect_component_id, "corner_radius"));

    const flag = live_project.scene.world.findEntityById("flag") orelse return error.TestExpectedEqual;
    try std.testing.expect(!try live_project.scene.world.getBoolean(flag, "flag", "active"));

    live_project.updateWithInput(0.016, .{
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = .{ 232.0, 54.0 },
            .has_position = true,
            .primary_released = true,
        },
    });

    try std.testing.expect(try live_project.scene.world.getBoolean(flag, "flag", "active"));
    const event = live_project.scene.world.uiCommandEvent() orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("activate_flag", event.command);
    try std.testing.expectEqualStrings("button", event.source);

    live_project.updateWithInput(0.016, .{});
    try std.testing.expect(live_project.scene.world.uiCommandEvent() == null);
    try std.testing.expect(try live_project.scene.world.getBoolean(flag, "flag", "active"));
}

test "LiveProject routes UI command hits through retained layout" {
    const root_path = ".zig-cache/test-live-project-ui-command-layout";
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
        .sub_path = "scenes/main.scene.toml",
        .data =
        \\name = "Main"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "toolbar"
        \\name = "Toolbar"
        \\
        \\[entities.components."machina.ui.stack"]
        \\position = [100.0, 24.0, 0.0]
        \\spacing = 12.0
        \\direction = "horizontal"
        \\padding = [0.0, 0.0, 0.0]
        \\
        \\[[entities]]
        \\id = "button"
        \\name = "Button"
        \\
        \\[entities.components."machina.ui.rect"]
        \\position = [0.0, 0.0, 0.0]
        \\size = [120.0, 48.0, 0.0]
        \\color = [0.0, 0.2, 0.4]
        \\
        \\[entities.components."machina.ui.button"]
        \\
        \\[entities.components."machina.ui.layout.item"]
        \\parent = "toolbar"
        \\order = 0
        \\
        \\[entities.components."machina.ui.command"]
        \\command = "activate_flag"
        \\
        \\[[entities]]
        \\id = "flag"
        \\name = "Flag"
        \\
        \\[entities.components.flag]
        \\active = false
        \\
        ,
    });
    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data =
        \\--!strict
        \\
        \\local CommandEvent = ecs.component<<MachinaUiCommandEvent>>("machina.ui.command_event")
        \\local Flag = ecs.component("flag", {
        \\  fields = ecs.fields({
        \\    active = "boolean",
        \\  }),
        \\})
        \\local CommandEvents = ecs.query(CommandEvent)
        \\local Flags = ecs.query(Flag)
        \\
        \\ecs.system("handle_ui_commands", {
        \\  query = CommandEvents,
        \\  reads = ecs.refs(CommandEvent),
        \\  writes = ecs.refs(Flag),
        \\  run = function(world, _dt)
        \\    for _event_entity, event in CommandEvents:iter(world) do
        \\      if event.command == "activate_flag" then
        \\        for _flag_entity, flag in Flags:iter(world) do
        \\          flag.active = true
        \\        end
        \\      end
        \\    end
        \\  end,
        \\})
        ,
    });

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();

    const flag = live_project.scene.world.findEntityById("flag") orelse return error.TestExpectedEqual;
    try std.testing.expect(!try live_project.scene.world.getBoolean(flag, "flag", "active"));

    live_project.updateWithInput(0.016, .{
        .pointer = .{
            .position = .{ 150.0, 36.0 },
            .has_position = true,
            .primary_released = true,
        },
    });

    try std.testing.expect(try live_project.scene.world.getBoolean(flag, "flag", "active"));
    const event = live_project.scene.world.uiCommandEvent() orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("button", event.source);
}

test "LiveProject scrolls scene-authored scroll views under pointer" {
    const root_path = ".zig-cache/test-live-project-ui-scroll-view";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try root_dir.writeFile(io, .{
        .sub_path = "scenes/main.scene.toml",
        .data =
        \\name = "Main"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "scroll"
        \\name = "Scroll"
        \\
        \\[entities.components."machina.ui.scroll_view"]
        \\position = [10.0, 10.0, 0.0]
        \\size = [100.0, 40.0, 0.0]
        \\content_offset = [0.0, 0.0, 0.0]
        \\
        \\[[entities]]
        \\id = "stack"
        \\name = "Stack"
        \\
        \\[entities.components."machina.ui.vbox"]
        \\position = [0.0, 0.0, 0.0]
        \\spacing = 0.0
        \\
        \\[entities.components."machina.ui.layout.item"]
        \\parent = "scroll"
        \\order = 0
        \\
        \\[[entities]]
        \\id = "row-1"
        \\name = "Row 1"
        \\
        \\[entities.components."machina.ui.text"]
        \\position = [0.0, 0.0, 0.0]
        \\size = 1.0
        \\color = [1.0, 1.0, 1.0]
        \\value = "ROW 1"
        \\
        \\[entities.components."machina.ui.layout.item"]
        \\parent = "stack"
        \\order = 0
        \\
        \\[[entities]]
        \\id = "row-2"
        \\name = "Row 2"
        \\
        \\[entities.components."machina.ui.text"]
        \\position = [0.0, 0.0, 0.0]
        \\size = 1.0
        \\color = [1.0, 1.0, 1.0]
        \\value = "ROW 2"
        \\
        \\[entities.components."machina.ui.layout.item"]
        \\parent = "stack"
        \\order = 1
        \\
        \\[[entities]]
        \\id = "row-3"
        \\name = "Row 3"
        \\
        \\[entities.components."machina.ui.text"]
        \\position = [0.0, 0.0, 0.0]
        \\size = 1.0
        \\color = [1.0, 1.0, 1.0]
        \\value = "ROW 3"
        \\
        \\[entities.components."machina.ui.layout.item"]
        \\parent = "stack"
        \\order = 2
        \\
        ,
    });

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();

    const scroll = live_project.scene.world.findEntityById("scroll") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 0.0), (try live_project.scene.world.getVec3(scroll, runtime.ui_scroll_view_component_id, "content_offset"))[1]);

    live_project.updateWithInput(0.016, .{
        .pointer = .{
            .position = .{ 20.0, 20.0 },
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expectApproxEqAbs(@as(f32, 24.0), (try live_project.scene.world.getVec3(scroll, runtime.ui_scroll_view_component_id, "content_offset"))[1], 0.001);

    try live_project.scene.world.setVec3(scroll, runtime.ui_scroll_view_component_id, "content_offset", .{ 0.0, 0.0, 0.0 });
    const editor_bounds = render.editorGameViewportBounds(.{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    });
    live_project.updateWithInput(0.016, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profile_count_hint = 9,
        .pointer = .{
            .position = .{ editor_bounds.x + 20.0, editor_bounds.y + 20.0 },
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expectApproxEqAbs(@as(f32, 24.0), (try live_project.scene.world.getVec3(scroll, runtime.ui_scroll_view_component_id, "content_offset"))[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), live_project.editor_state.system_scroll_target_y, 0.001);
}

test "stepProjectDetailed runs requested frames headlessly" {
    const root_path = ".zig-cache/test-step-project";
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
    try writeSpinnerScene(io, root_dir);
    try writeRotateScript(io, root_dir, "dt");

    const result = try stepProjectDetailed(io, std.testing.allocator, root_path, .{
        .frames = 2,
        .delta_seconds = 0.5,
    });
    defer freeStepDetailedResult(std.testing.allocator, result);

    switch (result) {
        .ok => |ok| {
            try std.testing.expectEqual(@as(u32, 2), ok.summary.frames);
            try std.testing.expectEqual(@as(u32, 2), ok.summary.completed_frames);
            try std.testing.expectEqual(@as(usize, 1), ok.scene.entityCount());
            try std.testing.expectEqual(@as(usize, 2), ok.scene.componentInstanceCount());
            try std.testing.expectEqual(@as(usize, 1), ok.schedule.systemCount());

            const entity = ok.scene.world.findEntityById("018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001") orelse return error.TestExpectedEqual;
            const transform = (try ok.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
            try std.testing.expectApproxEqAbs(@as(f32, 1.0), transform.rotation[0], 0.0001);
            try std.testing.expectApproxEqAbs(@as(f32, 1.0), transform.rotation[1], 0.0001);
            try std.testing.expectEqual(@as(f32, 0.0), transform.rotation[2]);
        },
        else => return error.TestExpectedEqual,
    }
}

test "stepProjectDetailed returns runtime diagnostics and final world state" {
    const root_path = ".zig-cache/test-step-project-runtime-diagnostic";
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
    try writeSpinnerScene(io, root_dir);
    try writeRotateScript(io, root_dir, "dt / 0");

    const result = try stepProjectDetailed(io, std.testing.allocator, root_path, .{
        .frames = 3,
        .delta_seconds = 1.0,
    });
    defer freeStepDetailedResult(std.testing.allocator, result);

    switch (result) {
        .runtime_error => |failure| {
            try std.testing.expectEqual(@as(u32, 3), failure.summary.frames);
            try std.testing.expectEqual(@as(u32, 0), failure.summary.completed_frames);
            try std.testing.expectEqual(script.DiagnosticStage.runtime, failure.diagnostic.stage);
            try std.testing.expectEqualStrings("rotate_cubes", failure.diagnostic.system_id orelse return error.TestExpectedEqual);
            try std.testing.expect(std.mem.indexOf(u8, failure.diagnostic.message, "machina.transform.rotation") != null);

            const entity = failure.scene.world.findEntityById("018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001") orelse return error.TestExpectedEqual;
            const transform = (try failure.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
            try std.testing.expect(std.math.isFinite(transform.rotation[0]));
            try std.testing.expect(std.math.isFinite(transform.rotation[1]));
            try std.testing.expect(std.math.isFinite(transform.rotation[2]));
            try std.testing.expectEqual(@as(f32, 0.0), transform.rotation[0]);
            try std.testing.expectEqual(@as(f32, 0.0), transform.rotation[1]);
            try std.testing.expectEqual(@as(f32, 0.0), transform.rotation[2]);
        },
        else => return error.TestExpectedEqual,
    }
}

test "headless gameplay fixture applies health damage and regen" {
    const io = Io.Threaded.global_single_threaded.io();
    const result = try stepProjectDetailed(io, std.testing.allocator, "tests/projects/health_tick", .{
        .frames = 4,
        .delta_seconds = 1.0,
    });
    defer freeStepDetailedResult(std.testing.allocator, result);

    switch (result) {
        .ok => |ok| {
            try std.testing.expectEqualStrings("Health Tick Test", ok.project.name);
            try std.testing.expectEqual(@as(u32, 4), ok.summary.completed_frames);
            try std.testing.expectEqual(@as(usize, 1), ok.scene.entityCount());
            try std.testing.expectEqual(@as(usize, 3), ok.scene.componentInstanceCount());
            try std.testing.expectEqual(@as(usize, 2), ok.schedule.systemCount());
            try expectFloatField(ok.scene.world, "health-target", "health", "current", 5.0);
            try expectFloatField(ok.scene.world, "health-target", "health", "max", 10.0);
        },
        else => return error.TestExpectedEqual,
    }
}

test "headless gameplay fixture moves projectile and expires lifetime" {
    const io = Io.Threaded.global_single_threaded.io();
    const result = try stepProjectDetailed(io, std.testing.allocator, "tests/projects/projectile_lifetime", .{
        .frames = 3,
        .delta_seconds = 1.0,
    });
    defer freeStepDetailedResult(std.testing.allocator, result);

    switch (result) {
        .ok => |ok| {
            try std.testing.expectEqualStrings("Projectile Lifetime Test", ok.project.name);
            try std.testing.expectEqual(@as(u32, 3), ok.summary.completed_frames);
            try std.testing.expectEqual(@as(usize, 1), ok.scene.entityCount());
            try std.testing.expectEqual(@as(usize, 3), ok.scene.componentInstanceCount());
            try std.testing.expectEqual(@as(usize, 2), ok.schedule.systemCount());

            const entity = ok.scene.world.findEntityById("projectile-1") orelse return error.TestExpectedEqual;
            const transform = (try ok.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
            try std.testing.expectApproxEqAbs(@as(f32, 6.0), transform.position[0], 0.0001);
            try std.testing.expectApproxEqAbs(@as(f32, 0.0), transform.position[1], 0.0001);
            try std.testing.expectApproxEqAbs(@as(f32, 0.0), transform.position[2], 0.0001);
            try expectFloatField(ok.scene.world, "projectile-1", "lifetime", "remaining", 0.0);
            try expectBooleanField(ok.scene.world, "projectile-1", "lifetime", "expired", true);
        },
        else => return error.TestExpectedEqual,
    }
}

test "headless gameplay fixture opens door from active switch" {
    const io = Io.Threaded.global_single_threaded.io();
    const result = try stepProjectDetailed(io, std.testing.allocator, "tests/projects/auto_door", .{
        .frames = 4,
        .delta_seconds = 1.0,
    });
    defer freeStepDetailedResult(std.testing.allocator, result);

    switch (result) {
        .ok => |ok| {
            try std.testing.expectEqualStrings("Auto Door Test", ok.project.name);
            try std.testing.expectEqual(@as(u32, 4), ok.summary.completed_frames);
            try std.testing.expectEqual(@as(usize, 2), ok.scene.entityCount());
            try std.testing.expectEqual(@as(usize, 3), ok.scene.componentInstanceCount());
            try std.testing.expectEqual(@as(usize, 1), ok.schedule.systemCount());

            try expectBooleanField(ok.scene.world, "switch-1", "switch", "active", true);
            try expectFloatField(ok.scene.world, "door-1", "door", "openness", 1.0);
            const door = ok.scene.world.findEntityById("door-1") orelse return error.TestExpectedEqual;
            const transform = (try ok.scene.world.getTransform(door)) orelse return error.TestExpectedEqual;
            try std.testing.expectApproxEqAbs(@as(f32, 1.5708), transform.rotation[2], 0.0001);
        },
        else => return error.TestExpectedEqual,
    }
}

test "LiveProject reloads script runner multiplier" {
    const root_path = ".zig-cache/test-live-script-runner-reload";
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
    try writeSpinnerScene(io, root_dir);
    try writeRotateScript(io, root_dir, "dt");

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();

    const entity = live_project.scene.world.findEntityById("018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001") orelse return error.TestExpectedEqual;
    const start = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
    live_project.update(1.0);
    const after_base = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
    const base_delta = after_base.rotation[0] - start.rotation[0];

    try writeRotateScript(io, root_dir, "dt * 3");
    const reload = try live_project.pollLoadedSources();
    try std.testing.expect(reload.reloaded.scripts_reloaded);

    live_project.update(1.0);
    const after_reloaded = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
    const reloaded_delta = after_reloaded.rotation[0] - after_base.rotation[0];
    try std.testing.expect(reloaded_delta > base_delta * 2.9);
}

test "LiveProject recovers after script update produces non-finite rotation delta" {
    const root_path = ".zig-cache/test-live-script-nonfinite-recovery";
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
    try writeSpinnerScene(io, root_dir);
    try writeRotateScript(io, root_dir, "dt");

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();

    const entity = live_project.scene.world.findEntityById("018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001") orelse return error.TestExpectedEqual;
    const start = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
    live_project.update(1.0);
    const after_valid = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
    const valid_delta = after_valid.rotation[0] - start.rotation[0];
    try std.testing.expect(valid_delta > 0.0);

    try writeRotateScript(io, root_dir, "dt / 0");
    const bad_reload = try live_project.pollLoadedSources();
    try std.testing.expect(bad_reload.reloaded.scripts_reloaded);

    live_project.update(1.0);
    const after_bad = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
    const diagnostic = live_project.lastDiagnostic() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(script.DiagnosticStage.runtime, diagnostic.stage);
    try std.testing.expectEqualStrings("scripts/gameplay.luau", diagnostic.path orelse return error.TestExpectedEqual);
    try std.testing.expectEqualStrings("rotate_cubes", diagnostic.system_id orelse return error.TestExpectedEqual);
    try std.testing.expect((diagnostic.start orelse return error.TestExpectedEqual).line > 0);
    try std.testing.expect(std.math.isFinite(after_bad.rotation[0]));
    try std.testing.expect(std.math.isFinite(after_bad.rotation[1]));
    try std.testing.expect(std.math.isFinite(after_bad.rotation[2]));
    try std.testing.expectEqual(after_valid.rotation[0], after_bad.rotation[0]);
    try std.testing.expectEqual(after_valid.rotation[1], after_bad.rotation[1]);
    try std.testing.expectEqual(after_valid.rotation[2], after_bad.rotation[2]);

    try writeRotateScript(io, root_dir, "dt");
    const fixed_reload = try live_project.pollLoadedSources();
    try std.testing.expect(fixed_reload.reloaded.scripts_reloaded);

    live_project.update(1.0);
    const after_fixed = (try live_project.scene.world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expect(after_fixed.rotation[0] > after_bad.rotation[0]);
    try std.testing.expect(after_fixed.rotation[1] > after_bad.rotation[1]);
    try std.testing.expectEqual(after_bad.rotation[2], after_fixed.rotation[2]);
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
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        \\[[entities]]
        \\id = "alternate-two"
        \\name = "Alternate Two"
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        ,
    });

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();
    try std.testing.expectEqualStrings(default_scene_path, live_project.project.default_scene);
    try std.testing.expectEqual(@as(usize, 3), live_project.scene.entityCount());

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
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
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
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
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
    defer freeCheckResult(std.testing.allocator, result);

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

fn writeRotateScript(io: Io, root_dir: Io.Dir, delta_expression: []const u8) !void {
    var buffer: [1536]u8 = undefined;
    const data = try std.fmt.bufPrint(
        &buffer,
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local Spin = ecs.component("spin", {{
        \\  fields = ecs.fields({{
        \\    angular_velocity = "vec3",
        \\  }}),
        \\}})
        \\local RotatingCubes = ecs.query(Transform, Spin)
        \\
        \\ecs.system("rotate_cubes", {{
        \\  query = RotatingCubes,
        \\  writes = ecs.refs(Transform),
        \\  run = function(world, dt)
        \\    for _entity, transform, spin in RotatingCubes:iter(world) do
        \\      transform.rotation = {{
        \\        transform.rotation[1] + spin.angular_velocity[1] * ({s}),
        \\        transform.rotation[2] + spin.angular_velocity[2] * ({s}),
        \\        transform.rotation[3] + spin.angular_velocity[3] * ({s}),
        \\      }}
        \\    end
        \\  end,
        \\}})
    ,
        .{ delta_expression, delta_expression, delta_expression },
    );
    try root_dir.writeFile(io, .{
        .sub_path = "scripts/gameplay.luau",
        .data = data,
    });
}

fn expectFloatField(
    world: World,
    entity_id: []const u8,
    component_id: []const u8,
    field_name: []const u8,
    expected: f32,
) !void {
    const entity = world.findEntityById(entity_id) orelse return error.TestExpectedEqual;
    const value = try world.getComponentFieldValue(entity, component_id, field_name);
    switch (value) {
        .float => |actual| try std.testing.expectApproxEqAbs(expected, actual, 0.0001),
        else => return error.TestExpectedEqual,
    }
}

fn expectBooleanField(
    world: World,
    entity_id: []const u8,
    component_id: []const u8,
    field_name: []const u8,
    expected: bool,
) !void {
    const entity = world.findEntityById(entity_id) orelse return error.TestExpectedEqual;
    const value = try world.getComponentFieldValue(entity, component_id, field_name);
    switch (value) {
        .boolean => |actual| try std.testing.expectEqual(expected, actual),
        else => return error.TestExpectedEqual,
    }
}

fn writeSpinnerScene(io: Io, root_dir: Io.Dir) !void {
    try root_dir.writeFile(io, .{
        .sub_path = default_scene_path,
        .data =
        \\name = "Main"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001"
        \\name = "Spinner"
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        \\[entities.components.spin]
        \\angular_velocity = [1.0, 1.0, 0.0]
        \\
        ,
    });
}
