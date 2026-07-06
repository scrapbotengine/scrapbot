const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const root = @import("root.zig");
const render = @import("render.zig");
const runtime = @import("runtime.zig");
const script = @import("script.zig");
const project_build = @import("project/build.zig");

const CheckSystemRunner = root.CheckSystemRunner;
const LiveProject = root.LiveProject;
const ProjectError = root.ProjectError;
const ReloadResult = root.ReloadResult;
const SystemProfileSnapshot = root.SystemProfileSnapshot;
const World = root.World;
const build_default_output_dir_name = project_build.default_output_dir_name;
const build_manifest_path = project_build.manifest_path;
const build_native_artifact_dir = project_build.native_artifact_dir;
const checkProject = root.checkProject;
const checkProjectDetailed = root.checkProjectDetailed;
const default_scene_path = root.default_scene_path;
const freeCheckResult = root.freeCheckResult;
const freeProject = root.freeProject;
const freeScene = root.freeScene;
const freeStepDetailedResult = root.freeStepDetailedResult;
const initProject = root.initProject;
const legacy_project_file_name = root.legacy_project_file_name;
const loadDefaultScene = root.loadDefaultScene;
const loadProject = root.loadProject;
const project_file_name = root.project_file_name;
const sceneUiPointerPosition = root.sceneUiPointerPosition;
const stepProjectDetailed = root.stepProjectDetailed;
const buildProject = root.buildProject;

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
    try std.testing.expect(fileExists(io, root_dir, "assets/.gitkeep"));
    try std.testing.expect(fileExists(io, root_dir, default_scene_path));
    try std.testing.expect(!fileExists(io, root_dir, "native/game.zig"));

    const metadata = try root_dir.readFileAlloc(io, project_file_name, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(metadata);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "\n# native = \"native/game.zig\"\n") != null);

    const project = try loadProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, project);

    var scene = try loadDefaultScene(io, std.testing.allocator, project);
    defer freeScene(std.testing.allocator, scene);
    const renderer_settings = scene.world.rendererSettings() orelse return error.TestExpectedEqual;
    try std.testing.expect(renderer_settings.hdr);
    try std.testing.expectEqualStrings("aces", renderer_settings.tone_mapping);
    try std.testing.expect(renderer_settings.postprocess_enabled);
    try std.testing.expectEqualStrings("fxaa", renderer_settings.antialiasing);
    try std.testing.expect(renderer_settings.bloom_enabled);
}

test "loadProject accepts legacy project metadata filename" {
    const root_path = ".zig-cache/test-load-legacy-project-file";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try cwd.createDirPath(io, root_path);
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try root_dir.writeFile(io, .{
        .sub_path = legacy_project_file_name,
        .data = "name = \"Legacy Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n",
    });

    const project = try loadProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, project);

    try std.testing.expectEqualStrings("Legacy Game", project.name);
    try std.testing.expectEqualStrings(default_scene_path, project.default_scene);
}

test "loadProject prefers project.toml over legacy project metadata" {
    const root_path = ".zig-cache/test-load-project-file-precedence";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try cwd.createDirPath(io, root_path);
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try root_dir.writeFile(io, .{
        .sub_path = legacy_project_file_name,
        .data = "name = \"Legacy Game\"\nversion = 1\ndefault_scene = \"scenes/legacy.scene.toml\"\n",
    });
    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Canonical Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n",
    });

    const project = try loadProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, project);

    try std.testing.expectEqualStrings("Canonical Game", project.name);
    try std.testing.expectEqualStrings(default_scene_path, project.default_scene);
}

test "initProject refuses to overwrite an existing project" {
    const root_path = ".zig-cache/test-init-project-existing";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Demo");
    try std.testing.expectError(ProjectError.AlreadyExists, initProject(io, std.testing.allocator, root_path, "Demo"));
}

