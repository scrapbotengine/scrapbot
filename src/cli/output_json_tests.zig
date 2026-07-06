const std = @import("std");
const Io = std.Io;
const output_json = @import("output_json.zig");
const scrapbot = @import("scrapbot");
const test_manifest = @import("test_manifest.zig");

const TestSuiteSummary = test_manifest.TestSuiteSummary;

test "writeJsonString uses std json escaping" {
    var buffer: [128]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);

    try output_json.writeJsonString(&writer, "quote\" slash\\ line\n tab\t");

    try std.testing.expectEqualStrings(
        "\"quote\\\" slash\\\\ line\\n tab\\t\"",
        writer.buffered(),
    );
}

test "field value json preserves compact float formatting" {
    var buffer: [128]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);

    try output_json.printExpectedFieldValueJson(&writer, .{ .vec3 = .{ 0.016666668, 1.5, -2.0 } });

    try std.testing.expectEqualStrings("[0.016666668,1.5,-2]", writer.buffered());
}

test "test discovery errors are emitted through the json output module" {
    var buffer: [256]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);

    try output_json.printTestDiscoveryFailureJson(&writer, "tests/projects", error.AccessDenied);

    try std.testing.expectEqualStrings(
        "{\"ok\":false,\"error\":\"AccessDenied\",\"root\":\"tests/projects\"}\n",
        writer.buffered(),
    );
}

test "test suite envelope json remains streamable" {
    var buffer: [256]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);
    const summary = TestSuiteSummary{
        .cases = 2,
        .passed_cases = 1,
        .failed_cases = 1,
        .assertions = 3,
        .failed_assertions = 1,
    };

    try output_json.printTestSuiteStartJson(&writer);
    try writer.writeAll("{\"name\":\"first\"}");
    try output_json.printTestSuiteSeparatorJson(&writer);
    try writer.writeAll("{\"name\":\"second\"}");
    try output_json.printTestSuiteEndJson(&writer, summary);

    try std.testing.expectEqualStrings(
        "{\"tests\":[{\"name\":\"first\"},{\"name\":\"second\"}],\"summary\":{\"cases\":2,\"passed\":1,\"failed\":1,\"assertions\":3,\"failed_assertions\":1},\"ok\":false}\n",
        writer.buffered(),
    );
}

test "printCheckOkJson includes schedule summary" {
    var buffer: [1024]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);

    const scripts = [_][]const u8{"scripts/gameplay.luau"};
    const reads = [_][]const u8{"spin"};
    const writes = [_][]const u8{"scrapbot.transform"};
    const system = scrapbot.CheckSystemSummary{
        .id = "autorotate",
        .phase = .update,
        .runner = .luau,
        .reads = &reads,
        .writes = &writes,
    };
    const systems = [_]scrapbot.CheckSystemSummary{system};
    const batch = scrapbot.CheckScheduleBatch{
        .phase = .update,
        .systems = &systems,
    };
    const batches = [_]scrapbot.CheckScheduleBatch{batch};
    const result = scrapbot.CheckResult{
        .project = .{
            .root_path = "examples/minimal",
            .name = "Minimal",
            .default_scene = "scenes/main.scene.toml",
            .scripts = &scripts,
        },
        .schedule = .{ .batches = &batches },
    };

    try output_json.printCheckOkJson(&writer, result);

    try std.testing.expectEqualStrings(
        "{\"ok\":true,\"project\":{\"name\":\"Minimal\",\"default_scene\":\"scenes/main.scene.toml\",\"scripts\":1},\"schedule\":{\"batches\":[{\"phase\":\"update\",\"systems\":[{\"id\":\"autorotate\",\"phase\":\"update\",\"runner\":\"luau\",\"reads\":[\"spin\"],\"writes\":[\"scrapbot.transform\"],\"before\":[],\"after\":[]}]}]}}\n",
        writer.buffered(),
    );
}

test "printStepOkJson includes simulation and scene summary" {
    var output_buffer: [1536]u8 = undefined;
    var writer = Io.Writer.fixed(&output_buffer);

    var scene = scrapbot.Scene{
        .name = "Main",
        .world = scrapbot.World.init(std.testing.allocator),
    };
    defer scene.world.deinit();
    const entity = try scene.world.createEntity("entity-1", "Entity");
    try scene.world.setTransform(entity, .{});
    try scene.world.setSpin(entity, .{ .angular_velocity = .{ 1.0, 0.0, 0.0 } });

    const scripts = [_][]const u8{"scripts/gameplay.luau"};
    const reads = [_][]const u8{"spin"};
    const writes = [_][]const u8{"scrapbot.transform"};
    const system = scrapbot.CheckSystemSummary{
        .id = "autorotate",
        .phase = .update,
        .runner = .luau,
        .reads = &reads,
        .writes = &writes,
    };
    const systems = [_]scrapbot.CheckSystemSummary{system};
    const batch = scrapbot.CheckScheduleBatch{
        .phase = .update,
        .systems = &systems,
    };
    const batches = [_]scrapbot.CheckScheduleBatch{batch};
    const ok = scrapbot.StepOk{
        .project = .{
            .root_path = "examples/minimal",
            .name = "Minimal",
            .default_scene = "scenes/main.scene.toml",
            .scripts = &scripts,
        },
        .scene = scene,
        .schedule = .{ .batches = &batches },
        .summary = .{
            .frames = 2,
            .completed_frames = 2,
            .delta_seconds = 0.5,
        },
    };

    try output_json.printStepOkJson(&writer, ok);

    try std.testing.expectEqualStrings(
        "{\"ok\":true,\"project\":{\"name\":\"Minimal\",\"default_scene\":\"scenes/main.scene.toml\",\"scripts\":1},\"scene\":{\"name\":\"Main\",\"entities\":1,\"component_instances\":2,\"renderable_cubes\":0},\"simulation\":{\"frames\":2,\"completed_frames\":2,\"dt\":0.5},\"schedule\":{\"batches\":[{\"phase\":\"update\",\"systems\":[{\"id\":\"autorotate\",\"phase\":\"update\",\"runner\":\"luau\",\"reads\":[\"spin\"],\"writes\":[\"scrapbot.transform\"],\"before\":[],\"after\":[]}]}]}}\n",
        writer.buffered(),
    );
}
