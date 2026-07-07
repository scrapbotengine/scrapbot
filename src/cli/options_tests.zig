const std = @import("std");
const options = @import("options.zig");

const ArgumentError = options.ArgumentError;
const CheckOutputFormat = options.CheckOutputFormat;

test "parseInitOptions defaults to current directory" {
    const parsed = try options.parseInitOptions(std.testing.allocator, &.{});
    try std.testing.expectEqualStrings(".", parsed.target_path);
}

test "parseInitOptions accepts one target path" {
    const args = [_][]const u8{"games/demo"};
    const parsed = try options.parseInitOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("games/demo", parsed.target_path);
}

test "parseInitOptions rejects extra arguments" {
    const args = [_][]const u8{ "games/demo", "extra" };
    try std.testing.expectError(ArgumentError.UnknownArgument, options.parseInitOptions(std.testing.allocator, &args));
}

test "parseWindowOptions accepts frames, editor, and hidden flags" {
    const args = [_][]const u8{ "--frames", "12", "--editor", "--hidden" };
    const parsed = try options.parseWindowOptions(std.testing.allocator, &args);
    try std.testing.expectEqual(@as(u32, 12), parsed.max_frames.?);
    try std.testing.expect(parsed.editor);
    try std.testing.expect(parsed.hidden);
}

test "parseWindowOptions rejects hidden run without frame limit" {
    const args = [_][]const u8{"--hidden"};
    try std.testing.expectError(ArgumentError.HiddenRequiresFrames, options.parseWindowOptions(std.testing.allocator, &args));
}

test "parseRenderOptions accepts editor flag before path" {
    const args = [_][]const u8{ "--editor", "examples/spawn_swarm", "zig-out/spawn-editor.png" };
    const parsed = try options.parseRenderOptions(std.testing.allocator, &args, "zig-out/default.png");
    try std.testing.expect(parsed.editor);
    try std.testing.expectEqualStrings("examples/spawn_swarm", parsed.target_path);
    try std.testing.expectEqualStrings("zig-out/spawn-editor.png", parsed.output_path);
}

test "parseRenderOptions accepts editor flag after output" {
    const args = [_][]const u8{ "examples/spawn_swarm", "zig-out/spawn-editor.png", "--editor" };
    const parsed = try options.parseRenderOptions(std.testing.allocator, &args, "zig-out/default.png");
    try std.testing.expect(parsed.editor);
    try std.testing.expectEqualStrings("examples/spawn_swarm", parsed.target_path);
    try std.testing.expectEqualStrings("zig-out/spawn-editor.png", parsed.output_path);
}

test "parseRenderOptions accepts selected entity" {
    const args = [_][]const u8{ "examples/spawn_swarm", "zig-out/spawn-editor.png", "--select", "swarm.0" };
    const parsed = try options.parseRenderOptions(std.testing.allocator, &args, "zig-out/default.png");
    try std.testing.expect(parsed.editor);
    try std.testing.expectEqualStrings("examples/spawn_swarm", parsed.target_path);
    try std.testing.expectEqualStrings("zig-out/spawn-editor.png", parsed.output_path);
    try std.testing.expectEqualStrings("swarm.0", parsed.selected_entity_id.?);
}

test "parseRenderOptions accepts frame count" {
    const args = [_][]const u8{ "--frames=60", "examples/ui_gallery", "zig-out/ui-gallery.png" };
    const parsed = try options.parseRenderOptions(std.testing.allocator, &args, "zig-out/default.png");
    try std.testing.expectEqual(@as(u32, 60), parsed.frames);
    try std.testing.expectEqualStrings("examples/ui_gallery", parsed.target_path);
    try std.testing.expectEqualStrings("zig-out/ui-gallery.png", parsed.output_path);
}

test "parseRenderOptions accepts explicit bmp output" {
    const args = [_][]const u8{ "examples/minimal", "zig-out/minimal-render-test.bmp" };
    const parsed = try options.parseRenderOptions(std.testing.allocator, &args, "zig-out/default.png");
    try std.testing.expectEqualStrings("examples/minimal", parsed.target_path);
    try std.testing.expectEqualStrings("zig-out/minimal-render-test.bmp", parsed.output_path);
}

