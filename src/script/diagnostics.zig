const std = @import("std");

pub const Stage = enum {
    load,
    native_build,
    native_load,
    native_registration,
    registration,
    schedule,
    runtime,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .load => "script load",
            .native_build => "native build",
            .native_load => "native load",
            .native_registration => "native registration",
            .registration => "script registration",
            .schedule => "script schedule",
            .runtime => "script runtime",
        };
    }
};

pub const Diagnostic = struct {
    stage: Stage,
    path: ?[]const u8 = null,
    system_id: ?[]const u8 = null,
    start: ?Position = null,
    end: ?Position = null,
    message: []const u8,

    pub fn deinit(self: *Diagnostic, allocator: std.mem.Allocator) void {
        if (self.path) |path| {
            allocator.free(path);
        }
        if (self.system_id) |system_id| {
            allocator.free(system_id);
        }
        allocator.free(self.message);
        self.* = undefined;
    }
};

pub const Position = struct {
    line: u32,
    column: ?u32 = null,
};
