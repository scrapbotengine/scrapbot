const std = @import("std");
const Io = std.Io;
const runtime = @import("runtime.zig");

const c = @cImport({
    @cInclude("luau_bridge.h");
});

pub const ScriptError = runtime.RegistryError || runtime.ScheduleError || std.mem.Allocator.Error || error{
    InvalidScript,
    UnknownFieldType,
    UnknownSystemPhase,
};

pub const DiagnosticStage = enum {
    load,
    registration,
    schedule,
    runtime,

    pub fn label(self: DiagnosticStage) []const u8 {
        return switch (self) {
            .load => "script load",
            .registration => "script registration",
            .schedule => "script schedule",
            .runtime => "script runtime",
        };
    }
};

pub const Diagnostic = struct {
    stage: DiagnosticStage,
    path: ?[]const u8 = null,
    system_id: ?[]const u8 = null,
    start: ?DiagnosticPosition = null,
    end: ?DiagnosticPosition = null,
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

pub const DiagnosticPosition = struct {
    line: u32,
    column: ?u32 = null,
};

pub const LoadResult = union(enum) {
    program: Program,
    diagnostic: Diagnostic,
};

const ScriptOrigin = struct {
    index: usize,
    id: []const u8,
    path: []const u8,
    start: ?DiagnosticPosition = null,
    runner_ref: u32 = 0,

    fn deinit(self: ScriptOrigin, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.path);
    }
};

pub const Program = struct {
    allocator: std.mem.Allocator,
    registry: runtime.ComponentRegistry,
    schedule: runtime.SystemSchedule,
    vm: *c.machina_luau,
    active_system: ?*const runtime.ScheduledSystem = null,
    component_origins: std.ArrayList(ScriptOrigin) = .empty,
    system_origins: std.ArrayList(ScriptOrigin) = .empty,
    last_diagnostic: ?Diagnostic = null,
    host_error: ?[:0]u8 = null,

    pub fn deinit(self: *Program) void {
        self.clearHostError();
        self.clearLastDiagnostic();
        for (self.system_origins.items) |origin| {
            origin.deinit(self.allocator);
        }
        self.system_origins.deinit(self.allocator);
        for (self.component_origins.items) |origin| {
            origin.deinit(self.allocator);
        }
        self.component_origins.deinit(self.allocator);
        self.schedule.deinit();
        self.registry.deinit();
        c.machina_luau_destroy(self.vm);
        self.* = undefined;
    }

    pub fn startup(self: *Program, world: *runtime.World) bool {
        return self.runPhase(world, .startup, 0.0);
    }

    pub fn update(self: *Program, world: *runtime.World, delta_seconds: f32) bool {
        return self.runPhase(world, .update, delta_seconds);
    }

    fn runPhase(self: *Program, world: *runtime.World, phase: runtime.SystemPhase, delta_seconds: f32) bool {
        self.clearLastDiagnostic();
        self.clearHostError();
        c.machina_luau_set_callback_context(self.vm, self);

        var ok = true;
        for (self.schedule.batches) |batch| {
            if (batch.phase != phase) {
                continue;
            }

            for (batch.systems) |*system| {
                switch (system.runner) {
                    .none => {},
                    .luau => |runner_ref| {
                        self.clearHostError();
                        self.active_system = system;
                        const system_ok = c.machina_luau_call_system(self.vm, runner_ref, world, delta_seconds) != 0;
                        if (!system_ok and self.last_diagnostic == null) {
                            self.setRuntimeDiagnostic(system.*, runner_ref) catch {};
                        }
                        self.active_system = null;
                        self.clearHostError();
                        ok = ok and system_ok;
                    },
                }
            }
        }
        return ok;
    }

    fn activeSystemAllowsRead(self: Program, component_id: []const u8) bool {
        const active_system = self.active_system orelse return false;
        if (active_system.registry_index >= self.registry.systems.items.len) {
            return false;
        }

        const definition = self.registry.systems.items[active_system.registry_index];
        return containsString(definition.reads, component_id) or containsString(definition.writes, component_id);
    }

    fn activeSystemAllowsWrite(self: Program, component_id: []const u8) bool {
        const active_system = self.active_system orelse return false;
        if (active_system.registry_index >= self.registry.systems.items.len) {
            return false;
        }

        const definition = self.registry.systems.items[active_system.registry_index];
        return containsString(definition.writes, component_id);
    }

    fn activeSystemId(self: Program) []const u8 {
        const active_system = self.active_system orelse return "unknown";
        return active_system.id;
    }

    fn clearHostError(self: *Program) void {
        if (self.host_error) |message| {
            self.allocator.free(message);
            self.host_error = null;
        }
    }

    fn setHostError(self: *Program, comptime format: []const u8, args: anytype) void {
        self.clearHostError();
        const message = std.fmt.allocPrint(self.allocator, format, args) catch return;
        defer self.allocator.free(message);
        self.host_error = self.allocator.dupeZ(u8, message) catch null;
    }

    pub fn clearLastDiagnostic(self: *Program) void {
        if (self.last_diagnostic) |*diagnostic| {
            diagnostic.deinit(self.allocator);
            self.last_diagnostic = null;
        }
    }

    fn setRuntimeDiagnostic(self: *Program, system: runtime.ScheduledSystem, runner_ref: u32) !void {
        const origin = self.findSystemOrigin(system.id, runner_ref);
        const message = lastLuauError(self.vm);
        const location = parseLuauDiagnosticPosition(message) orelse if (origin) |found| found.start else null;
        self.last_diagnostic = try makeDiagnostic(self.allocator, .{
            .stage = .runtime,
            .path = if (origin) |found| found.path else null,
            .system_id = system.id,
            .start = location,
            .message = message,
        });
    }

    fn findSystemOrigin(self: Program, system_id: []const u8, runner_ref: u32) ?ScriptOrigin {
        for (self.system_origins.items) |origin| {
            if (origin.runner_ref == runner_ref or std.mem.eql(u8, origin.id, system_id)) {
                return origin;
            }
        }
        return null;
    }
};

