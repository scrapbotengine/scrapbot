const std = @import("std");
const Io = std.Io;

pub fn projectNameFromPath(path: []const u8) []const u8 {
    const trimmed = trimTrailingSlashes(path);
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, ".")) {
        return "Scrapbot Project";
    }
    return std.fs.path.basename(trimmed);
}

pub fn trimTrailingSlashes(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and path[end - 1] == '/') {
        end -= 1;
    }
    return path[0..end];
}

pub fn pathExists(io: Io, dir: Io.Dir, path: []const u8) bool {
    dir.access(io, path, .{}) catch return false;
    return true;
}

pub fn sameResolvedPath(allocator: std.mem.Allocator, left: []const u8, right: []const u8) !bool {
    const resolved_left = try std.fs.path.resolve(allocator, &.{left});
    defer allocator.free(resolved_left);
    const resolved_right = try std.fs.path.resolve(allocator, &.{right});
    defer allocator.free(resolved_right);
    return std.mem.eql(u8, resolved_left, resolved_right);
}
