const std = @import("std");
const machina = @import("machina");

const Io = std.Io;

const root_path = ".context/native-reload-check-project";
const native_path = "native/game.zig";
const mover_id = "native-mover";

const CheckError = error{CheckFailed};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try machina.initProject(io, allocator, root_path, "Native Reload Check");
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try root_dir.createDirPath(io, "native");

    try root_dir.writeFile(io, .{
        .sub_path = machina.project_file_name,
        .data = "name = \"Native Reload Check\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.zig\"\n",
    });
    try writeScene(io, root_dir);
    try writeNativeModule(io, root_dir, allocator, "1.0");

    var live_project = try initLiveProject(io, allocator);
    defer live_project.deinit();

    try expect(live_project.scripts.registry.findComponent("native_tick") != null, "native_tick component missing after initial load\n", .{});
    try expectEqualUsize(1, live_project.scripts.schedule.systemCount(), "initial native system count");

    try expectPositionX(&live_project.scene.world, 0.0);
    live_project.update(1.0);
    try expectPositionX(&live_project.scene.world, 2.0);

    try root_dir.writeFile(io, .{ .sub_path = native_path, .data = native_module_build_error });
    try expectReloadFailure(&live_project, .native_build);
    live_project.update(1.0);
    try expectPositionX(&live_project.scene.world, 4.0);
    try expectUnchanged(try live_project.pollLoadedSources(), "duplicate native build failure should be suppressed");

    try root_dir.writeFile(io, .{ .sub_path = native_path, .data = native_module_missing_register });
    try expectReloadFailure(&live_project, .native_load);
    live_project.update(1.0);
    try expectPositionX(&live_project.scene.world, 6.0);

    try root_dir.writeFile(io, .{ .sub_path = native_path, .data = native_module_registration_error });
    try expectReloadFailure(&live_project, .native_registration);
    live_project.update(1.0);
    try expectPositionX(&live_project.scene.world, 8.0);

    try writeNativeModule(io, root_dir, allocator, "3.00");
    const reload = try live_project.pollLoadedSources();
    try expect(reload.reloaded.native_reloaded, "valid native source did not reload native program\n", .{});
    try expect(live_project.lastDiagnostic() == null, "successful native reload left a stale diagnostic\n", .{});
    live_project.update(1.0);
    try expectPositionX(&live_project.scene.world, 14.0);
}

fn initLiveProject(io: Io, allocator: std.mem.Allocator) !machina.LiveProject {
    return machina.LiveProject.init(io, allocator, root_path) catch |err| {
        try printCheckDiagnostic(io, allocator);
        return err;
    };
}

fn printCheckDiagnostic(io: Io, allocator: std.mem.Allocator) !void {
    var result = try machina.checkProjectDetailed(io, allocator, root_path);
    switch (result) {
        .ok => |ok| machina.freeCheckResult(allocator, ok),
        .invalid => |*diagnostic| {
            defer diagnostic.deinit(allocator);
            std.debug.print("initial project check failed: {s}", .{@tagName(diagnostic.stage)});
            if (diagnostic.path) |path| {
                std.debug.print(" {s}", .{path});
            }
            std.debug.print(": {s}\n", .{diagnostic.message});
        },
    }
}

fn writeScene(io: Io, root_dir: Io.Dir) !void {
    try root_dir.writeFile(io, .{
        .sub_path = machina.default_scene_path,
        .data =
        \\name = "Main"
        \\version = 1
        \\
        \\[[entities]]
        \\id = "native-mover"
        \\name = "Native Mover"
        \\
        \\[entities.components."machina.transform"]
        \\position = [0.0, 0.0, 0.0]
        \\rotation = [0.0, 0.0, 0.0]
        \\scale = [1.0, 1.0, 1.0]
        \\
        \\[entities.components.native_tick]
        \\speed = 2.0
        \\
        ,
    });
}

fn writeNativeModule(io: Io, root_dir: Io.Dir, allocator: std.mem.Allocator, multiplier: []const u8) !void {
    const source = try std.mem.concat(allocator, u8, &.{ native_module_prefix, " ", multiplier, native_module_suffix });
    defer allocator.free(source);
    try root_dir.writeFile(io, .{ .sub_path = native_path, .data = source });
}

fn expectReloadFailure(live_project: *machina.LiveProject, expected_stage: machina.ScriptDiagnosticStage) !void {
    const result = live_project.pollLoadedSources();
    if (result) |_| {
        std.debug.print("native reload unexpectedly succeeded for {s}\n", .{@tagName(expected_stage)});
        return CheckError.CheckFailed;
    } else |err| {
        if (err != machina.ProjectError.InvalidScript) {
            return err;
        }
    }
    const diagnostic = live_project.lastDiagnostic() orelse {
        std.debug.print("native reload failure did not store a diagnostic for {s}\n", .{@tagName(expected_stage)});
        return CheckError.CheckFailed;
    };
    try expect(diagnostic.stage == expected_stage, "expected diagnostic stage {s}, got {s}\n", .{ @tagName(expected_stage), @tagName(diagnostic.stage) });
    try expectEqualStrings(native_path, diagnostic.path orelse "", "diagnostic path");
    try expect(diagnostic.message.len > 0, "diagnostic message was empty for {s}\n", .{@tagName(expected_stage)});
    try expect(live_project.scripts.registry.findComponent("native_tick") != null, "native_tick component missing after failed reload\n", .{});
    try expectEqualUsize(1, live_project.scripts.schedule.systemCount(), "native system count after failed reload");
}