pub fn loadProjectProgram(
    io: Io,
    allocator: std.mem.Allocator,
    root_dir: Io.Dir,
    script_paths: []const []const u8,
) !Program {
    var result = try loadProjectProgramDetailed(io, allocator, root_dir, script_paths);
    switch (result) {
        .program => |program| return program,
        .diagnostic => |*diagnostic| {
            diagnostic.deinit(allocator);
            return ScriptError.InvalidScript;
        },
    }
}

pub fn loadProjectProgramDetailed(
    io: Io,
    allocator: std.mem.Allocator,
    root_dir: Io.Dir,
    script_paths: []const []const u8,
) !LoadResult {
    var program = try initProgram(allocator);
    errdefer program.deinit();

    for (script_paths) |script_path| {
        const contents = try root_dir.readFileAlloc(io, script_path, allocator, .limited(256 * 1024));
        defer allocator.free(contents);
        if (try loadChunk(&program, script_path, contents)) |diagnostic| {
            program.deinit();
            return .{ .diagnostic = diagnostic };
        }
    }

    registerDeclaredTypes(&program) catch |err| {
        const diagnostic = try registrationDiagnostic(&program, err);
        program.deinit();
        return .{ .diagnostic = diagnostic };
    };
    program.schedule = buildRuntimeSchedule(allocator, program.registry) catch |err| {
        const diagnostic = try makeDiagnostic(allocator, .{
            .stage = .schedule,
            .message = @errorName(err),
        });
        program.deinit();
        return .{ .diagnostic = diagnostic };
    };
    return .{ .program = program };
}

pub fn loadSourceProgram(
    allocator: std.mem.Allocator,
    chunk_name: []const u8,
    source: []const u8,
) !Program {
    var program = try initProgram(allocator);
    errdefer program.deinit();
    if (try loadChunk(&program, chunk_name, source)) |diagnostic| {
        var owned_diagnostic = diagnostic;
        owned_diagnostic.deinit(allocator);
        return ScriptError.InvalidScript;
    }
    try registerDeclaredTypes(&program);
    program.schedule = try buildRuntimeSchedule(allocator, program.registry);
    return program;
}

pub fn buildRuntimeSchedule(
    allocator: std.mem.Allocator,
    registry: runtime.ComponentRegistry,
) !runtime.SystemSchedule {
    const script_phases = [_]runtime.SystemPhase{ .startup, .update };
    var batches: std.ArrayList(runtime.SystemBatch) = .empty;
    errdefer {
        for (batches.items) |batch| {
            for (batch.systems) |system| {
                allocator.free(system.id);
            }
            allocator.free(batch.systems);
        }
        batches.deinit(allocator);
    }

    for (script_phases) |phase| {
        const phase_schedule = try registry.buildSchedule(allocator, phase);
        var transferred: usize = 0;
        errdefer {
            for (phase_schedule.batches[transferred..]) |batch| {
                for (batch.systems) |system| {
                    allocator.free(system.id);
                }
                allocator.free(batch.systems);
            }
            allocator.free(phase_schedule.batches);
        }

        for (phase_schedule.batches) |batch| {
            try batches.append(allocator, batch);
            transferred += 1;
        }
        allocator.free(phase_schedule.batches);
    }

    return .{
        .allocator = allocator,
        .batches = try batches.toOwnedSlice(allocator),
    };
}

fn initProgram(allocator: std.mem.Allocator) !Program {
    const callbacks = c.machina_luau_callbacks{
        .query_next = queryNextCallback,
        .get_vec3 = getVec3Callback,
        .set_vec3 = setVec3Callback,
        .get_field = getFieldCallback,
        .set_field = setFieldCallback,
        .spawn_entity = spawnEntityCallback,
        .despawn_entity = despawnEntityCallback,
        .add_component = addComponentCallback,
        .remove_component = removeComponentCallback,
        .host_error = hostErrorCallback,
    };
    const vm = c.machina_luau_create(callbacks) orelse return ScriptError.InvalidScript;

    var registry = runtime.ComponentRegistry.init(allocator);
    errdefer {
        registry.deinit();
        c.machina_luau_destroy(vm);
    }
    try runtime.registerEngineComponents(&registry);

    return .{
        .allocator = allocator,
        .registry = registry,
        .schedule = .{ .allocator = allocator, .batches = &.{} },
        .vm = vm,
    };
}

fn loadChunk(program: *Program, chunk_name: []const u8, source: []const u8) !?Diagnostic {
    const component_start = c.machina_luau_component_count(program.vm);
    const system_start = c.machina_luau_system_count(program.vm);
    const chunk_name_z = try program.allocator.dupeZ(u8, chunk_name);
    defer program.allocator.free(chunk_name_z);

    if (c.machina_luau_load(program.vm, chunk_name_z.ptr, source.ptr, source.len) == 0) {
        const message = lastLuauError(program.vm);
        return try makeDiagnostic(program.allocator, .{
            .stage = .load,
            .path = chunk_name,
            .start = parseLuauDiagnosticPosition(message),
            .message = message,
        });
    }

    try recordOrigins(program, chunk_name, component_start, system_start);
    return null;
}