test "parseRenderOptions accepts render dimensions" {
    const args = [_][]const u8{ "--width", "1400", "--height=1000", "examples/spawn_swarm", "zig-out/spawn-editor.png" };
    const parsed = try options.parseRenderOptions(std.testing.allocator, &args, "zig-out/default.bmp");
    try std.testing.expectEqual(@as(u32, 1400), parsed.width);
    try std.testing.expectEqual(@as(u32, 1000), parsed.height);
    try std.testing.expectEqualStrings("examples/spawn_swarm", parsed.target_path);
    try std.testing.expectEqualStrings("zig-out/spawn-editor.png", parsed.output_path);
}

test "parseRenderOptions accepts pixel scale" {
    const args = [_][]const u8{ "--width=1280", "--height=900", "--pixel-scale=2", "examples/minimal" };
    const parsed = try options.parseRenderOptions(std.testing.allocator, &args, "zig-out/default.png");
    try std.testing.expectEqual(@as(u32, 1280), parsed.width);
    try std.testing.expectEqual(@as(u32, 900), parsed.height);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), parsed.pixel_scale, 0.000001);
}

test "parseRenderOptions rejects zero render dimension" {
    const args = [_][]const u8{ "--width=0", "examples/minimal" };
    try std.testing.expectError(ArgumentError.InvalidRenderSize, options.parseRenderOptions(std.testing.allocator, &args, "zig-out/default.bmp"));
}

test "parseRenderOptions rejects invalid pixel scale" {
    const args = [_][]const u8{ "--pixel-scale=0", "examples/minimal" };
    try std.testing.expectError(ArgumentError.InvalidPixelScale, options.parseRenderOptions(std.testing.allocator, &args, "zig-out/default.png"));
}

test "parseRenderOptions rejects extra positionals" {
    const args = [_][]const u8{ "examples/minimal", "one.bmp", "two.bmp" };
    try std.testing.expectError(ArgumentError.UnknownArgument, options.parseRenderOptions(std.testing.allocator, &args, "zig-out/default.png"));
}

test "parseVisualTestOptions accepts expected and actual paths" {
    const args = [_][]const u8{ "--frames=4", "tests/golden/postprocess_effects", "tests/golden/postprocess_effects/expected.png", "zig-out/postprocess-actual.png" };
    const parsed = try options.parseVisualTestOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("tests/golden/postprocess_effects", parsed.render.target_path);
    try std.testing.expectEqualStrings("tests/golden/postprocess_effects/expected.png", parsed.expected_path);
    try std.testing.expectEqualStrings("zig-out/postprocess-actual.png", parsed.render.output_path);
    try std.testing.expectEqual(@as(u32, 4), parsed.render.frames);
    try std.testing.expect(!parsed.update);
}

test "parseVisualTestOptions supports update selected entity and pixel scale" {
    const args = [_][]const u8{ "--update", "--select", "cube-1", "--width=1280", "--height", "720", "--pixel-scale", "2", "tests/golden/basic", "tests/golden/basic/expected.png" };
    const parsed = try options.parseVisualTestOptions(std.testing.allocator, &args);
    try std.testing.expect(parsed.update);
    try std.testing.expect(parsed.render.editor);
    try std.testing.expectEqualStrings("cube-1", parsed.render.selected_entity_id.?);
    try std.testing.expectEqual(@as(u32, 1280), parsed.render.width);
    try std.testing.expectEqual(@as(u32, 720), parsed.render.height);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), parsed.render.pixel_scale, 0.000001);
    try std.testing.expectEqualStrings("zig-out/scrapbot-visual-test.png", parsed.render.output_path);
}

test "parseVisualTestOptions requires expected path" {
    const args = [_][]const u8{"tests/golden/basic"};
    try std.testing.expectError(ArgumentError.MissingExpected, options.parseVisualTestOptions(std.testing.allocator, &args));
}

test "parseCheckOptions accepts path and json format" {
    const args = [_][]const u8{ "examples/minimal", "--format=json" };
    const parsed = try options.parseCheckOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("examples/minimal", parsed.target_path);
    try std.testing.expectEqual(CheckOutputFormat.json, parsed.format);
}

test "parseCheckOptions accepts format before path" {
    const args = [_][]const u8{ "--format", "json", "examples/minimal" };
    const parsed = try options.parseCheckOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("examples/minimal", parsed.target_path);
    try std.testing.expectEqual(CheckOutputFormat.json, parsed.format);
}

