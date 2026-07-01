const std = @import("std");
const Io = std.Io;
const runtime = @import("runtime.zig");

pub const ScriptError = runtime.RegistryError || std.mem.Allocator.Error || error{
    InvalidScript,
    UnsupportedScript,
    UnknownFieldType,
    UnknownSystemPhase,
};

pub fn loadProjectRegistry(
    io: Io,
    allocator: std.mem.Allocator,
    root_dir: Io.Dir,
    script_paths: []const []const u8,
) !runtime.ComponentRegistry {
    var registry = runtime.ComponentRegistry.init(allocator);
    errdefer registry.deinit();

    try registerEngineTypes(&registry);

    for (script_paths) |script_path| {
        const contents = try root_dir.readFileAlloc(io, script_path, allocator, .limited(256 * 1024));
        defer allocator.free(contents);

        var parser = DeclarationParser{
            .allocator = allocator,
            .registry = &registry,
            .source = contents,
        };
        try parser.parse();
    }

    return registry;
}

pub fn buildUpdateSchedule(
    allocator: std.mem.Allocator,
    registry: runtime.ComponentRegistry,
) !runtime.SystemSchedule {
    return registry.buildSchedule(allocator, .update);
}

fn registerEngineTypes(registry: *runtime.ComponentRegistry) !void {
    const transform_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "position", .value_type = .float },
        .{ .name = "rotation", .value_type = .float },
        .{ .name = "scale", .value_type = .float },
    };
    try registry.registerEngineComponent(.{
        .id = "machina.transform",
        .version = 1,
        .fields = &transform_fields,
    });

    const cube_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "color", .value_type = .float },
    };
    try registry.registerEngineComponent(.{
        .id = "machina.render.cube",
        .version = 1,
        .fields = &cube_fields,
    });

    const spin_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "angular_velocity", .value_type = .float },
    };
    try registry.registerEngineComponent(.{
        .id = "machina.spin",
        .version = 1,
        .fields = &spin_fields,
    });
}