fn registerDeclaredTypes(program: *Program) ScriptError!void {
    const component_count = c.machina_luau_component_count(program.vm);
    for (0..component_count) |component_index| {
        var fields: std.ArrayList(runtime.ComponentFieldDefinition) = .empty;
        defer fields.deinit(program.allocator);

        const field_count = c.machina_luau_component_field_count(program.vm, component_index);
        for (0..field_count) |field_index| {
            try fields.append(program.allocator, .{
                .name = try spanC(c.machina_luau_component_field_name(program.vm, component_index, field_index)),
                .value_type = try parseFieldType(try spanC(c.machina_luau_component_field_type(program.vm, component_index, field_index))),
            });
        }

        try program.registry.registerProjectComponent(.{
            .id = try spanC(c.machina_luau_component_id(program.vm, component_index)),
            .version = c.machina_luau_component_version(program.vm, component_index),
            .fields = fields.items,
        });
    }

    const system_count = c.machina_luau_system_count(program.vm);
    for (0..system_count) |system_index| {
        var reads = try readSystemReads(program.allocator, program.vm, system_index);
        defer reads.deinit(program.allocator);
        var writes = try readSystemWrites(program.allocator, program.vm, system_index);
        defer writes.deinit(program.allocator);
        var before = try readSystemBefore(program.allocator, program.vm, system_index);
        defer before.deinit(program.allocator);
        var after = try readSystemAfter(program.allocator, program.vm, system_index);
        defer after.deinit(program.allocator);

        const runner_ref = c.machina_luau_system_runner_ref(program.vm, system_index);
        try program.registry.registerProjectSystem(.{
            .id = try spanC(c.machina_luau_system_id(program.vm, system_index)),
            .phase = try parseSystemPhase(try spanC(c.machina_luau_system_phase(program.vm, system_index))),
            .reads = reads.items,
            .writes = writes.items,
            .before = before.items,
            .after = after.items,
            .runner = if (runner_ref == 0) .none else .{ .luau = runner_ref },
        });
    }
}

fn recordOrigins(program: *Program, path: []const u8, component_start: usize, system_start: usize) !void {
    const component_count = c.machina_luau_component_count(program.vm);
    for (component_start..component_count) |component_index| {
        {
            const id = try spanC(c.machina_luau_component_id(program.vm, component_index));
            const owned_id = try program.allocator.dupe(u8, id);
            errdefer program.allocator.free(owned_id);
            const owned_path = try program.allocator.dupe(u8, path);
            errdefer program.allocator.free(owned_path);
            const line = c.machina_luau_component_line(program.vm, component_index);
            try program.component_origins.append(program.allocator, .{
                .index = component_index,
                .id = owned_id,
                .path = owned_path,
                .start = diagnosticPositionFromLine(line),
            });
        }
    }

    const system_count = c.machina_luau_system_count(program.vm);
    for (system_start..system_count) |system_index| {
        {
            const id = try spanC(c.machina_luau_system_id(program.vm, system_index));
            const owned_id = try program.allocator.dupe(u8, id);
            errdefer program.allocator.free(owned_id);
            const owned_path = try program.allocator.dupe(u8, path);
            errdefer program.allocator.free(owned_path);
            const line = c.machina_luau_system_line(program.vm, system_index);
            try program.system_origins.append(program.allocator, .{
                .index = system_index,
                .id = owned_id,
                .path = owned_path,
                .start = diagnosticPositionFromLine(line),
                .runner_ref = c.machina_luau_system_runner_ref(program.vm, system_index),
            });
        }
    }
}

fn registrationDiagnostic(program: *Program, err: anyerror) !Diagnostic {
    const message = @errorName(err);
    if (program.system_origins.items.len > 0) {
        const origin = program.system_origins.items[program.system_origins.items.len - 1];
        return makeDiagnostic(program.allocator, .{
            .stage = .registration,
            .path = origin.path,
            .system_id = origin.id,
            .start = origin.start,
            .message = message,
        });
    }
    if (program.component_origins.items.len > 0) {
        const origin = program.component_origins.items[program.component_origins.items.len - 1];
        return makeDiagnostic(program.allocator, .{
            .stage = .registration,
            .path = origin.path,
            .start = origin.start,
            .message = message,
        });
    }
    return makeDiagnostic(program.allocator, .{
        .stage = .registration,
        .message = message,
    });
}

const DiagnosticDraft = struct {
    stage: DiagnosticStage,
    path: ?[]const u8 = null,
    system_id: ?[]const u8 = null,
    start: ?DiagnosticPosition = null,
    end: ?DiagnosticPosition = null,
    message: []const u8,
};

fn makeDiagnostic(allocator: std.mem.Allocator, draft: DiagnosticDraft) !Diagnostic {
    const path = if (draft.path) |path_value| try allocator.dupe(u8, path_value) else null;
    errdefer if (path) |path_value| allocator.free(path_value);
    const system_id = if (draft.system_id) |system_id_value| try allocator.dupe(u8, system_id_value) else null;
    errdefer if (system_id) |system_id_value| allocator.free(system_id_value);
    return .{
        .stage = draft.stage,
        .path = path,
        .system_id = system_id,
        .start = draft.start,
        .end = draft.end,
        .message = try allocator.dupe(u8, draft.message),
    };
}

fn lastLuauError(vm: *c.machina_luau) []const u8 {
    return std.mem.span(c.machina_luau_last_error(vm));
}

fn diagnosticPositionFromLine(line: c_int) ?DiagnosticPosition {
    if (line <= 0) {
        return null;
    }
    return .{ .line = @intCast(line) };
}

