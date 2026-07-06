const std = @import("std");
const test_manifest = @import("test_manifest.zig");

const TestManifestError = test_manifest.TestManifestError;

test "parseTestManifest reads field assertions" {
    var manifest = try test_manifest.parseTestManifest(std.testing.allocator,
        \\frames = 4
        \\dt = 1.0
        \\
        \\[[input.frame]]
        \\frame = 2
        \\debug_overlay_visible = true
        \\viewport = [1280.0, 720.0]
        \\pixel_scale = 2.0
        \\pointer = [36.0, 190.0]
        \\pointer_delta = [3.0, -2.0]
        \\secondary_down = true
        \\wheel_delta = [0.0, -1.0]
        \\move_forward = true
        \\move_up = true
        \\system_profile_count_hint = 9
        \\
        \\[[expect.field]]
        \\entity = "door-1"
        \\component = "door"
        \\field = "openness"
        \\equals_float = 1.0
        \\
        \\[[expect.field]]
        \\entity = "switch-1"
        \\component = "switch"
        \\field = "active"
        \\equals_bool = true
        \\
    );
    defer manifest.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 4), manifest.frames);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), manifest.delta_seconds, 0.000001);
    try std.testing.expectEqual(@as(usize, 1), manifest.input_frames.len);
    try std.testing.expectEqual(@as(u32, 2), manifest.input_frames[0].frame);
    try std.testing.expect(manifest.input_frames[0].input.debug_overlay_visible);
    try std.testing.expectApproxEqAbs(@as(f32, 1280.0), manifest.input_frames[0].input.viewport_width, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), manifest.input_frames[0].input.pixel_scale, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 36.0), manifest.input_frames[0].input.pointer.position[0], 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), manifest.input_frames[0].input.pointer.delta[0], 0.000001);
    try std.testing.expect(manifest.input_frames[0].input.pointer.secondary_down);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), manifest.input_frames[0].input.pointer.wheel_delta[1], 0.000001);
    try std.testing.expect(manifest.input_frames[0].input.keyboard.move_forward);
    try std.testing.expect(manifest.input_frames[0].input.keyboard.move_up);
    try std.testing.expectEqual(@as(usize, 9), manifest.input_frames[0].input.system_profile_count_hint);
    try std.testing.expectEqual(@as(usize, 2), manifest.expectations.len);
    try std.testing.expectEqualStrings("door-1", manifest.expectations[0].entity);
    try std.testing.expectEqualStrings("door", manifest.expectations[0].component);
    try std.testing.expectEqualStrings("openness", manifest.expectations[0].field);
    try std.testing.expect(manifest.expectations[0].expected.matches(.{ .float = 1.0 }));
    try std.testing.expect(manifest.expectations[1].expected.matches(.{ .boolean = true }));
}

test "parseTestManifest rejects duplicate input frames" {
    try std.testing.expectError(TestManifestError.InvalidTestManifest, test_manifest.parseTestManifest(std.testing.allocator,
        \\frames = 2
        \\
        \\[[input.frame]]
        \\frame = 1
        \\pointer = [1.0, 2.0]
        \\
        \\[[input.frame]]
        \\frame = 1
        \\pointer = [3.0, 4.0]
        \\
        \\[[expect.field]]
        \\entity = "scroll"
        \\component = "scrapbot.ui.scroll_view"
        \\field = "content_offset"
        \\equals_vec3 = [0.0, 0.0, 0.0]
        \\
    ));
}
