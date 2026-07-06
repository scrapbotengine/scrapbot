const std = @import("std");
const cli = @import("cli.zig");
const cli_path = @import("cli/path.zig");
const scrapbot = @import("scrapbot");

const Io = std.Io;

test "run init command creates a checkable project" {
    const root_path = ".zig-cache/test-cli-init-project";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    var stdout_buffer: [512]u8 = undefined;
    var stdout = Io.Writer.fixed(&stdout_buffer);
    var stderr_buffer: [512]u8 = undefined;
    var stderr = Io.Writer.fixed(&stderr_buffer);
    const args = [_][]const u8{ "scrapbot", "init", root_path };

    const exit_code = try cli.run(io, std.testing.allocator, &args, &stdout, &stderr);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expectEqualStrings("Initialized Scrapbot project at " ++ root_path ++ "\n", stdout.buffered());
    try std.testing.expectEqualStrings("", stderr.buffered());

    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try std.testing.expect(cli_path.pathExists(io, root_dir, scrapbot.project_file_name));
    try std.testing.expect(cli_path.pathExists(io, root_dir, "scenes/main.scene.toml"));
    try std.testing.expect(cli_path.pathExists(io, root_dir, "assets/.gitkeep"));
    try std.testing.expect(!cli_path.pathExists(io, root_dir, "native/game.zig"));

    const metadata = try root_dir.readFileAlloc(io, scrapbot.project_file_name, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(metadata);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "\n# native = \"native/game.zig\"\n") != null);

    const result = try scrapbot.checkProject(io, std.testing.allocator, root_path);
    defer scrapbot.freeCheckResult(std.testing.allocator, result);
    try std.testing.expectEqualStrings("test-cli-init-project", result.project.name);
}

test "run init command rejects extra arguments" {
    const root_path = ".zig-cache/test-cli-init-extra";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    var stdout_buffer: [512]u8 = undefined;
    var stdout = Io.Writer.fixed(&stdout_buffer);
    var stderr_buffer: [512]u8 = undefined;
    var stderr = Io.Writer.fixed(&stderr_buffer);
    const args = [_][]const u8{ "scrapbot", "init", root_path, "extra" };

    const exit_code = try cli.run(io, std.testing.allocator, &args, &stdout, &stderr);
    try std.testing.expectEqual(@as(u8, 1), exit_code);
    try std.testing.expectEqualStrings("", stdout.buffered());
    try std.testing.expectEqualStrings("unknown argument\n", stderr.buffered());
    try std.testing.expectError(scrapbot.ProjectError.InvalidProject, scrapbot.checkProject(io, std.testing.allocator, root_path));
}

test "run test command runs a gameplay project fixture" {
    var stdout_buffer: [8192]u8 = undefined;
    var stdout = Io.Writer.fixed(&stdout_buffer);
    var stderr_buffer: [2048]u8 = undefined;
    var stderr = Io.Writer.fixed(&stderr_buffer);
    const io = Io.Threaded.global_single_threaded.io();

    const args = [_][]const u8{ "scrapbot", "test", "tests/projects/health_tick" };
    const exit_code = try cli.run(io, std.testing.allocator, &args, &stdout, &stderr);

    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout.buffered(), "PASS health_tick") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout.buffered(), "Test projects: 1 passed, 0 failed") != null);
    try std.testing.expectEqualStrings("", stderr.buffered());
}