fn parseLuauDiagnosticPosition(message: []const u8) ?DiagnosticPosition {
    var index = std.mem.indexOfScalar(u8, message, ':') orelse return null;
    while (index + 1 < message.len) {
        const number_start = index + 1;
        if (!std.ascii.isDigit(message[number_start])) {
            index = std.mem.indexOfScalarPos(u8, message, index + 1, ':') orelse return null;
            continue;
        }

        var number_end = number_start;
        while (number_end < message.len and std.ascii.isDigit(message[number_end])) {
            number_end += 1;
        }
        if (number_end >= message.len or message[number_end] != ':') {
            index = std.mem.indexOfScalarPos(u8, message, number_end, ':') orelse return null;
            continue;
        }

        const line = std.fmt.parseInt(u32, message[number_start..number_end], 10) catch return null;
        if (line == 0) {
            return null;
        }
        return .{ .line = line };
    }
    return null;
}

fn readSystemReads(allocator: std.mem.Allocator, vm: *c.machina_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.machina_luau_system_reads_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.machina_luau_system_reads_item(vm, system_index, item_index)));
    }
    return values;
}

fn readSystemWrites(allocator: std.mem.Allocator, vm: *c.machina_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.machina_luau_system_writes_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.machina_luau_system_writes_item(vm, system_index, item_index)));
    }
    return values;
}

fn readSystemBefore(allocator: std.mem.Allocator, vm: *c.machina_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.machina_luau_system_before_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.machina_luau_system_before_item(vm, system_index, item_index)));
    }
    return values;
}

fn readSystemAfter(allocator: std.mem.Allocator, vm: *c.machina_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.machina_luau_system_after_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.machina_luau_system_after_item(vm, system_index, item_index)));
    }
    return values;
}

fn spanC(value: ?[*:0]const u8) ScriptError![]const u8 {
    return std.mem.span(value orelse return ScriptError.InvalidScript);
}

fn hostErrorCallback(raw_context: ?*anyopaque) callconv(.c) [*c]const u8 {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return null));
    if (program.host_error) |message| {
        return message.ptr;
    }
    return null;
}

fn queryNextCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_ids: ?[*]const ?[*:0]const u8,
    component_count: usize,
    raw_cursor: ?*u32,
    raw_out_entity: ?*u32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return -1));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return -1));
    const component_id_ptr = raw_component_ids orelse return -1;
    const cursor = raw_cursor orelse return -1;
    const out_entity = raw_out_entity orelse return -1;

    var component_ids_buffer: [16][]const u8 = undefined;
    if (component_count == 0 or component_count > component_ids_buffer.len) {
        program.setHostError("system '{s}' tried to query {d} components; the host bridge supports at most {d}", .{
            program.activeSystemId(),
            component_count,
            component_ids_buffer.len,
        });
        return -1;
    }

    for (0..component_count) |index| {
        const component_id = std.mem.span(component_id_ptr[index] orelse return -1);
        if (!program.activeSystemAllowsRead(component_id)) {
            program.setHostError("system '{s}' tried to query component '{s}' without declaring it in reads or writes", .{
                program.activeSystemId(),
                component_id,
            });
            return -1;
        }
        component_ids_buffer[index] = component_id;
    }

    var cursor_value: usize = cursor.*;
    const entity = world.queryNext(component_ids_buffer[0..component_count], &cursor_value) orelse return 0;
    cursor.* = @intCast(cursor_value);
    out_entity.* = entity.index;
    return 1;
}