test "parseCheckOptions rejects unknown format" {
    const args = [_][]const u8{"--format=yaml"};
    try std.testing.expectError(ArgumentError.InvalidFormat, options.parseCheckOptions(std.testing.allocator, &args));
}

test "parseStepOptions accepts path frames dt and json format" {
    const args = [_][]const u8{ "examples/minimal", "--frames=60", "--dt", "0.016", "--format=json" };
    const parsed = try options.parseStepOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("examples/minimal", parsed.target_path);
    try std.testing.expectEqual(@as(u32, 60), parsed.frames);
    try std.testing.expectApproxEqAbs(@as(f32, 0.016), parsed.delta_seconds, 0.000001);
    try std.testing.expectEqual(CheckOutputFormat.json, parsed.format);
}

test "parseStepOptions rejects invalid dt" {
    const args = [_][]const u8{ "--dt", "inf" };
    try std.testing.expectError(ArgumentError.InvalidDelta, options.parseStepOptions(std.testing.allocator, &args));
}

test "parseBenchOptions accepts path frames dt and json format" {
    const args = [_][]const u8{ "examples/spawn_swarm", "--frames=120", "--dt", "0.016", "--format=json" };
    const parsed = try options.parseBenchOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("examples/spawn_swarm", parsed.target_path);
    try std.testing.expectEqual(@as(u32, 120), parsed.frames);
    try std.testing.expectApproxEqAbs(@as(f32, 0.016), parsed.delta_seconds, 0.000001);
    try std.testing.expectEqual(CheckOutputFormat.json, parsed.format);
}

test "parseRenderBenchOptions accepts editor frames warmup dimensions dt and json format" {
    const args = [_][]const u8{ "examples/spawn_swarm", "--editor", "--select", "cube-1", "--frames=120", "--warmup=20", "--dt", "0.016", "--width", "1280", "--height", "720", "--pixel-scale", "2", "--format=json" };
    const parsed = try options.parseRenderBenchOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("examples/spawn_swarm", parsed.target_path);
    try std.testing.expect(parsed.editor);
    try std.testing.expectEqualStrings("cube-1", parsed.selected_entity_id.?);
    try std.testing.expectEqual(@as(u32, 120), parsed.frames);
    try std.testing.expectEqual(@as(u32, 20), parsed.warmup_frames);
    try std.testing.expectApproxEqAbs(@as(f32, 0.016), parsed.delta_seconds, 0.000001);
    try std.testing.expectEqual(@as(u32, 1280), parsed.width);
    try std.testing.expectEqual(@as(u32, 720), parsed.height);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), parsed.pixel_scale, 0.000001);
    try std.testing.expectEqual(CheckOutputFormat.json, parsed.format);
}

test "parseTestOptions defaults to tests/projects" {
    const parsed = try options.parseTestOptions(std.testing.allocator, &.{});
    try std.testing.expectEqualStrings("tests/projects", parsed.target_path);
    try std.testing.expectEqual(CheckOutputFormat.text, parsed.format);
}

test "parseTestOptions accepts path and json format" {
    const args = [_][]const u8{ "tests/projects/health_tick", "--format=json" };
    const parsed = try options.parseTestOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("tests/projects/health_tick", parsed.target_path);
    try std.testing.expectEqual(CheckOutputFormat.json, parsed.format);
}

test "parseBuildOptions accepts path output name force and json format" {
    const args = [_][]const u8{ "examples/minimal", "--output=zig-out/packages", "--name", "minimal-demo", "--force", "--format=json" };
    const parsed = try options.parseBuildOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("examples/minimal", parsed.target_path);
    try std.testing.expectEqualStrings("zig-out/packages", parsed.output_root.?);
    try std.testing.expectEqualStrings("minimal-demo", parsed.name.?);
    try std.testing.expect(parsed.force);
    try std.testing.expectEqual(CheckOutputFormat.json, parsed.format);
}

test "parseBuildOptions defaults output root to project build directory" {
    const parsed = try options.parseBuildOptions(std.testing.allocator, &.{});
    try std.testing.expectEqualStrings(".", parsed.target_path);
    try std.testing.expect(parsed.output_root == null);
}

test "parseBuildOptions rejects extra positionals" {
    const args = [_][]const u8{ "examples/minimal", "extra" };
    try std.testing.expectError(ArgumentError.UnknownArgument, options.parseBuildOptions(std.testing.allocator, &args));
}
