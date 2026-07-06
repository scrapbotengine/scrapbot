const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const render = @import("render.zig");
const render_verify = @import("render_verify.zig");
const geometry = @import("geometry.zig");
const native = @import("native.zig");
const project_build = @import("project/build.zig");
const runtime = @import("runtime.zig");
const scene_loader = @import("project/scene_loader.zig");
const script = @import("script.zig");
const ui_layout = @import("ui_layout.zig");

pub const version = "0.1.0-dev";
pub const project_file_name = "project.toml";
pub const legacy_project_file_name = "project.scrapbot.toml";
pub const default_scene_path = "scenes/main.scene.toml";

pub const renderDemoImage = render.renderDemoImage;
pub const renderDemoImageWithInput = render.renderDemoImageWithInput;
pub const renderDemoImageFrames = render.renderDemoImageFrames;
pub const renderStats = render.stats;
pub const runDemoWindow = render.runDemoWindow;
pub const default_output_width = render.default_output_width;
pub const default_output_height = render.default_output_height;
pub const WindowOptions = render.WindowOptions;
pub const ImageRenderOptions = render.ImageRenderOptions;
pub const FrameUpdateHook = render.FrameUpdateHook;
pub const FrameInput = render.FrameInput;
pub const PointerInput = render.PointerInput;
pub const EditorFrameState = render.EditorFrameState;
pub const EditorState = render.EditorState;
pub const RenderScene = render.Scene;
pub const RenderStats = render.Stats;
pub const RenderVerification = render_verify.Verification;
pub const RenderVerificationOptions = render_verify.VerificationOptions;
pub const RenderComparison = render_verify.Comparison;
pub const RenderComparisonOptions = render_verify.ComparisonOptions;
pub const World = runtime.World;
pub const EntityHandle = runtime.EntityHandle;
pub const Transform = runtime.Transform;
pub const CubeRenderer = runtime.CubeRenderer;
pub const GeometryPrimitive = runtime.GeometryPrimitive;
pub const SurfaceMaterial = runtime.SurfaceMaterial;
pub const Camera = runtime.Camera;
pub const DirectionalLight = runtime.DirectionalLight;
pub const RendererSettings = runtime.RendererSettings;
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
pub const ScriptDiagnosticStage = script.DiagnosticStage;
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
pub const verifyRenderImage = render_verify.verifyImage;
pub const compareRenderImage = render_verify.compareImage;
pub const writeFrameInput = render.writeFrameInput;

pub const Project = struct {
    root_path: []const u8,
    name: []const u8,
    default_scene: []const u8,
    scripts: []const []const u8,
    native: ?[]const u8 = null,
    native_artifact: ?[]const u8 = null,
};

pub const Scene = scene_loader.Scene;

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
    input_frames: []const StepInputFrame = &.{},
};