fn getVec3Callback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_out_value: ?[*]f32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    const out_value = raw_out_value orelse return 0;
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    const value = world.getVec3(.{ .index = entity_index }, component_id, field_name) catch |err| {
        program.setHostError("system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    out_value[0] = value[0];
    out_value[1] = value[1];
    out_value[2] = value[2];
    return 1;
}

fn setVec3Callback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_value: ?[*]const f32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    const value = raw_value orelse return 0;
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    world.setVec3(.{ .index = entity_index }, component_id, field_name, .{
        value[0],
        value[1],
        value[2],
    }) catch |err| {
        program.setHostError("system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn getFieldCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_out_value: ?*c.machina_luau_field_value,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    const out_value = raw_out_value orelse return 0;
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }

    const value = world.getComponentFieldValue(.{ .index = entity_index }, component_id, field_name) catch |err| {
        program.setHostError("system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    out_value.* = .{
        .tag = 0,
        .boolean_value = 0,
        .int_value = 0,
        .number_value = 0,
        .string_data = null,
        .string_len = 0,
        .vec3_value = .{ 0.0, 0.0, 0.0 },
    };

    switch (value) {
        .boolean => |payload| {
            out_value.tag = c.MACHINA_LUAU_FIELD_BOOLEAN;
            out_value.boolean_value = if (payload) 1 else 0;
        },
        .int => |payload| {
            out_value.tag = c.MACHINA_LUAU_FIELD_INT;
            out_value.int_value = payload;
        },
        .float => |payload| {
            out_value.tag = c.MACHINA_LUAU_FIELD_FLOAT;
            out_value.number_value = payload;
        },
        .vec3 => |payload| {
            out_value.tag = c.MACHINA_LUAU_FIELD_VEC3;
            out_value.vec3_value = payload;
        },
        .string => |payload| {
            out_value.tag = c.MACHINA_LUAU_FIELD_STRING;
            out_value.string_data = payload.ptr;
            out_value.string_len = payload.len;
        },
    }

    return 1;
}

fn setFieldCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_value: ?*const c.machina_luau_field_value,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    const value = raw_value orelse return 0;
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }

    const component_value = componentValueFromLuau(world, .{ .index = entity_index }, component_id, field_name, value) catch |err| {
        program.setHostError("system '{s}' failed to convert value for '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    world.setComponentFieldValue(.{ .index = entity_index }, component_id, field_name, component_value) catch |err| {
        program.setHostError("system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn spawnEntityCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_id: ?[*:0]const u8,
    raw_name: ?[*:0]const u8,
    raw_out_entity: ?*u32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const id = std.mem.span(raw_id orelse return 0);
    const name = std.mem.span(raw_name orelse return 0);
    const out_entity = raw_out_entity orelse return 0;

    const entity = world.createEntity(id, name) catch |err| {
        program.setHostError("system '{s}' failed to spawn entity '{s}': {s}", .{
            program.activeSystemId(),
            id,
            @errorName(err),
        });
        return 0;
    };
    out_entity.* = entity.index;
    return 1;
}

fn despawnEntityCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const entity = runtime.EntityHandle{ .index = entity_index };
    _ = world.entity(entity) catch |err| {
        program.setHostError("system '{s}' failed to despawn entity {d}: {s}", .{
            program.activeSystemId(),
            entity_index,
            @errorName(err),
        });
        return 0;
    };

    var components = world.entityComponents(entity) catch |err| {
        program.setHostError("system '{s}' failed to inspect entity {d}: {s}", .{
            program.activeSystemId(),
            entity_index,
            @errorName(err),
        });
        return 0;
    };
    while (components.next()) |component_id| {
        if (!program.activeSystemAllowsWrite(component_id)) {
            program.setHostError("system '{s}' tried to despawn entity {d} without declaring write access to '{s}'", .{
                program.activeSystemId(),
                entity_index,
                component_id,
            });
            return 0;
        }
    }

    _ = world.removeEntity(entity) catch |err| {
        program.setHostError("system '{s}' failed to despawn entity {d}: {s}", .{
            program.activeSystemId(),
            entity_index,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn addComponentCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    raw_component_id: ?[*:0]const u8,
    raw_fields: ?[*]const c.machina_luau_component_field_value,
    field_count: usize,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to add component '{s}' without declaring it in writes", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    }

    const definition = program.registry.findComponent(component_id) orelse {
        program.setHostError("system '{s}' tried to add unknown component '{s}'", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    };
    const entity = runtime.EntityHandle{ .index = entity_index };
    const raw_slice = if (field_count == 0) &[_]c.machina_luau_component_field_value{} else (raw_fields orelse return 0)[0..field_count];
    const fields = program.allocator.alloc(runtime.ComponentFieldValue, field_count) catch {
        program.setHostError("system '{s}' failed to allocate component fields for '{s}'", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    };
    defer program.allocator.free(fields);

    for (raw_slice, 0..) |raw_field, index| {
        const field_name = raw_field.name[0..raw_field.name_len];
        const field_definition = findComponentField(definition.*, field_name) orelse {
            program.setHostError("system '{s}' tried to add unknown field '{s}.{s}'", .{
                program.activeSystemId(),
                component_id,
                field_name,
            });
            return 0;
        };
        fields[index] = .{
            .name = field_name,
            .value = componentValueFromLuauType(field_definition.value_type, &raw_field.value) catch |err| {
                program.setHostError("system '{s}' failed to convert value for '{s}.{s}': {s}", .{
                    program.activeSystemId(),
                    component_id,
                    field_name,
                    @errorName(err),
                });
                return 0;
            },
        };
    }

    world.setComponent(entity, component_id, fields) catch |err| {
        program.setHostError("system '{s}' failed to add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn removeComponentCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    raw_component_id: ?[*:0]const u8,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to remove component '{s}' without declaring it in writes", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    }
    _ = world.removeComponent(.{ .index = entity_index }, component_id) catch |err| {
        program.setHostError("system '{s}' failed to remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn componentValueFromLuau(
    world: *runtime.World,
    entity: runtime.EntityHandle,
    component_id: []const u8,
    field_name: []const u8,
    value: *const c.machina_luau_field_value,
) !runtime.ComponentValue {
    return switch (value.tag) {
        c.MACHINA_LUAU_FIELD_BOOLEAN => .{ .boolean = value.boolean_value != 0 },
        c.MACHINA_LUAU_FIELD_STRING => .{ .string = stringFromLuau(value) },
        c.MACHINA_LUAU_FIELD_VEC3 => blk: {
            const vec3 = value.vec3_value;
            if (!std.math.isFinite(vec3[0]) or !std.math.isFinite(vec3[1]) or !std.math.isFinite(vec3[2])) {
                return ScriptError.InvalidScript;
            }
            break :blk .{ .vec3 = .{ vec3[0], vec3[1], vec3[2] } };
        },
        c.MACHINA_LUAU_FIELD_NUMBER => blk: {
            if (!std.math.isFinite(value.number_value)) {
                return ScriptError.InvalidScript;
            }

            const current = try world.getComponentFieldValue(entity, component_id, field_name);
            break :blk switch (current) {
                .int => .{ .int = try i32FromLuauNumber(value.number_value) },
                .float => .{ .float = try f32FromLuauNumber(value.number_value) },
                else => return ScriptError.InvalidScript,
            };
        },
        else => ScriptError.InvalidScript,
    };
}

fn componentValueFromLuauType(field_type: runtime.FieldType, value: *const c.machina_luau_field_value) !runtime.ComponentValue {
    return switch (field_type) {
        .boolean => switch (value.tag) {
            c.MACHINA_LUAU_FIELD_BOOLEAN => .{ .boolean = value.boolean_value != 0 },
            else => ScriptError.InvalidScript,
        },
        .string => switch (value.tag) {
            c.MACHINA_LUAU_FIELD_STRING => .{ .string = stringFromLuau(value) },
            else => ScriptError.InvalidScript,
        },
        .vec3 => switch (value.tag) {
            c.MACHINA_LUAU_FIELD_VEC3 => blk: {
                const vec3 = value.vec3_value;
                if (!std.math.isFinite(vec3[0]) or !std.math.isFinite(vec3[1]) or !std.math.isFinite(vec3[2])) {
                    return ScriptError.InvalidScript;
                }
                break :blk .{ .vec3 = .{ vec3[0], vec3[1], vec3[2] } };
            },
            else => ScriptError.InvalidScript,
        },
        .int => switch (value.tag) {
            c.MACHINA_LUAU_FIELD_NUMBER => .{ .int = try i32FromLuauNumber(value.number_value) },
            c.MACHINA_LUAU_FIELD_INT => .{ .int = value.int_value },
            else => ScriptError.InvalidScript,
        },
        .float => switch (value.tag) {
            c.MACHINA_LUAU_FIELD_NUMBER => .{ .float = try f32FromLuauNumber(value.number_value) },
            c.MACHINA_LUAU_FIELD_FLOAT => .{ .float = @floatCast(value.number_value) },
            else => ScriptError.InvalidScript,
        },
    };
}

fn findComponentField(definition: runtime.ComponentDefinition, field_name: []const u8) ?runtime.ComponentFieldDefinition {
    for (definition.fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return field;
        }
    }
    return null;
}

fn stringFromLuau(value: *const c.machina_luau_field_value) []const u8 {
    if (value.string_len == 0) {
        return "";
    }
    return value.string_data[0..value.string_len];
}

fn i32FromLuauNumber(value: f64) !i32 {
    if (!std.math.isFinite(value)) {
        return ScriptError.InvalidScript;
    }
    const min = @as(f64, @floatFromInt(std.math.minInt(i32)));
    const max = @as(f64, @floatFromInt(std.math.maxInt(i32)));
    if (value < min or value > max or value != @floor(value)) {
        return ScriptError.InvalidScript;
    }
    return @intFromFloat(value);
}

fn f32FromLuauNumber(value: f64) !f32 {
    if (!std.math.isFinite(value)) {
        return ScriptError.InvalidScript;
    }
    const narrowed: f32 = @floatCast(value);
    if (!std.math.isFinite(narrowed)) {
        return ScriptError.InvalidScript;
    }
    return narrowed;
}

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
    if (std.mem.eql(u8, value, "vec3")) {
        return .vec3;
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

fn containsString(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, needle)) {
            return true;
        }
    }
    return false;
}

test "luau declarations register components and executable systems" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\local RotatingCubes = ecs.query(Transform, Spin)
        \\
        \\ecs.system("rotate_cubes", {
        \\  phase = "update",
        \\  query = RotatingCubes,
        \\  writes = ecs.refs(Transform),
        \\  run = function(world, dt)
        \\    for _entity, transform, spin in RotatingCubes:iter(world) do
        \\      transform.rotation = {
        \\        transform.rotation[1] + spin.angular_velocity[1] * dt * (1 + 1.5),
        \\        transform.rotation[2] + spin.angular_velocity[2] * dt * (1 + 1.5),
        \\        transform.rotation[3] + spin.angular_velocity[3] * dt * (1 + 1.5),
        \\      }
        \\    end
        \\  end,
        \\})
    );
    defer program.deinit();

    try std.testing.expect(program.registry.findComponent("spin") != null);
    const system = program.registry.findSystem("rotate_cubes") orelse return error.TestExpectedEqual;
    try std.testing.expect(system.runner.luau != 0);
    try std.testing.expectEqual(@as(usize, 1), system.reads.len);
    try std.testing.expectEqualStrings("spin", system.reads[0]);
    try std.testing.expectEqual(@as(usize, 1), system.writes.len);
    try std.testing.expectEqualStrings("machina.transform", system.writes[0]);

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("spinner", "Spinner");
    try world.setTransform(entity, .{});
    try world.setSpin(entity, .{ .angular_velocity = .{ 1.0, 0.0, 0.0 } });

    try std.testing.expect(program.update(&world, 0.5));
    const transform = (try world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 1.25), transform.rotation[0]);
}

test "luau systems can spawn despawn add and remove components" {
    var program = try loadSourceProgram(
        std.testing.allocator,
        "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local Spawned = ecs.component("spawned", {
        \\  fields = ecs.fields({
        \\    value = "int",
        \\  }),
        \\})
        \\local Temporary = ecs.component("temporary", {
        \\  fields = ecs.fields({
        \\    value = "int",
        \\  }),
        \\})
        \\
        \\ecs.system("spawn_entities", {
        \\  phase = "startup",
        \\  writes = ecs.refs(Transform, Spawned, Temporary),
        \\  run = function(world, _dt)
        \\    local entity = world.spawn("spawned-one", "Spawned One")
        \\    entity:add(Transform, {
        \\      position = { 1.0, 2.0, 3.0 },
        \\      rotation = { 0.0, 0.0, 0.0 },
        \\      scale = { 1.0, 1.0, 1.0 },
        \\    })
        \\    entity:add(Spawned, { value = 7 })
        \\    entity:add(Temporary, { value = 99 })
        \\    entity:remove(Temporary)
        \\
        \\    local doomed = world.spawn("doomed", "Doomed")
        \\    doomed:add(Temporary, { value = 1 })
        \\    doomed:despawn()
        \\  end,
        \\})
        ,
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try std.testing.expect(program.startup(&world));
    const spawned = world.findEntityById("spawned-one") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), world.entityCount());
    try std.testing.expect(try world.hasComponent(spawned, runtime.transform_component_id));
    try std.testing.expect(try world.hasComponent(spawned, "spawned"));
    try std.testing.expect(!try world.hasComponent(spawned, "temporary"));
    try std.testing.expectEqual(@as(i32, 7), try world.getInt(spawned, "spawned", "value"));
    try std.testing.expect(world.findEntityById("doomed") == null);
}

test "luau component handles can reference engine components without registration" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local RenderCube = ecs.component<<MachinaRenderCube>>("machina.render.cube")
        \\
        \\ecs.system("observe_cubes", {
        \\  reads = ecs.refs(Transform, RenderCube),
        \\})
    );
    defer program.deinit();

    try std.testing.expect(program.registry.findComponent("spin") == null);
    try std.testing.expect(program.registry.findSystem("observe_cubes") != null);
}

