const std = @import("std");
const Io = std.Io;
const machina = @import("machina");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const exit_code = try run(init.io, allocator, args, stdout, stderr);

    try stdout.flush();
    try stderr.flush();

    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}

fn run(
    io: Io,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    if (args.len <= 1) {
        try printHelp(stdout);
        return 0;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "version")) {
        try stdout.print("machina {s}\n", .{machina.version});
        return 0;
    }

    if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "help")) {
        try printHelp(stdout);
        return 0;
    }

    if (std.mem.eql(u8, command, "init")) {
        const target_path = if (args.len >= 3) args[2] else ".";
        const name = projectNameFromPath(target_path);
        machina.initProject(io, allocator, target_path, name) catch |err| {
            try printProjectError(stderr, target_path, err);
            return 1;
        };
        try stdout.print("Initialized Machina project at {s}\n", .{target_path});
        return 0;
    }

    if (std.mem.eql(u8, command, "check")) {
        const target_path = if (args.len >= 3) args[2] else ".";
        const result = machina.checkProject(io, allocator, target_path) catch |err| {
            try printProjectError(stderr, target_path, err);
            return 1;
        };
        defer machina.freeProject(allocator, result.project);
        try stdout.print("Project OK: {s}\n", .{result.project.name});
        try stdout.print("Default scene: {s}\n", .{result.project.default_scene});
        return 0;
    }

    if (std.mem.eql(u8, command, "run")) {
        const target_path = if (args.len >= 3) args[2] else ".";
        const window_options = parseWindowOptions(args[3..]) catch |err| {
            try printArgumentError(stderr, err);
            return 1;
        };
        const result = machina.checkProject(io, allocator, target_path) catch |err| {
            try printProjectError(stderr, target_path, err);
            return 1;
        };
        defer machina.freeProject(allocator, result.project);
        try stdout.print("Loaded project {s}\n", .{result.project.name});
        try stdout.print("Selected scene: {s}\n", .{result.project.default_scene});

        machina.runDemoWindow(allocator, result.project.name, window_options) catch |err| {
            try stderr.print("run failed: {s}\n", .{@errorName(err)});
            return 1;
        };
        return 0;
    }

    if (std.mem.eql(u8, command, "render")) {
        const target_path = if (args.len >= 3) args[2] else ".";
        const output_path = if (args.len >= 4) args[3] else "zig-out/machina-cube.bmp";
        const result = machina.checkProject(io, allocator, target_path) catch |err| {
            try printProjectError(stderr, target_path, err);
            return 1;
        };
        defer machina.freeProject(allocator, result.project);

        machina.renderDemoBmp(io, allocator, output_path) catch |err| {
            try stderr.print("render failed: {s}\n", .{@errorName(err)});
            return 1;
        };

        try stdout.print("Rendered cube: {s}\n", .{output_path});
        return 0;
    }

    try stderr.print("Unknown command: {s}\n\n", .{command});
    try printHelp(stderr);
    return 1;
}

fn printHelp(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\machina - agent-native game engine
        \\
        \\Usage:
        \\  machina --version
        \\  machina help
        \\  machina init [path]
        \\  machina check [path]
        \\  machina run [path] [--frames N]
        \\  machina render [path] [output.bmp]
        \\
    );
}

const ArgumentError = error{
    InvalidFrames,
    UnknownArgument,
};

fn parseWindowOptions(args: []const []const u8) ArgumentError!machina.WindowOptions {
    var options = machina.WindowOptions{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--frames")) {
            index += 1;
            if (index >= args.len) {
                return ArgumentError.InvalidFrames;
            }
            options.max_frames = std.fmt.parseInt(u32, args[index], 10) catch return ArgumentError.InvalidFrames;
            if (options.max_frames.? == 0) {
                return ArgumentError.InvalidFrames;
            }
            continue;
        }

        return ArgumentError.UnknownArgument;
    }

    return options;
}

fn printArgumentError(writer: *Io.Writer, err: ArgumentError) !void {
    const message = switch (err) {
        ArgumentError.InvalidFrames => "--frames expects a positive integer",
        ArgumentError.UnknownArgument => "unknown run argument",
    };
    try writer.print("{s}\n", .{message});
}

fn printProjectError(writer: *Io.Writer, root_path: []const u8, err: anyerror) !void {
    const message = switch (err) {
        machina.ProjectError.AlreadyExists => "project already exists",
        machina.ProjectError.InvalidProject => "not a valid Machina project",
        machina.ProjectError.MissingProjectFile => "missing project.machina.toml",
        machina.ProjectError.MissingDefaultScene => "missing default scene",
        machina.ProjectError.UnsupportedProjectVersion => "unsupported project version",
        machina.ProjectError.InvalidProjectName => "invalid project name",
        machina.ProjectError.InvalidDefaultScene => "invalid default scene",
        else => "unexpected project error",
    };
    try writer.print("{s}: {s}\n", .{ root_path, message });
}

fn projectNameFromPath(path: []const u8) []const u8 {
    const trimmed = trimTrailingSlashes(path);
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, ".")) {
        return "Machina Project";
    }
    return std.fs.path.basename(trimmed);
}

fn trimTrailingSlashes(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and path[end - 1] == '/') {
        end -= 1;
    }
    return path[0..end];
}

test "projectNameFromPath uses final path segment" {
    try std.testing.expectEqualStrings("demo", projectNameFromPath("games/demo"));
    try std.testing.expectEqualStrings("demo", projectNameFromPath("games/demo/"));
    try std.testing.expectEqualStrings("Machina Project", projectNameFromPath("."));
}