pub const StepInputFrame = struct {
    frame: u32,
    input: FrameInput,
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

pub const build_default_output_dir_name = project_build.default_output_dir_name;
const build_bundle_marker = project_build.bundle_marker;
const build_project_dir = project_build.project_dir;
const build_bin_dir = project_build.bin_dir;
const build_lib_dir = project_build.lib_dir;
const build_manifest_path = project_build.manifest_path;
const build_native_artifact_dir = project_build.native_artifact_dir;

pub const BuildOptions = struct {
    output_root: ?[]const u8 = null,
    name: ?[]const u8 = null,
    force: bool = false,
};

pub const BuildResult = struct {
    project_name: []const u8,
    bundle_path: []const u8,
    project_path: []const u8,
    runtime_path: []const u8,
    launcher_path: []const u8,
    native_artifact: ?[]const u8 = null,
    sdl3_bundled: bool = false,
    sdl3_warning: ?[]const u8 = null,

    pub fn deinit(self: BuildResult, allocator: std.mem.Allocator) void {
        allocator.free(self.project_name);
        allocator.free(self.bundle_path);
        allocator.free(self.project_path);
        allocator.free(self.runtime_path);
        allocator.free(self.launcher_path);
        if (self.native_artifact) |path| {
            allocator.free(path);
        }
        if (self.sdl3_warning) |message| {
            allocator.free(message);
        }
    }
};

pub const BuildDetailedResult = union(enum) {
    ok: BuildResult,
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
        return .{ .world = &self.scene.world };
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
            std.log.err("editor interaction failed: {s}", .{@errorName(err)});
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
            routed_input.pointer.delta = .{ 0.0, 0.0 };
            routed_input.pointer.primary_down = false;
            routed_input.pointer.primary_pressed = false;
            routed_input.pointer.primary_released = false;
            routed_input.pointer.secondary_down = false;
            routed_input.pointer.secondary_pressed = false;
            routed_input.pointer.secondary_released = false;
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

    if (try routeUiCommandAt(world, pointer_position)) |hit| {
        try emitUiCommandEvent(world, hit.command, hit.source);
    }
}

pub fn sceneUiPointerPosition(world: *World, input_entity: runtime.EntityHandle, pointer_position: [2]f32) ![2]f32 {
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

fn routeUiCommandAt(world: *World, pointer_position: [2]f32) anyerror!?ui_layout.CommandHit {
    return ui_layout.commandAt(world, pointer_position) catch |err| return mapLayoutError(err);
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
    InvalidBuildOutput,
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

    if (fileExists(io, root_dir, project_file_name) or fileExists(io, root_dir, legacy_project_file_name)) {
        return ProjectError.AlreadyExists;
    }

    try root_dir.createDirPath(io, "scenes");
    try root_dir.createDirPath(io, "assets");

    const escaped_name = try encodeTomlBasicString(allocator, name);
    defer allocator.free(escaped_name);

    const project_contents = try std.fmt.allocPrint(
        allocator,
        "name = \"{s}\"\nversion = 1\ndefault_scene = \"{s}\"\n\n# native = \"native/game.zig\"\n",
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
            \\id = "scrapbot.renderer"
            \\name = "Renderer"
            \\
            \\[entities.components."scrapbot.renderer"]
            \\hdr = true
            \\tone_mapping = "aces"
            \\exposure = 0.0
            \\postprocess_enabled = true
            \\antialiasing = "fxaa"
            \\bloom_enabled = true
            \\bloom_threshold = 0.85
            \\bloom_intensity = 0.12
            \\bloom_radius = 1.0
            \\vignette_enabled = true
            \\vignette_strength = 0.24
            \\vignette_radius = 0.82
            \\chromatic_aberration_enabled = true
            \\chromatic_aberration_strength = 0.0025
            \\
            \\[[entities]]
            \\id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001"
            \\name = "Demo Cube"
            \\
            \\[entities.components."scrapbot.transform"]
            \\position = [0.0, 0.0, 0.0]
            \\rotation = [0.0, 0.0, 0.0]
            \\scale = [1.0, 1.0, 1.0]
            \\
            \\[entities.components."scrapbot.geometry.primitive"]
            \\primitive = "box"
            \\segments = 0
            \\rings = 0
            \\
            \\[entities.components."scrapbot.material.surface"]
            \\base_color = [0.0, 0.56, 1.0]
            \\
            \\[[entities]]
            \\id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0002"
            \\name = "Main Camera"
            \\
            \\[entities.components."scrapbot.transform"]
            \\position = [0.0, 0.0, 4.8]
            \\rotation = [0.0, 0.0, 0.0]
            \\scale = [1.0, 1.0, 1.0]
            \\
            \\[entities.components."scrapbot.camera"]
            \\fov_y_degrees = 48.0
            \\near = 0.1
            \\far = 100.0
            \\
            \\[[entities]]
            \\id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0003"
            \\name = "Key Light"
            \\
            \\[entities.components."scrapbot.light.directional"]
            \\direction = [0.35, 0.68, 0.64]
            \\color = [1.0, 1.0, 1.0]
            \\intensity = 0.78
            \\ambient = 0.18
            \\
            ,
            .flags = .{ .exclusive = true },
        });
    }

    {
        try root_dir.writeFile(io, .{
            .sub_path = "assets/.gitkeep",
            .data = "",
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
            const scene = try scene_loader.loadSceneFile(io, allocator, root_dir, project.default_scene, scripts.registry);
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

    var scene = try scene_loader.loadSceneFile(io, allocator, root_dir, project.default_scene, scripts.registry);
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

    var editor_state = EditorState{};
    while (completed_frames < options.frames) {
        const frame_number = completed_frames + 1;
        if (options.input_frames.len > 0) {
            var editor_input = stepInputForFrame(options.input_frames, frame_number);
            const render_profile_count = editor_input.system_profile_count_hint;
            editor_input.delta_seconds = options.delta_seconds;
            editor_input.editor = render.editorFrameState(&scene.world, editor_state);
            editor_input.system_profiles = scripts.systemProfileSnapshots();
            editor_input.system_profile_count_hint = editor_input.system_profiles.len + render_profile_count;

            var routed_input = editor_input;
            const editor_update = try render.updateEditorState(allocator, &scene.world, &editor_state, editor_input);
            routed_input.editor = render.editorFrameState(&scene.world, editor_state);
            if (editor_update.consumed_pointer) {
                routed_input.pointer.delta = .{ 0.0, 0.0 };
                routed_input.pointer.primary_down = false;
                routed_input.pointer.primary_pressed = false;
                routed_input.pointer.primary_released = false;
                routed_input.pointer.secondary_down = false;
                routed_input.pointer.secondary_pressed = false;
                routed_input.pointer.secondary_released = false;
                routed_input.pointer.wheel_delta = .{ 0.0, 0.0 };
            }

            try render.writeFrameInput(&scene.world, routed_input);
            try updateSceneUiScrollViews(&scene.world);
            try updateUiCommandEvents(&scene.world);
        }

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

pub fn buildProject(
    io: Io,
    allocator: std.mem.Allocator,
    root_path: []const u8,
    options: BuildOptions,
) !BuildResult {
    var result = try buildProjectDetailed(io, allocator, root_path, options);
    switch (result) {
        .ok => |ok| return ok,
        .invalid => |*diagnostic| {
            diagnostic.deinit(allocator);
            return ProjectError.InvalidScript;
        },
    }
}

pub fn buildProjectDetailed(
    io: Io,
    allocator: std.mem.Allocator,
    root_path: []const u8,
    options: BuildOptions,
) !BuildDetailedResult {
    const project = try loadProject(io, allocator, root_path);
    defer freeProject(allocator, project);

    const bundle_name = if (options.name) |name|
        try allocator.dupe(u8, name)
    else
        try project_build.defaultBuildBundleName(allocator, project.name);
    defer allocator.free(bundle_name);
    if (!project_build.isSafeBundleName(bundle_name)) {
        return ProjectError.InvalidProjectName;
    }

    const cwd = Io.Dir.cwd();
    const output_root = if (options.output_root) |path|
        try allocator.dupe(u8, path)
    else
        try std.fs.path.join(allocator, &.{ project.root_path, build_default_output_dir_name });
    defer allocator.free(output_root);

    const bundle_path = try std.fs.path.join(allocator, &.{ output_root, bundle_name });
    var keep_bundle_path = false;
    defer if (!keep_bundle_path) allocator.free(bundle_path);
    if (fileExists(io, cwd, bundle_path)) {
        if (!options.force or !project_build.isScrapbotBuildBundle(io, cwd, bundle_path)) {
            return ProjectError.AlreadyExists;
        }
        try cwd.deleteTree(io, bundle_path);
    }
    var keep_bundle_tree = false;
    defer if (!keep_bundle_tree) cwd.deleteTree(io, bundle_path) catch {};

    try cwd.createDirPath(io, bundle_path);
    const bundle_dir = try cwd.openDir(io, bundle_path, .{});
    defer bundle_dir.close(io);
    try bundle_dir.writeFile(io, .{
        .sub_path = build_bundle_marker,
        .data = "scrapbot build bundle\n",
    });
    try bundle_dir.createDirPath(io, build_project_dir);
    try bundle_dir.createDirPath(io, build_bin_dir);
    try bundle_dir.createDirPath(io, build_lib_dir);

    const project_bundle_path = try std.fs.path.join(allocator, &.{ bundle_path, build_project_dir });
    var keep_project_bundle_path = false;
    defer if (!keep_project_bundle_path) allocator.free(project_bundle_path);
    const output_root_entry_to_skip = try project_build.outputRootEntryToSkip(allocator, io, project.root_path, output_root, bundle_path);
    defer if (output_root_entry_to_skip) |entry| allocator.free(entry);
    try project_build.copyProjectTree(io, allocator, project.root_path, project_bundle_path, output_root_entry_to_skip);

    const runtime_source_path = try std.process.executablePathAlloc(io, allocator);
    defer allocator.free(runtime_source_path);
    const runtime_name = project_build.executableFileName();
    const runtime_bundle_path = try std.fs.path.join(allocator, &.{ bundle_path, build_bin_dir, runtime_name });
    var keep_runtime_bundle_path = false;
    defer if (!keep_runtime_bundle_path) allocator.free(runtime_bundle_path);
    try cwd.copyFile(runtime_source_path, cwd, runtime_bundle_path, io, .{ .make_path = true, .replace = true });

    var native_artifact: ?[]u8 = null;
    var keep_native_artifact = false;
    defer if (!keep_native_artifact) {
        if (native_artifact) |path| allocator.free(path);
    };
    if (project.native) |native_path| {
        const native_artifact_project_path = try project_build.buildNativeArtifactProjectPath(allocator);
        var keep_native_artifact_project_path = false;
        defer if (!keep_native_artifact_project_path) allocator.free(native_artifact_project_path);
        {
            const project_bundle_dir = try cwd.openDir(io, project_bundle_path, .{});
            defer project_bundle_dir.close(io);
            try project_bundle_dir.createDirPath(io, build_native_artifact_dir);
        }
        const native_output_path = try std.fs.path.join(allocator, &.{ project_bundle_path, native_artifact_project_path });
        defer allocator.free(native_output_path);
        const absolute_native_output_path = try project_build.absoluteCwdPath(allocator, io, native_output_path);
        defer allocator.free(absolute_native_output_path);
        if (try native.buildProjectDynamicLibraryDetailed(io, allocator, project.root_path, native_path, absolute_native_output_path, .release_fast)) |diagnostic| {
            return .{ .invalid = diagnostic };
        }
        try rewritePackagedProjectManifest(io, allocator, project_bundle_path, native_artifact_project_path);
        native_artifact = native_artifact_project_path;
        keep_native_artifact_project_path = true;
    } else if (project.native_artifact) |artifact_path| {
        try project_build.copyPackagedNativeArtifact(io, allocator, cwd, project.root_path, project_bundle_path, artifact_path);
        native_artifact = try allocator.dupe(u8, artifact_path);
    }

    const packaged_check = try checkProjectDetailed(io, allocator, project_bundle_path);
    switch (packaged_check) {
        .ok => |ok| freeCheckResult(allocator, ok),
        .invalid => |diagnostic| return .{ .invalid = diagnostic },
    }

    const launcher_name = project_build.launcherFileName();
    const launcher_path = try std.fs.path.join(allocator, &.{ bundle_path, launcher_name });
    var keep_launcher_path = false;
    defer if (!keep_launcher_path) allocator.free(launcher_path);
    try project_build.writeLauncher(io, bundle_dir, launcher_name);

    const sdl3_bundled = try project_build.copyDiscoverableSdl3(io, cwd, bundle_dir);
    const sdl3_warning = if (sdl3_bundled)
        null
    else
        try allocator.dupe(u8, "SDL3 was not copied; the target machine must provide a compatible SDL3 runtime library.");
    var keep_sdl3_warning = false;
    defer if (!keep_sdl3_warning) {
        if (sdl3_warning) |message| allocator.free(message);
    };

    try project_build.writeBuildManifest(io, allocator, bundle_dir, .{
        .project_name = project.name,
        .bundle_path = bundle_path,
        .runtime_path = runtime_bundle_path,
        .project_path = project_bundle_path,
        .native_artifact = native_artifact,
        .sdl3_bundled = sdl3_bundled,
        .sdl3_warning = sdl3_warning,
    });

    const result_project_name = try allocator.dupe(u8, project.name);
    errdefer allocator.free(result_project_name);

    const result = BuildResult{
        .project_name = result_project_name,
        .bundle_path = bundle_path,
        .project_path = project_bundle_path,
        .runtime_path = runtime_bundle_path,
        .launcher_path = launcher_path,
        .native_artifact = native_artifact,
        .sdl3_bundled = sdl3_bundled,
        .sdl3_warning = sdl3_warning,
    };

    keep_bundle_tree = true;
    keep_bundle_path = true;
    keep_project_bundle_path = true;
    keep_runtime_bundle_path = true;
    keep_launcher_path = true;
    keep_native_artifact = true;
    keep_sdl3_warning = true;

    return .{ .ok = result };
}

fn stepInputForFrame(input_frames: []const StepInputFrame, frame: u32) FrameInput {
    for (input_frames) |input_frame| {
        if (input_frame.frame == frame) {
            return input_frame.input;
        }
    }
    return .{};
}

fn rewritePackagedProjectManifest(
    io: Io,
    allocator: std.mem.Allocator,
    project_bundle_path: []const u8,
    native_artifact_path: []const u8,
) !void {
    const cwd = Io.Dir.cwd();
    const project_dir = try cwd.openDir(io, project_bundle_path, .{});
    defer project_dir.close(io);

    const metadata_file_name = projectMetadataFileName(io, project_dir) orelse return ProjectError.MissingProjectFile;
    const contents = try project_dir.readFileAlloc(io, metadata_file_name, allocator, .limited(64 * 1024));
    defer allocator.free(contents);
    const escaped_artifact = try encodeTomlBasicString(allocator, native_artifact_path);
    defer allocator.free(escaped_artifact);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        const is_native_artifact = if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_index|
            std.mem.eql(u8, std.mem.trim(u8, trimmed[0..eq_index], " \t"), "native_artifact")
        else
            false;
        if (!is_native_artifact) {
            try out.appendSlice(allocator, line);
            try out.append(allocator, '\n');
        }
    }
    try out.print(allocator, "native_artifact = \"{s}\"\n", .{escaped_artifact});

    try project_dir.writeFile(io, .{
        .sub_path = metadata_file_name,
        .data = out.items,
    });
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
    if (project.native_artifact) |native_artifact_path| {
        allocator.free(native_artifact_path);
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

    return scene_loader.loadSceneFile(io, allocator, root_dir, project.default_scene, registry);
}

fn statProjectFile(io: Io, root_path: []const u8) !SourceFileStamp {
    const cwd = Io.Dir.cwd();
    const root_dir = cwd.openDir(io, root_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ProjectError.InvalidProject,
        else => return err,
    };
    defer root_dir.close(io);

    const metadata_file_name = projectMetadataFileName(io, root_dir) orelse return ProjectError.MissingProjectFile;
    return statFile(io, root_dir, metadata_file_name, ProjectError.MissingProjectFile);
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
    if (project.native_artifact != null) {
        return null;
    }
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
    scene_loader.freeScene(allocator, scene);
}

fn loadProjectFile(io: Io, allocator: std.mem.Allocator, root_path: []const u8, root_dir: Io.Dir) !Project {
    const metadata_file_name = projectMetadataFileName(io, root_dir) orelse return ProjectError.MissingProjectFile;
    const contents = root_dir.readFileAlloc(io, metadata_file_name, allocator, .limited(64 * 1024)) catch |err| switch (err) {
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

    const native_artifact_path = try readOptionalString(allocator, contents, "native_artifact");
    errdefer if (native_artifact_path) |path| allocator.free(path);
    if (native_artifact_path) |path| {
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
        .native_artifact = native_artifact_path,
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

    var native_extension: ?native.LoadedExtension = if (project.native_artifact) |artifact_path| blk: {
        const native_result = try native.loadProjectArtifactDetailed(allocator, project.root_path, artifact_path);
        break :blk switch (native_result) {
            .extension => |extension| extension,
            .diagnostic => |diagnostic| return .{ .diagnostic = diagnostic },
        };
    } else if (project.native) |native_path| blk: {
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

fn projectMetadataFileName(io: Io, root_dir: Io.Dir) ?[]const u8 {
    if (fileExists(io, root_dir, project_file_name)) {
        return project_file_name;
    }
    if (fileExists(io, root_dir, legacy_project_file_name)) {
        return legacy_project_file_name;
    }
    return null;
}

test {
    _ = @import("root_tests.zig");
}