test "luau component handles expose a guarded type brand function" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\if type(Transform.__machina_component_type) ~= "function" then
        \\  error("component type brand is missing")
        \\end
        \\local ok = pcall(function()
        \\  Transform.__machina_component_type()
        \\end)
        \\if ok then
        \\  error("component type brand should not be callable gameplay API")
        \\end
    );
    defer program.deinit();
}

test "luau refs helper erases component handles for system declarations" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local RenderCube = ecs.component<<MachinaRenderCube>>("machina.render.cube")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\
        \\ecs.system("observe_everything", {
        \\  reads = ecs.refs(Transform, RenderCube, Spin),
        \\})
    );
    defer program.deinit();

    const system = program.registry.findSystem("observe_everything") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 3), system.reads.len);
    try std.testing.expectEqualStrings("machina.transform", system.reads[0]);
    try std.testing.expectEqualStrings("machina.render.cube", system.reads[1]);
    try std.testing.expectEqualStrings("spin", system.reads[2]);
}

test "luau fields helper preserves component declaration fields" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\type Spin = {
        \\  angular_velocity: MachinaVec3,
        \\}
        \\
        \\local _Spin = ecs.component<<Spin>>("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
    );
    defer program.deinit();

    const spin = program.registry.findComponent("spin") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), spin.fields.len);
    try std.testing.expectEqualStrings("angular_velocity", spin.fields[0].name);
    try std.testing.expectEqual(runtime.FieldType.vec3, spin.fields[0].value_type);
}