const DeclarationParser = struct {
    allocator: std.mem.Allocator,
    registry: *runtime.ComponentRegistry,
    source: []const u8,
    index: usize = 0,

    fn parse(self: *DeclarationParser) ScriptError!void {
        while (true) {
            self.skipTrivia();
            if (self.isEof()) {
                return;
            }
            try self.parseDeclaration();
        }
    }

    fn parseDeclaration(self: *DeclarationParser) ScriptError!void {
        try self.expectLiteral("ecs.");
        const declaration = try self.parseIdentifier();
        try self.expectByte('(');
        const id = try self.parseString();
        try self.expectByte(',');

        if (std.mem.eql(u8, declaration, "component")) {
            try self.parseComponent(id);
        } else if (std.mem.eql(u8, declaration, "system")) {
            try self.parseSystem(id);
        } else {
            return ScriptError.UnsupportedScript;
        }

        try self.expectByte(')');
        _ = self.consumeByte(';');
    }

    fn parseComponent(self: *DeclarationParser, id: []const u8) ScriptError!void {
        var version: u32 = 1;
        var fields: std.ArrayList(runtime.ComponentFieldDefinition) = .empty;
        defer fields.deinit(self.allocator);

        try self.expectByte('{');
        while (true) {
            self.skipTrivia();
            if (self.consumeByte('}')) {
                break;
            }

            const key = try self.parseIdentifier();
            try self.expectByte('=');

            if (std.mem.eql(u8, key, "version")) {
                version = try self.parseU32();
            } else if (std.mem.eql(u8, key, "fields")) {
                try self.parseFieldTable(&fields);
            } else {
                return ScriptError.UnsupportedScript;
            }

            try self.consumeSeparatorOrEnd();
        }

        try self.registry.registerProjectComponent(.{
            .id = id,
            .version = version,
            .fields = fields.items,
        });
    }

    fn parseSystem(self: *DeclarationParser, id: []const u8) ScriptError!void {
        var phase: runtime.SystemPhase = .update;
        var reads: std.ArrayList([]const u8) = .empty;
        var writes: std.ArrayList([]const u8) = .empty;
        var before: std.ArrayList([]const u8) = .empty;
        var after: std.ArrayList([]const u8) = .empty;
        defer reads.deinit(self.allocator);
        defer writes.deinit(self.allocator);
        defer before.deinit(self.allocator);
        defer after.deinit(self.allocator);

        try self.expectByte('{');
        while (true) {
            self.skipTrivia();
            if (self.consumeByte('}')) {
                break;
            }

            const key = try self.parseIdentifier();
            try self.expectByte('=');

            if (std.mem.eql(u8, key, "phase")) {
                phase = try parseSystemPhase(try self.parseString());
            } else if (std.mem.eql(u8, key, "reads")) {
                try self.parseStringList(&reads);
            } else if (std.mem.eql(u8, key, "writes")) {
                try self.parseStringList(&writes);
            } else if (std.mem.eql(u8, key, "before")) {
                try self.parseStringList(&before);
            } else if (std.mem.eql(u8, key, "after")) {
                try self.parseStringList(&after);
            } else if (std.mem.eql(u8, key, "run")) {
                return ScriptError.UnsupportedScript;
            } else {
                return ScriptError.UnsupportedScript;
            }

            try self.consumeSeparatorOrEnd();
        }

        try self.registry.registerProjectSystem(.{
            .id = id,
            .phase = phase,
            .reads = reads.items,
            .writes = writes.items,
            .before = before.items,
            .after = after.items,
        });
    }

    fn parseFieldTable(
        self: *DeclarationParser,
        fields: *std.ArrayList(runtime.ComponentFieldDefinition),
    ) ScriptError!void {
        try self.expectByte('{');
        while (true) {
            self.skipTrivia();
            if (self.consumeByte('}')) {
                return;
            }

            const field_name = try self.parseIdentifier();
            try self.expectByte('=');
            const field_type = try parseFieldType(try self.parseString());
            try fields.append(self.allocator, .{
                .name = field_name,
                .value_type = field_type,
            });
            try self.consumeSeparatorOrEnd();
        }
    }

    fn parseStringList(self: *DeclarationParser, values: *std.ArrayList([]const u8)) ScriptError!void {
        try self.expectByte('{');
        while (true) {
            self.skipTrivia();
            if (self.consumeByte('}')) {
                return;
            }

            try values.append(self.allocator, try self.parseString());
            try self.consumeSeparatorOrEnd();
        }
    }

    fn parseIdentifier(self: *DeclarationParser) ScriptError![]const u8 {
        self.skipTrivia();
        if (self.isEof() or !isIdentifierStart(self.source[self.index])) {
            return ScriptError.InvalidScript;
        }

        const start = self.index;
        self.index += 1;
        while (!self.isEof() and isIdentifierContinue(self.source[self.index])) {
            self.index += 1;
        }
        return self.source[start..self.index];
    }

    fn parseString(self: *DeclarationParser) ScriptError![]const u8 {
        self.skipTrivia();
        if (self.isEof() or self.source[self.index] != '"') {
            return ScriptError.InvalidScript;
        }
        self.index += 1;
        const start = self.index;
        while (!self.isEof() and self.source[self.index] != '"') : (self.index += 1) {
            if (self.source[self.index] == '\\') {
                return ScriptError.UnsupportedScript;
            }
        }
        if (self.isEof()) {
            return ScriptError.InvalidScript;
        }
        const value = self.source[start..self.index];
        self.index += 1;
        return value;
    }

    fn parseU32(self: *DeclarationParser) ScriptError!u32 {
        self.skipTrivia();
        const start = self.index;
        while (!self.isEof() and std.ascii.isDigit(self.source[self.index])) {
            self.index += 1;
        }
        if (start == self.index) {
            return ScriptError.InvalidScript;
        }
        return std.fmt.parseInt(u32, self.source[start..self.index], 10) catch ScriptError.InvalidScript;
    }

    fn expectLiteral(self: *DeclarationParser, literal: []const u8) ScriptError!void {
        self.skipTrivia();
        if (!std.mem.startsWith(u8, self.source[self.index..], literal)) {
            return ScriptError.InvalidScript;
        }
        self.index += literal.len;
    }

    fn expectByte(self: *DeclarationParser, byte: u8) ScriptError!void {
        self.skipTrivia();
        if (!self.consumeByte(byte)) {
            return ScriptError.InvalidScript;
        }
    }

    fn consumeByte(self: *DeclarationParser, byte: u8) bool {
        self.skipTrivia();
        if (self.isEof() or self.source[self.index] != byte) {
            return false;
        }
        self.index += 1;
        return true;
    }

    fn consumeSeparatorOrEnd(self: *DeclarationParser) ScriptError!void {
        self.skipTrivia();
        _ = self.consumeByte(',');
        _ = self.consumeByte(';');
    }

    fn skipTrivia(self: *DeclarationParser) void {
        while (!self.isEof()) {
            const byte = self.source[self.index];
            if (byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r') {
                self.index += 1;
                continue;
            }
            if (byte == '-' and self.index + 1 < self.source.len and self.source[self.index + 1] == '-') {
                self.index += 2;
                while (!self.isEof() and self.source[self.index] != '\n') {
                    self.index += 1;
                }
                continue;
            }
            return;
        }
    }

    fn isEof(self: DeclarationParser) bool {
        return self.index >= self.source.len;
    }
};