fn expectUnchanged(result: machina.ReloadResult, label: []const u8) !void {
    switch (result) {
        .unchanged => {},
        .reloaded => {
            std.debug.print("{s}: expected unchanged reload result\n", .{label});
            return CheckError.CheckFailed;
        },
    }
}

fn expectPositionX(world: *machina.World, expected: f32) !void {
    const mover = world.findEntityById(mover_id) orelse {
        std.debug.print("missing entity '{s}'\n", .{mover_id});
        return CheckError.CheckFailed;
    };
    const transform = (try world.getTransform(mover)) orelse {
        std.debug.print("entity '{s}' has no transform\n", .{mover_id});
        return CheckError.CheckFailed;
    };
    if (@abs(transform.position[0] - expected) > 0.001) {
        std.debug.print("expected position.x ~= {d}, got {d}\n", .{ expected, transform.position[0] });
        return CheckError.CheckFailed;
    }
}

fn expectEqualUsize(expected: usize, actual: usize, label: []const u8) !void {
    if (actual != expected) {
        std.debug.print("{s}: expected {d}, got {d}\n", .{ label, expected, actual });
        return CheckError.CheckFailed;
    }
}

fn expectEqualStrings(expected: []const u8, actual: []const u8, label: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("{s}: expected '{s}', got '{s}'\n", .{ label, expected, actual });
        return CheckError.CheckFailed;
    }
}

fn expect(condition: bool, comptime format: []const u8, args: anytype) !void {
    if (!condition) {
        std.debug.print(format, args);
        return CheckError.CheckFailed;
    }
}

const native_module_prefix =
    \\const machina = @import("machina_native");
    \\
    \\const tick_fields = [_]machina.ComponentField{
    \\    .{ .name = "speed", .field_type = .float },
    \\};
    \\
    \\const tick_reads = [_][*:0]const u8{"native_tick"};
    \\const tick_writes = [_][*:0]const u8{"machina.transform"};
    \\
    \\export fn machina_register(api: *const machina.RegisterApi) callconv(.c) c_int {
    \\    machina.registerComponent(api, .{
    \\        .id = "native_tick",
    \\        .fields = tick_fields[0..],
    \\    }) catch return 0;
    \\
    \\    machina.registerSystem(api, .{
    \\        .id = "native_tick_move",
    \\        .phase = .update,
    \\        .reads = tick_reads[0..],
    \\        .writes = tick_writes[0..],
    \\        .run = nativeTickMove,
    \\    }) catch return 0;
    \\
    \\    return 1;
    \\}
    \\
    \\fn nativeTickMove(context: *machina.SystemContext) callconv(.c) c_int {
    \\    const query = [_][*:0]const u8{ "machina.transform", "native_tick" };
    \\    var cursor: usize = 0;
    \\    while (machina.queryNext(context, query[0..], &cursor) catch return 0) |entity| {
    \\        const position = machina.getVec3(context, entity, "machina.transform", "position") catch return 0;
    \\        const speed = machina.getF32(context, entity, "native_tick", "speed") catch return 0;
    \\        machina.setVec3(context, entity, "machina.transform", "position", .{
    \\            .x = position.x + speed * context.delta_seconds *
;

const native_module_suffix =
    \\,
    \\            .y = position.y,
    \\            .z = position.z,
    \\        }) catch return 0;
    \\    }
    \\    return 1;
    \\}
;

const native_module_build_error =
    \\const machina = @import("machina_native");
    \\
    \\export fn machina_register(api: *const machina.RegisterApi) callconv(.c) c_int {
    \\    _ = api;
    \\    return does_not_compile;
    \\}
;

const native_module_missing_register =
    \\export fn not_machina_register() callconv(.c) c_int {
    \\    return 1;
    \\}
;

const native_module_registration_error =
    \\const machina = @import("machina_native");
    \\
    \\const partial_fields = [_]machina.ComponentField{
    \\    .{ .name = "value", .field_type = .float },
    \\};
    \\const partial_reads = [_][*:0]const u8{"partial_component"};
    \\
    \\export fn machina_register(api: *const machina.RegisterApi) callconv(.c) c_int {
    \\    machina.registerComponent(api, .{
    \\        .id = "partial_component",
    \\        .fields = partial_fields[0..],
    \\    }) catch return 0;
    \\    machina.registerSystem(api, .{
    \\        .id = "partial_system",
    \\        .phase = .update,
    \\        .reads = partial_reads[0..],
    \\        .run = partialSystem,
    \\    }) catch return 0;
    \\    return 0;
    \\}
    \\
    \\fn partialSystem(context: *machina.SystemContext) callconv(.c) c_int {
    \\    _ = context;
    \\    return 1;
    \\}
;