test "luau fields helper infers and preserves component payload types" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\local Spinners = ecs.query(Spin)
        \\
        \\ecs.system("observe_spin", {
        \\  query = Spinners,
        \\})
    );
    defer program.deinit();

    const spin = program.registry.findComponent("spin") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), spin.fields.len);
    try std.testing.expectEqualStrings("angular_velocity", spin.fields[0].name);
    try std.testing.expectEqual(runtime.FieldType.vec3, spin.fields[0].value_type);
    const system = program.registry.findSystem("observe_spin") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), system.reads.len);
    try std.testing.expectEqualStrings("spin", system.reads[0]);
}

test "luau component proxies read and write scalar fields" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Stats = ecs.component("stats", {
        \\  fields = ecs.fields({
        \\    enabled = "boolean",
        \\    count = "i32",
        \\    speed = "f32",
        \\    label = "string",
        \\  }),
        \\})
        \\local StatsQuery = ecs.query(Stats)
        \\
        \\ecs.system("update_stats", {
        \\  query = StatsQuery,
        \\  writes = ecs.refs(Stats),
        \\  run = function(world, _dt)
        \\    for _entity, stats in StatsQuery:iter(world) do
        \\      if stats.enabled and stats.label == "ready" then
        \\        stats.count = stats.count + 1
        \\        stats.speed = stats.speed + 0.5
        \\        stats.label = "done"
        \\      end
        \\    end
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("stats-entity", "Stats Entity");
    const fields = [_]runtime.ComponentFieldValue{
        .{ .name = "enabled", .value = .{ .boolean = true } },
        .{ .name = "count", .value = .{ .int = 41 } },
        .{ .name = "speed", .value = .{ .float = 1.5 } },
        .{ .name = "label", .value = .{ .string = "ready" } },
    };
    try world.setComponent(entity, "stats", &fields);

    try std.testing.expect(program.update(&world, 0.25));
    try std.testing.expectEqual(runtime.ComponentValue{ .boolean = true }, try world.getComponentFieldValue(entity, "stats", "enabled"));
    try std.testing.expectEqual(runtime.ComponentValue{ .int = 42 }, try world.getComponentFieldValue(entity, "stats", "count"));
    try std.testing.expectEqual(runtime.ComponentValue{ .float = 2.0 }, try world.getComponentFieldValue(entity, "stats", "speed"));
    const label = try world.getComponentFieldValue(entity, "stats", "label");
    try std.testing.expectEqualStrings("done", label.string);
}

test "luau component proxy rejects scalar values outside host field range" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Stats = ecs.component("stats", {
        \\  fields = ecs.fields({
        \\    speed = "f32",
        \\  }),
        \\})
        \\local StatsQuery = ecs.query(Stats)
        \\
        \\ecs.system("break_stats", {
        \\  query = StatsQuery,
        \\  writes = ecs.refs(Stats),
        \\  run = function(world, _dt)
        \\    for _entity, stats in StatsQuery:iter(world) do
        \\      stats.speed = 1e100
        \\    end
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("stats-entity", "Stats Entity");
    const fields = [_]runtime.ComponentFieldValue{
        .{ .name = "speed", .value = .{ .float = 1.5 } },
    };
    try world.setComponent(entity, "stats", &fields);

    try std.testing.expect(!program.update(&world, 0.25));
    try std.testing.expectEqual(runtime.ComponentValue{ .float = 1.5 }, try world.getComponentFieldValue(entity, "stats", "speed"));
}

test "luau schema helper rejects non-marker field values" {
    try std.testing.expectError(ScriptError.InvalidScript, loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local _Spin = ecs.component("spin", {
        \\  fields = ecs.schema({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
    ));
}

test "luau query objects infer system reads from unwritten query components" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local RenderCube = ecs.component<<MachinaRenderCube>>("machina.render.cube")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\local RotatingCubes = ecs.query(Transform, Spin, RenderCube)
        \\
        \\ecs.system("rotate_cubes", {
        \\  query = RotatingCubes,
        \\  writes = ecs.refs(Transform),
        \\})
    );
    defer program.deinit();

    const system = program.registry.findSystem("rotate_cubes") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), system.reads.len);
    try std.testing.expectEqualStrings("spin", system.reads[0]);
    try std.testing.expectEqualStrings("machina.render.cube", system.reads[1]);
    try std.testing.expectEqual(@as(usize, 1), system.writes.len);
    try std.testing.expectEqualStrings("machina.transform", system.writes[0]);
}

test "luau query objects reject duplicate component refs" {
    try std.testing.expectError(ScriptError.InvalidScript, loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local _BadQuery = ecs.query(Transform, Transform)
    ));
}