test "initProject refuses to overwrite a legacy project" {
    const root_path = ".zig-cache/test-init-project-existing-legacy";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try cwd.createDirPath(io, root_path);
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try root_dir.writeFile(io, .{
        .sub_path = legacy_project_file_name,
        .data = "name = \"Legacy Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n",
    });

    try std.testing.expectError(ProjectError.AlreadyExists, initProject(io, std.testing.allocator, root_path, "Demo"));
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

test "loadProject accepts packaged native artifact metadata" {
    const root_path = ".zig-cache/test-load-project-native-artifact";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.zig\"\nnative_artifact = \".scrapbot/build/native/libscrapbot_project.dylib\"\n",
    });

    const project = try loadProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, project);
    try std.testing.expectEqualStrings("native/game.zig", project.native.?);
    try std.testing.expectEqualStrings(".scrapbot/build/native/libscrapbot_project.dylib", project.native_artifact.?);
}

test "loadDefaultScene parses renderer singleton settings" {
    const root_path = ".zig-cache/test-load-scene-renderer-settings";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try root_dir.writeFile(io, .{ .sub_path = default_scene_path, .data =
        \\name = "Main"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "scrapbot.renderer"
        \\name = "Renderer"
        \\
        \\[entities.components."scrapbot.renderer"]
        \\hdr = true
        \\tone_mapping = "reinhard"
        \\exposure = 0.5
        \\postprocess_enabled = true
        \\antialiasing = "fxaa"
        \\bloom_enabled = true
        \\bloom_threshold = 0.8
        \\bloom_intensity = 0.3
        \\bloom_radius = 2.0
        \\vignette_enabled = true
        \\vignette_strength = 0.4
        \\vignette_radius = 0.75
        \\chromatic_aberration_enabled = true
        \\chromatic_aberration_strength = 0.01
        \\
    });

    const project = try loadProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, project);
    var scene = try loadDefaultScene(io, std.testing.allocator, project);
    defer freeScene(std.testing.allocator, scene);

    const renderer_settings = scene.world.rendererSettings() orelse return error.TestExpectedEqual;
    try std.testing.expect(renderer_settings.hdr);
    try std.testing.expectEqualStrings("reinhard", renderer_settings.tone_mapping);
    try std.testing.expectEqual(@as(f32, 0.5), renderer_settings.exposure);
    try std.testing.expect(renderer_settings.postprocess_enabled);
    try std.testing.expectEqualStrings("fxaa", renderer_settings.antialiasing);
    try std.testing.expect(renderer_settings.vignette_enabled);
    try std.testing.expectEqual(@as(f32, 0.4), renderer_settings.vignette_strength);
    try std.testing.expectEqual(@as(f32, 0.75), renderer_settings.vignette_radius);
    try std.testing.expect(renderer_settings.chromatic_aberration_enabled);
    try std.testing.expectEqual(@as(f32, 0.01), renderer_settings.chromatic_aberration_strength);
    try std.testing.expect(renderer_settings.bloom_enabled);
    try std.testing.expectEqual(@as(f32, 0.8), renderer_settings.bloom_threshold);
    try std.testing.expectEqual(@as(f32, 0.3), renderer_settings.bloom_intensity);
    try std.testing.expectEqual(@as(f32, 2.0), renderer_settings.bloom_radius);
}

test "buildNativeArtifactProjectPath uses project metadata separators" {
    const path = try project_build.buildNativeArtifactProjectPath(std.testing.allocator);
    defer std.testing.allocator.free(path);

    try std.testing.expect(std.mem.startsWith(u8, path, ".scrapbot/build/native/"));
    try std.testing.expect(std.mem.indexOfScalar(u8, path, '\\') == null);
}