fn parseFieldType(value: []const u8) ScriptError!runtime.FieldType {
    if (std.mem.eql(u8, value, "boolean") or std.mem.eql(u8, value, "bool")) {
        return .boolean;
    }
    if (std.mem.eql(u8, value, "int") or std.mem.eql(u8, value, "i32")) {
        return .int;
    }
    if (std.mem.eql(u8, value, "float") or std.mem.eql(u8, value, "f32")) {
        return .float;
    }
    if (std.mem.eql(u8, value, "string")) {
        return .string;
    }
    return ScriptError.UnknownFieldType;
}

fn parseSystemPhase(value: []const u8) ScriptError!runtime.SystemPhase {
    if (std.mem.eql(u8, value, "startup")) {
        return .startup;
    }
    if (std.mem.eql(u8, value, "update")) {
        return .update;
    }
    if (std.mem.eql(u8, value, "fixed_update")) {
        return .fixed_update;
    }
    if (std.mem.eql(u8, value, "render")) {
        return .render;
    }
    return ScriptError.UnknownSystemPhase;
}

fn isIdentifierStart(byte: u8) bool {
    return std.ascii.isAlphabetic(byte) or byte == '_';
}

fn isIdentifierContinue(byte: u8) bool {
    return isIdentifierStart(byte) or std.ascii.isDigit(byte);
}

test "script declarations register components and systems" {
    var registry = runtime.ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registerEngineTypes(&registry);

    var parser = DeclarationParser{
        .allocator = std.testing.allocator,
        .registry = &registry,
        .source =
        \\ecs.component("health", {
        \\  fields = {
        \\    current = "f32",
        \\    max = "f32",
        \\  },
        \\})
        \\
        \\ecs.system("health_regen", {
        \\  phase = "update",
        \\  reads = { "machina.transform" },
        \\  writes = { "health" },
        \\})
        ,
    };
    try parser.parse();

    try std.testing.expect(registry.findComponent("health") != null);
    try std.testing.expect(registry.findSystem("health_regen") != null);
}

test "update schedule batches read-only systems and separates write conflicts" {
    var registry = runtime.ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registerEngineTypes(&registry);

    try registry.registerProjectComponent(.{ .id = "health" });
    try registry.registerProjectSystem(.{
        .id = "read_transform",
        .reads = &.{"machina.transform"},
    });
    try registry.registerProjectSystem(.{
        .id = "observe_health",
        .reads = &.{"health"},
    });
    try registry.registerProjectSystem(.{
        .id = "regen_health",
        .reads = &.{"machina.transform"},
        .writes = &.{"health"},
    });

    var schedule = try buildUpdateSchedule(std.testing.allocator, registry);
    defer schedule.deinit();

    try std.testing.expectEqual(@as(usize, 2), schedule.batchCount());
    try std.testing.expectEqual(@as(usize, 3), schedule.systemCount());
    try std.testing.expectEqual(@as(usize, 2), schedule.batches[0].systems.len);
    try std.testing.expectEqual(@as(usize, 1), schedule.batches[1].systems.len);
}