test "luau world mutation requires declared system access" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\type Marker = {}
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\
        \\local Marker = ecs.component<<Marker>>("marker", {})
        \\local RotatingCubes = ecs.query(Transform, Spin)
        \\
        \\ecs.system("bad_rotate", {
        \\  query = RotatingCubes,
        \\  writes = ecs.refs(Marker),
        \\  run = function(world, dt)
        \\    for _entity, transform, spin in RotatingCubes:iter(world) do
        \\      transform.rotation = { dt, 0, 0 }
        \\    end
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("spinner", "Spinner");
    try world.setTransform(entity, .{});
    try world.setSpin(entity, .{ .angular_velocity = .{ 1.0, 0.0, 0.0 } });

    try std.testing.expect(!program.update(&world, 1.0));
    const diagnostic = program.last_diagnostic orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(DiagnosticStage.runtime, diagnostic.stage);
    try std.testing.expectEqualStrings("bad_rotate", diagnostic.system_id orelse return error.TestExpectedEqual);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "bad_rotate") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "machina.transform.rotation") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "writes") != null);
    const transform = (try world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 0.0), transform.rotation[0]);
}

test "luau world query requires declared component access" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\type Marker = {}
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\
        \\local Marker = ecs.component<<Marker>>("marker", {})
        \\local Markers = ecs.query(Marker)
        \\
        \\ecs.system("bad_query", {
        \\  reads = ecs.refs(Spin),
        \\  writes = ecs.refs(Transform),
        \\  run = function(world, dt)
        \\    for entity, marker in Markers:iter(world) do
        \\      entity.set_vec3("machina.transform", "rotation", { dt, 0, 0 })
        \\    end
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("spinner", "Spinner");
    try world.setTransform(entity, .{});
    try world.setSpin(entity, .{ .angular_velocity = .{ 1.0, 0.0, 0.0 } });

    try std.testing.expect(!program.update(&world, 1.0));
    const diagnostic = program.last_diagnostic orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(DiagnosticStage.runtime, diagnostic.stage);
    try std.testing.expectEqualStrings("bad_query", diagnostic.system_id orelse return error.TestExpectedEqual);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "bad_query") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "marker") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "reads or writes") != null);
}

test "script runtime schedule includes startup and update batches" {
    var registry = runtime.ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try runtime.registerEngineComponents(&registry);

    try registry.registerProjectComponent(.{ .id = "stamina" });
    try registry.registerProjectSystem(.{
        .id = "spawn_initial",
        .phase = .startup,
        .writes = &.{"machina.transform"},
    });
    try registry.registerProjectSystem(.{
        .id = "read_transform",
        .reads = &.{"machina.transform"},
    });
    try registry.registerProjectSystem(.{
        .id = "observe_stamina",
        .reads = &.{"stamina"},
    });
    try registry.registerProjectSystem(.{
        .id = "regen_stamina",
        .reads = &.{"machina.transform"},
        .writes = &.{"stamina"},
    });

    var schedule = try buildRuntimeSchedule(std.testing.allocator, registry);
    defer schedule.deinit();

    try std.testing.expectEqual(@as(usize, 3), schedule.batchCount());
    try std.testing.expectEqual(@as(usize, 4), schedule.systemCount());
    try std.testing.expectEqual(runtime.SystemPhase.startup, schedule.batches[0].phase);
    try std.testing.expectEqual(@as(usize, 1), schedule.batches[0].systems.len);
    try std.testing.expectEqualStrings("spawn_initial", schedule.batches[0].systems[0].id);
    try std.testing.expectEqual(runtime.SystemPhase.update, schedule.batches[1].phase);
    try std.testing.expectEqual(@as(usize, 2), schedule.batches[1].systems.len);
    try std.testing.expectEqual(runtime.SystemPhase.update, schedule.batches[2].phase);
    try std.testing.expectEqual(@as(usize, 1), schedule.batches[2].systems.len);
}