test "copyPackagedNativeArtifact copies artifact from excluded scrapbot cache" {
    const root_path = ".zig-cache/test-copy-packaged-native-artifact-source";
    const bundle_project_path = ".zig-cache/test-copy-packaged-native-artifact-bundle/project";
    const artifact_path = ".scrapbot/build/native/libscrapbot_project.test";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    cwd.deleteTree(io, ".zig-cache/test-copy-packaged-native-artifact-bundle") catch {};
    defer cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, ".zig-cache/test-copy-packaged-native-artifact-bundle") catch {};

    try initProject(io, std.testing.allocator, root_path, "Artifact Native");
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try root_dir.createDirPath(io, build_native_artifact_dir);
    try root_dir.writeFile(io, .{
        .sub_path = artifact_path,
        .data = "native artifact bytes",
    });
    try cwd.createDirPath(io, bundle_project_path);

    try project_build.copyPackagedNativeArtifact(io, std.testing.allocator, cwd, root_path, bundle_project_path, artifact_path);

    const packaged_artifact_path = try std.fs.path.join(std.testing.allocator, &.{ bundle_project_path, artifact_path });
    defer std.testing.allocator.free(packaged_artifact_path);
    try std.testing.expect(fileExists(io, cwd, packaged_artifact_path));
}

