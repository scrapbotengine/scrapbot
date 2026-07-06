const std = @import("std");
const path = @import("path.zig");

test "projectNameFromPath uses final path segment" {
    try std.testing.expectEqualStrings("demo", path.projectNameFromPath("games/demo"));
    try std.testing.expectEqualStrings("demo", path.projectNameFromPath("games/demo/"));
    try std.testing.expectEqualStrings("Scrapbot Project", path.projectNameFromPath("."));
}

test "sameResolvedPath detects equivalent relative paths" {
    try std.testing.expect(try path.sameResolvedPath(std.testing.allocator, "tests/golden/postprocess_effects/expected.png", "./tests/golden/postprocess_effects/expected.png"));
    try std.testing.expect(!try path.sameResolvedPath(std.testing.allocator, "tests/golden/postprocess_effects/expected.png", "zig-out/postprocess-effects-actual.png"));
}

test "renderArtifactMetadataPath appends sidecar suffix" {
    const metadata_path = try path.renderArtifactMetadataPath(std.testing.allocator, "zig-out/editor.png");
    defer std.testing.allocator.free(metadata_path);
    try std.testing.expectEqualStrings("zig-out/editor.png.metadata.json", metadata_path);
}
