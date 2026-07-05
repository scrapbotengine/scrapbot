const std = @import("std");
const cli = @import("cli.zig");

const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const arena_allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena_allocator);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const exit_code = if (leakCheckEnabled(init))
        try runLeakChecked(init.io, args, stdout, stderr)
    else
        try cli.run(init.io, arena_allocator, args, stdout, stderr);

    try stdout.flush();
    try stderr.flush();

    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}

fn leakCheckEnabled(init: std.process.Init) bool {
    const value = init.environ_map.get("SCRAPBOT_LEAK_CHECK") orelse return false;
    return std.mem.eql(u8, value, "1");
}

fn runLeakChecked(
    io: Io,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    var debug_allocator: std.heap.DebugAllocator(.{
        .safety = true,
        .stack_trace_frames = if (std.debug.sys_can_stack_trace) 8 else 0,
    }) = .init;
    const allocator = debug_allocator.allocator();
    const exit_code = try cli.run(io, allocator, args, stdout, stderr);
    switch (debug_allocator.deinit()) {
        .ok => return exit_code,
        .leak => {
            try stderr.writeAll("memory leak detected by SCRAPBOT_LEAK_CHECK\n");
            return 1;
        },
    }
}