test "buildProject creates a host bundle for a simple project" {
    const root_path = ".zig-cache/test-build-project-source";
    const output_root = ".zig-cache/test-build-project-output";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    cwd.deleteTree(io, output_root) catch {};
    defer cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, output_root) catch {};

    try initProject(io, std.testing.allocator, root_path, "Demo Game");
    const result = try buildProject(io, std.testing.allocator, root_path, .{
        .output_root = output_root,
        .name = "demo-game-test",
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(fileExists(io, cwd, result.launcher_path));
    try std.testing.expect(fileExists(io, cwd, result.runtime_path));
    const packaged_manifest = try std.fs.path.join(std.testing.allocator, &.{ result.project_path, project_file_name });
    defer std.testing.allocator.free(packaged_manifest);
    try std.testing.expect(fileExists(io, cwd, packaged_manifest));
    const build_manifest = try std.fs.path.join(std.testing.allocator, &.{ result.bundle_path, build_manifest_path });
    defer std.testing.allocator.free(build_manifest);
    try std.testing.expect(fileExists(io, cwd, build_manifest));

    const launcher_contents = try cwd.readFileAlloc(io, result.launcher_path, std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(launcher_contents);
    switch (builtin.os.tag) {
        .windows => try std.testing.expect(std.mem.indexOf(u8, launcher_contents, "PATH=%SCRIPT_DIR%lib;%SCRIPT_DIR%bin;%PATH%") != null),
        .macos => try std.testing.expect(std.mem.indexOf(u8, launcher_contents, "DYLD_LIBRARY_PATH") != null),
        .linux => try std.testing.expect(std.mem.indexOf(u8, launcher_contents, "LD_LIBRARY_PATH") != null),
        else => {},
    }
}

test "buildProject default output skips absolute in-project output tree" {
    const root_path = ".zig-cache/test-build-project-absolute-source";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Demo Absolute");
    const absolute_root_path = try project_build.absoluteCwdPath(std.testing.allocator, io, root_path);
    defer std.testing.allocator.free(absolute_root_path);

    const result = try buildProject(io, std.testing.allocator, absolute_root_path, .{
        .name = "demo-absolute-test",
    });
    defer result.deinit(std.testing.allocator);

    const expected_bundle_path = try std.fs.path.join(std.testing.allocator, &.{
        absolute_root_path,
        build_default_output_dir_name,
        "demo-absolute-test",
    });
    defer std.testing.allocator.free(expected_bundle_path);
    try std.testing.expectEqualStrings(expected_bundle_path, result.bundle_path);

    const copied_output_root = try std.fs.path.join(std.testing.allocator, &.{ result.project_path, build_default_output_dir_name });
    defer std.testing.allocator.free(copied_output_root);
    try std.testing.expect(!fileExists(io, cwd, copied_output_root));
}

test "buildProject output at project root skips bundle directory" {
    const root_path = ".zig-cache/test-build-project-root-output";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Root Output");
    const absolute_root_path = try project_build.absoluteCwdPath(std.testing.allocator, io, root_path);
    defer std.testing.allocator.free(absolute_root_path);

    const result = try buildProject(io, std.testing.allocator, absolute_root_path, .{
        .output_root = absolute_root_path,
        .name = "root-output-test",
    });
    defer result.deinit(std.testing.allocator);

    const copied_bundle_root = try std.fs.path.join(std.testing.allocator, &.{ result.project_path, "root-output-test" });
    defer std.testing.allocator.free(copied_bundle_root);
    try std.testing.expect(!fileExists(io, cwd, copied_bundle_root));
}

test "buildProject rejects nested in-project output root" {
    const root_path = ".zig-cache/test-build-project-nested-output";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Nested Output");
    const nested_output_root = try std.fs.path.join(std.testing.allocator, &.{ root_path, "assets", "build" });
    defer std.testing.allocator.free(nested_output_root);

    try std.testing.expectError(ProjectError.InvalidBuildOutput, buildProject(io, std.testing.allocator, root_path, .{
        .output_root = nested_output_root,
        .name = "nested-output-test",
    }));
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
    try std.testing.expectEqual(@as(usize, 4), scene.entityCount());
    try std.testing.expectEqual(@as(usize, 1), scene.renderableMeshCount());

    const entity = scene.world.findEntityById("018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(runtime.EntityProvenance.authored, (try scene.world.entity(entity)).provenance);
    const mesh = scene.world.renderableMeshAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(entity.index, mesh.entity.index);
    try std.testing.expectEqualStrings("box", mesh.primitive);
    try std.testing.expectEqual(@as(f32, 0.56), mesh.base_color[1]);

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
    const query = [_][]const u8{ "scrapbot.transform", "spin" };
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
        \\[entities.components."scrapbot.transform"]
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
        \\[entities.components."scrapbot.transform"]
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
        \\[entities.components."scrapbot.transform"]
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
        \\[entities.components."scrapbot.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        \\[[entities]]
        \\id = "same-id"
        \\name = "Two"
        \\
        \\[entities.components."scrapbot.transform"]
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
        \\[entities.components."scrapbot.transform"]
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
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
        \\local RenderCube = ecs.component<<ScrapbotRenderCube>>("scrapbot.render.cube")
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
        \\ecs.component("scrapbot.bad", {
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
    try std.testing.expectEqual(@as(usize, 4), live_project.scene.entityCount());
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
        \\[entities.components."scrapbot.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        \\[[entities]]
        \\id = "two"
        \\name = "Two"
        \\
        \\[entities.components."scrapbot.transform"]
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
        \\[entities.components."scrapbot.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        \\[[entities]]
        \\id = "same"
        \\name = "Two"
        \\
        \\[entities.components."scrapbot.transform"]
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
        \\ecs.component("scrapbot.bad", {
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
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
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
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
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
        \\[entities.components."scrapbot.ui.canvas"]
        \\design_size = [640.0, 480.0, 0.0]
        \\scale_mode = "fit"
        \\
        \\[[entities]]
        \\id = "button"
        \\name = "Button"
        \\
        \\[entities.components."scrapbot.ui.rect"]
        \\position = [32.0, 24.0, 0.0]
        \\size = [120.0, 48.0, 0.0]
        \\color = [0.0, 0.2, 0.4]
        \\
        \\[entities.components."scrapbot.ui.button"]
        \\
        \\[entities.components."scrapbot.ui.command"]
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
        \\local CommandEvent = ecs.component<<ScrapbotUiCommandEvent>>("scrapbot.ui.command_event")
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
        \\[entities.components."scrapbot.ui.stack"]
        \\position = [100.0, 24.0, 0.0]
        \\spacing = 12.0
        \\direction = "horizontal"
        \\padding = [0.0, 0.0, 0.0]
        \\
        \\[[entities]]
        \\id = "button"
        \\name = "Button"
        \\
        \\[entities.components."scrapbot.ui.rect"]
        \\position = [0.0, 0.0, 0.0]
        \\size = [120.0, 48.0, 0.0]
        \\color = [0.0, 0.2, 0.4]
        \\
        \\[entities.components."scrapbot.ui.button"]
        \\
        \\[entities.components."scrapbot.ui.layout.item"]
        \\parent = "toolbar"
        \\order = 0
        \\
        \\[entities.components."scrapbot.ui.command"]
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
        \\local CommandEvent = ecs.component<<ScrapbotUiCommandEvent>>("scrapbot.ui.command_event")
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
        \\[entities.components."scrapbot.ui.scroll_view"]
        \\position = [10.0, 10.0, 0.0]
        \\size = [100.0, 40.0, 0.0]
        \\content_offset = [0.0, 0.0, 0.0]
        \\
        \\[[entities]]
        \\id = "stack"
        \\name = "Stack"
        \\
        \\[entities.components."scrapbot.ui.vgroup"]
        \\position = [0.0, 0.0, 0.0]
        \\size = [100.0, 96.0, 0.0]
        \\spacing = 0.0
        \\padding = [0.0, 0.0, 0.0]
        \\
        \\[entities.components."scrapbot.ui.layout.item"]
        \\parent = "scroll"
        \\order = 0
        \\
        \\[[entities]]
        \\id = "row-1"
        \\name = "Row 1"
        \\
        \\[entities.components."scrapbot.ui.text"]
        \\position = [0.0, 0.0, 0.0]
        \\size = 1.0
        \\color = [1.0, 1.0, 1.0]
        \\value = "ROW 1"
        \\
        \\[entities.components."scrapbot.ui.layout.item"]
        \\parent = "stack"
        \\order = 0
        \\
        \\[[entities]]
        \\id = "row-2"
        \\name = "Row 2"
        \\
        \\[entities.components."scrapbot.ui.text"]
        \\position = [0.0, 0.0, 0.0]
        \\size = 1.0
        \\color = [1.0, 1.0, 1.0]
        \\value = "ROW 2"
        \\
        \\[entities.components."scrapbot.ui.layout.item"]
        \\parent = "stack"
        \\order = 1
        \\
        \\[[entities]]
        \\id = "row-3"
        \\name = "Row 3"
        \\
        \\[entities.components."scrapbot.ui.text"]
        \\position = [0.0, 0.0, 0.0]
        \\size = 1.0
        \\color = [1.0, 1.0, 1.0]
        \\value = "ROW 3"
        \\
        \\[entities.components."scrapbot.ui.layout.item"]
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
            try std.testing.expect(std.mem.indexOf(u8, failure.diagnostic.message, "scrapbot.transform.rotation") != null);

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
        \\[entities.components."scrapbot.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        \\[[entities]]
        \\id = "alternate-two"
        \\name = "Alternate Two"
        \\
        \\[entities.components."scrapbot.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        ,
    });

    var live_project = try LiveProject.init(io, std.testing.allocator, root_path);
    defer live_project.deinit();
    try std.testing.expectEqualStrings(default_scene_path, live_project.project.default_scene);
    try std.testing.expectEqual(@as(usize, 4), live_project.scene.entityCount());

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
        \\[entities.components."scrapbot.transform"]
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
        \\[entities.components."scrapbot.transform"]
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
        loadProject(io, std.testing.allocator, root_path),
    );
}

fn writeRotateScript(io: Io, root_dir: Io.Dir, delta_expression: []const u8) !void {
    var buffer: [1536]u8 = undefined;
    const data = try std.fmt.bufPrint(
        &buffer,
        \\--!strict
        \\
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
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
        \\[entities.components."scrapbot.transform"]
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
