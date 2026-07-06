const std = @import("std");
const native_api = @import("../native_api.zig");
const runtime = @import("../runtime.zig");
const script = @import("main.zig");

const c = script.c;

pub fn hostErrorCallback(raw_context: ?*anyopaque) callconv(.c) [*c]const u8 {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return null));
    if (program.host_error) |message| {
        return message.ptr;
    }
    return null;
}

pub const NativeCallContext = struct {
    program: *script.Program,
    world: *runtime.World,
};

pub const native_system_api = native_api.SystemApi{
    .query_next = nativeQueryNext,
    .get_vec3 = nativeGetVec3,
    .set_vec3 = nativeSetVec3,
    .get_f32 = nativeGetF32,
    .set_f32 = nativeSetF32,
    .get_bool = nativeGetBool,
    .set_bool = nativeSetBool,
    .get_i32 = nativeGetI32,
    .set_i32 = nativeSetI32,
    .get_string = nativeGetString,
    .set_string = nativeSetString,
    .spawn_entity = nativeSpawnEntity,
    .despawn_entity = nativeDespawnEntity,
    .add_component = nativeAddComponent,
    .remove_component = nativeRemoveComponent,
    .host_error = nativeHostError,
};

fn nativeCallContext(raw_context: ?*anyopaque) ?*NativeCallContext {
    return @ptrCast(@alignCast(raw_context orelse return null));
}

fn nativeHostError(raw_context: ?*anyopaque) callconv(.c) ?[*:0]const u8 {
    const context = nativeCallContext(raw_context) orelse return null;
    if (context.program.host_error) |message| {
        return message.ptr;
    }
    return null;
}

fn nativeQueryNext(
    raw_context: ?*anyopaque,
    raw_component_ids: ?[*]const [*:0]const u8,
    component_count: usize,
    raw_cursor: *usize,
    out_entity: *native_api.Entity,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return -1;
    const program = context.program;
    const component_id_ptr = raw_component_ids orelse return -1;

    var component_ids_buffer: [16][]const u8 = undefined;
    if (component_count == 0 or component_count > component_ids_buffer.len) {
        program.setHostError("native system '{s}' tried to query {d} components; the host bridge supports at most {d}", .{
            program.activeSystemId(),
            component_count,
            component_ids_buffer.len,
        });
        return -1;
    }

    for (0..component_count) |index| {
        const component_id = std.mem.span(component_id_ptr[index]);
        if (!program.activeSystemAllowsRead(component_id)) {
            program.setHostError("native system '{s}' tried to query component '{s}' without declaring it in reads or writes", .{
                program.activeSystemId(),
                component_id,
            });
            return -1;
        }
        component_ids_buffer[index] = component_id;
    }

    const entity = context.world.queryNext(component_ids_buffer[0..component_count], raw_cursor) orelse return 0;
    out_entity.* = .{
        .index = entity.index,
        .generation = entity.generation,
    };
    return 1;
}

fn nativeGetVec3(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    out_value: *native_api.Vec3,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("native system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    const value = context.world.getVec3(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name) catch |err| {
        program.setHostError("native system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    out_value.* = .{ .x = value[0], .y = value[1], .z = value[2] };
    return 1;
}

fn nativeSetVec3(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    value: native_api.Vec3,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (!std.math.isFinite(value.x) or !std.math.isFinite(value.y) or !std.math.isFinite(value.z)) {
        program.setHostError("native system '{s}' tried to write non-finite vec3 value to '{s}.{s}'", .{
            program.activeSystemId(),
            component_id,
            field_name,
        });
        return 0;
    }
    context.world.setVec3(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name, .{
        value.x,
        value.y,
        value.z,
    }) catch |err| {
        program.setHostError("native system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeGetF32(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    out_value: *f32,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("native system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    out_value.* = context.world.getFloat(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name) catch |err| {
        program.setHostError("native system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeSetF32(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    value: f32,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (!std.math.isFinite(value)) {
        program.setHostError("native system '{s}' tried to write non-finite f32 value to '{s}.{s}'", .{
            program.activeSystemId(),
            component_id,
            field_name,
        });
        return 0;
    }
    context.world.setComponentFieldValue(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name, .{ .float = value }) catch |err| {
        program.setHostError("native system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeGetBool(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    out_value: *u8,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("native system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    const value = context.world.getBoolean(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name) catch |err| {
        program.setHostError("native system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    out_value.* = if (value) 1 else 0;
    return 1;
}

fn nativeSetBool(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    value: u8,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    context.world.setComponentFieldValue(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name, .{ .boolean = value != 0 }) catch |err| {
        program.setHostError("native system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeGetI32(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    out_value: *i32,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("native system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    out_value.* = context.world.getInt(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name) catch |err| {
        program.setHostError("native system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeSetI32(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    value: i32,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    context.world.setComponentFieldValue(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name, .{ .int = value }) catch |err| {
        program.setHostError("native system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeGetString(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    out_value: *native_api.StringView,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("native system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    const value = context.world.getString(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name) catch |err| {
        program.setHostError("native system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    out_value.* = native_api.StringView.fromSlice(value);
    return 1;
}

fn nativeSetString(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    raw_value: native_api.StringView,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    const value = raw_value.asSlice() orelse {
        program.setHostError("native system '{s}' tried to write invalid string value to '{s}.{s}'", .{
            program.activeSystemId(),
            component_id,
            field_name,
        });
        return 0;
    };
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    context.world.setComponentFieldValue(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name, .{ .string = value }) catch |err| {
        program.setHostError("native system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeSpawnEntity(
    raw_context: ?*anyopaque,
    raw_id: native_api.StringView,
    raw_name: native_api.StringView,
    out_entity: *native_api.Entity,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const id = raw_id.asSlice() orelse {
        program.setHostError("native system '{s}' tried to spawn an entity with an invalid id", .{program.activeSystemId()});
        return 0;
    };
    const name = raw_name.asSlice() orelse {
        program.setHostError("native system '{s}' tried to spawn entity '{s}' with an invalid name", .{ program.activeSystemId(), id });
        return 0;
    };

    const entity = context.world.createEntity(id, name) catch |err| {
        program.setHostError("native system '{s}' failed to spawn entity '{s}': {s}", .{
            program.activeSystemId(),
            id,
            @errorName(err),
        });
        return 0;
    };
    out_entity.* = .{ .index = entity.index, .generation = entity.generation };
    program.immediate_script_spawns.append(program.allocator, entity) catch {
        _ = context.world.removeEntity(entity) catch {};
        program.setHostError("native system '{s}' failed to record spawned entity '{s}': {s}", .{
            program.activeSystemId(),
            id,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    return 1;
}

fn nativeDespawnEntity(raw_context: ?*anyopaque, entity: native_api.Entity) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    return queueDespawnEntity(context.program, context.world, .{ .index = entity.index, .generation = entity.generation });
}

fn nativeAddComponent(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_fields: ?[*]const native_api.FieldValue,
    field_count: usize,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to add component '{s}' without declaring it in writes", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    }

    const definition = program.registry.findComponent(component_id) orelse {
        program.setHostError("native system '{s}' tried to add unknown component '{s}'", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    };
    const runtime_entity = runtime.EntityHandle{ .index = entity.index, .generation = entity.generation };
    _ = context.world.entity(runtime_entity) catch |err| {
        program.setHostError("native system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(err),
        });
        return 0;
    };
    const raw_slice = if (field_count == 0) &[_]native_api.FieldValue{} else (raw_fields orelse return 0)[0..field_count];
    const fields = program.allocator.alloc(script.QueuedComponentFieldValue, field_count) catch {
        program.setHostError("native system '{s}' failed to allocate component fields for '{s}'", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    };
    var initialized_fields: usize = 0;
    var fields_owned = true;
    defer {
        if (fields_owned) {
            for (fields[0..initialized_fields]) |*field| {
                field.deinit(program.allocator);
            }
            program.allocator.free(fields);
        }
    }

    for (raw_slice, 0..) |raw_field, index| {
        const field_name = std.mem.span(raw_field.name);
        const field_definition = findComponentField(definition.*, field_name) orelse {
            program.setHostError("native system '{s}' tried to add unknown field '{s}.{s}'", .{
                program.activeSystemId(),
                component_id,
                field_name,
            });
            return 0;
        };
        const component_value = componentValueFromNativeType(field_definition.value_type, raw_field) catch |err| {
            program.setHostError("native system '{s}' failed to convert value for '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
        const owned_field_name = program.allocator.dupe(u8, field_name) catch {
            program.setHostError("native system '{s}' failed to queue field name for '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(error.OutOfMemory),
            });
            return 0;
        };
        fields[index] = .{
            .name = owned_field_name,
            .value = cloneComponentValue(program.allocator, component_value) catch |err| {
                program.allocator.free(owned_field_name);
                program.setHostError("native system '{s}' failed to queue value for '{s}.{s}': {s}", .{
                    program.activeSystemId(),
                    component_id,
                    field_name,
                    @errorName(err),
                });
                return 0;
            },
        };
        initialized_fields += 1;
    }

    const owned_component_id = program.allocator.dupe(u8, component_id) catch {
        program.setHostError("native system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    var component_id_owned = true;
    defer {
        if (component_id_owned) {
            program.allocator.free(owned_component_id);
        }
    }

    program.queued_script_commands.append(program.allocator, .{ .add_component = .{
        .entity = runtime_entity,
        .component_id = owned_component_id,
        .fields = fields,
    } }) catch {
        program.setHostError("native system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    fields_owned = false;
    component_id_owned = false;
    return 1;
}

fn nativeRemoveComponent(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    return queueRemoveComponent(context.program, context.world, .{ .index = entity.index, .generation = entity.generation }, std.mem.span(raw_component_id));
}

pub fn queryNextCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_ids: ?[*]const ?[*:0]const u8,
    component_count: usize,
    raw_cursor: ?*u32,
    raw_out_entity: ?*u32,
    raw_out_entity_generation: ?*u32,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return -1));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return -1));
    const component_id_ptr = raw_component_ids orelse return -1;
    const cursor = raw_cursor orelse return -1;
    const out_entity = raw_out_entity orelse return -1;
    const out_entity_generation = raw_out_entity_generation orelse return -1;

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
    out_entity_generation.* = entity.generation;
    return 1;
}

pub fn prepareQueryCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_ids: ?[*]const ?[*:0]const u8,
    component_count: usize,
    raw_out_component_table_indices: ?[*]u32,
    raw_out_driver_table_index: ?*u32,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return -1));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return -1));
    const component_id_ptr = raw_component_ids orelse return -1;
    const out_component_table_indices = raw_out_component_table_indices orelse return -1;
    const out_driver_table_index = raw_out_driver_table_index orelse return -1;

    var component_table_indices_buffer: [16]u32 = undefined;
    if (component_count == 0 or component_count > component_table_indices_buffer.len) {
        program.setHostError("system '{s}' tried to query {d} components; the host bridge supports at most {d}", .{
            program.activeSystemId(),
            component_count,
            component_table_indices_buffer.len,
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

        const table_index = world.resolveComponentTableIndex(component_id) orelse return 0;
        component_table_indices_buffer[index] = table_index;
        out_component_table_indices[index] = table_index;
    }

    const driver_table_index = (world.queryDriverTableIndex(component_table_indices_buffer[0..component_count]) catch |err| {
        program.setHostError("system '{s}' failed to prepare query: {s}", .{
            program.activeSystemId(),
            @errorName(err),
        });
        return -1;
    }) orelse return 0;
    out_driver_table_index.* = driver_table_index;
    return 1;
}

pub fn queryNextPreparedCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_table_indices: ?[*]const u32,
    component_count: usize,
    driver_table_index: u32,
    raw_cursor: ?*u32,
    raw_out_entity: ?*u32,
    raw_out_entity_generation: ?*u32,
    raw_out_component_rows: ?[*]u32,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return -1));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return -1));
    const component_table_indices_ptr = raw_component_table_indices orelse return -1;
    const cursor = raw_cursor orelse return -1;
    const out_entity = raw_out_entity orelse return -1;
    const out_entity_generation = raw_out_entity_generation orelse return -1;
    const out_component_rows_ptr = raw_out_component_rows orelse return -1;

    if (component_count == 0 or component_count > 16) {
        program.setHostError("system '{s}' tried to run prepared query with unsupported component count {d}", .{
            program.activeSystemId(),
            component_count,
        });
        return -1;
    }

    const component_table_indices = component_table_indices_ptr[0..component_count];
    const out_component_rows = out_component_rows_ptr[0..component_count];
    var cursor_value: usize = cursor.*;
    const entity = (world.queryNextResolved(component_table_indices, driver_table_index, &cursor_value, out_component_rows) catch |err| {
        program.setHostError("system '{s}' failed to run prepared query: {s}", .{
            program.activeSystemId(),
            @errorName(err),
        });
        return -1;
    }) orelse return 0;

    cursor.* = @intCast(cursor_value);
    out_entity.* = entity.index;
    out_entity_generation.* = entity.generation;
    return 1;
}

pub fn queryPlanGenerationCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
) callconv(.c) u64 {
    _ = raw_context;
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    return world.queryPlanGeneration();
}

pub fn readF32ViewCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    raw_entities: ?[*]const u32,
    raw_entity_generations: ?[*]const u32,
    raw_component_rows: ?[*]const u32,
    entity_count: usize,
    raw_field_name: ?[*:0]const u8,
    raw_out_values: ?[*]f32,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("system '{s}' tried to bulk-read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (entity_count == 0) {
        return 1;
    }

    const entities = (raw_entities orelse return 0)[0..entity_count];
    const entity_generations = (raw_entity_generations orelse return 0)[0..entity_count];
    const component_rows = (raw_component_rows orelse return 0)[0..entity_count];
    const out_values = (raw_out_values orelse return 0)[0..entity_count];
    for (entities, entity_generations, component_rows, out_values) |entity_index, entity_generation, component_row_index, *out_value| {
        const value = world.getComponentFieldValueResolved(.{ .index = entity_index, .generation = entity_generation }, .{
            .table_index = component_table_index,
            .row_index = component_row_index,
        }, field_name) catch |err| {
            program.setHostError("system '{s}' failed to bulk-read '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
        out_value.* = switch (value) {
            .float => |payload| payload,
            else => {
                program.setHostError("system '{s}' tried to bulk-read non-f32 field '{s}.{s}' as f32", .{
                    program.activeSystemId(),
                    component_id,
                    field_name,
                });
                return 0;
            },
        };
    }
    return 1;
}

pub fn writeF32ViewCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    raw_entities: ?[*]const u32,
    raw_entity_generations: ?[*]const u32,
    raw_component_rows: ?[*]const u32,
    entity_count: usize,
    raw_field_name: ?[*:0]const u8,
    raw_values: ?[*]const f32,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to bulk-write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (entity_count == 0) {
        return 1;
    }

    const entities = (raw_entities orelse return 0)[0..entity_count];
    const entity_generations = (raw_entity_generations orelse return 0)[0..entity_count];
    const component_rows = (raw_component_rows orelse return 0)[0..entity_count];
    const values = (raw_values orelse return 0)[0..entity_count];
    for (entities, entity_generations, component_rows, values) |entity_index, entity_generation, component_row_index, value| {
        if (!std.math.isFinite(value)) {
            program.setHostError("system '{s}' tried to bulk-write non-finite f32 value to '{s}.{s}'", .{
                program.activeSystemId(),
                component_id,
                field_name,
            });
            return 0;
        }
        world.setComponentFieldValueResolved(.{ .index = entity_index, .generation = entity_generation }, .{
            .table_index = component_table_index,
            .row_index = component_row_index,
        }, field_name, .{ .float = value }) catch |err| {
            program.setHostError("system '{s}' failed to bulk-write '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
    }
    return 1;
}

pub fn readVec3ViewCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    raw_entities: ?[*]const u32,
    raw_entity_generations: ?[*]const u32,
    raw_component_rows: ?[*]const u32,
    entity_count: usize,
    raw_field_name: ?[*:0]const u8,
    raw_out_values: ?[*]f32,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("system '{s}' tried to bulk-read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (entity_count == 0) {
        return 1;
    }

    const entities = (raw_entities orelse return 0)[0..entity_count];
    const entity_generations = (raw_entity_generations orelse return 0)[0..entity_count];
    const component_rows = (raw_component_rows orelse return 0)[0..entity_count];
    const out_values = (raw_out_values orelse return 0)[0 .. entity_count * 3];
    for (entities, entity_generations, component_rows, 0..) |entity_index, entity_generation, component_row_index, entity_offset| {
        const value = world.getComponentFieldValueResolved(.{ .index = entity_index, .generation = entity_generation }, .{
            .table_index = component_table_index,
            .row_index = component_row_index,
        }, field_name) catch |err| {
            program.setHostError("system '{s}' failed to bulk-read '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
        const vec3 = switch (value) {
            .vec3 => |payload| payload,
            else => {
                program.setHostError("system '{s}' tried to bulk-read non-vec3 field '{s}.{s}' as vec3", .{
                    program.activeSystemId(),
                    component_id,
                    field_name,
                });
                return 0;
            },
        };
        const value_offset = entity_offset * 3;
        out_values[value_offset + 0] = vec3[0];
        out_values[value_offset + 1] = vec3[1];
        out_values[value_offset + 2] = vec3[2];
    }
    return 1;
}

pub fn writeVec3ViewCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    raw_entities: ?[*]const u32,
    raw_entity_generations: ?[*]const u32,
    raw_component_rows: ?[*]const u32,
    entity_count: usize,
    raw_field_name: ?[*:0]const u8,
    raw_values: ?[*]const f32,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to bulk-write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (entity_count == 0) {
        return 1;
    }

    const entities = (raw_entities orelse return 0)[0..entity_count];
    const entity_generations = (raw_entity_generations orelse return 0)[0..entity_count];
    const component_rows = (raw_component_rows orelse return 0)[0..entity_count];
    const values = (raw_values orelse return 0)[0 .. entity_count * 3];
    for (entities, entity_generations, component_rows, 0..) |entity_index, entity_generation, component_row_index, entity_offset| {
        const value_offset = entity_offset * 3;
        const value = [3]f32{
            values[value_offset + 0],
            values[value_offset + 1],
            values[value_offset + 2],
        };
        if (!std.math.isFinite(value[0]) or !std.math.isFinite(value[1]) or !std.math.isFinite(value[2])) {
            program.setHostError("system '{s}' tried to bulk-write non-finite vec3 value to '{s}.{s}'", .{
                program.activeSystemId(),
                component_id,
                field_name,
            });
            return 0;
        }
        world.setComponentFieldValueResolved(.{ .index = entity_index, .generation = entity_generation }, .{
            .table_index = component_table_index,
            .row_index = component_row_index,
        }, field_name, .{ .vec3 = value }) catch |err| {
            program.setHostError("system '{s}' failed to bulk-write '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
    }
    return 1;
}

pub fn getVec3Callback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_out_value: ?[*]f32,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
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
    const value = world.getVec3(.{ .index = entity_index, .generation = entity_generation }, component_id, field_name) catch |err| {
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

pub fn setVec3Callback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_value: ?[*]const f32,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
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
    world.setVec3(.{ .index = entity_index, .generation = entity_generation }, component_id, field_name, .{
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

fn writeLuauFieldValue(out_value: *c.scrapbot_luau_field_value, value: runtime.ComponentValue) void {
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
            out_value.tag = c.SCRAPBOT_LUAU_FIELD_BOOLEAN;
            out_value.boolean_value = if (payload) 1 else 0;
        },
        .int => |payload| {
            out_value.tag = c.SCRAPBOT_LUAU_FIELD_INT;
            out_value.int_value = payload;
        },
        .float => |payload| {
            out_value.tag = c.SCRAPBOT_LUAU_FIELD_FLOAT;
            out_value.number_value = payload;
        },
        .vec3 => |payload| {
            out_value.tag = c.SCRAPBOT_LUAU_FIELD_VEC3;
            out_value.vec3_value = payload;
        },
        .string => |payload| {
            out_value.tag = c.SCRAPBOT_LUAU_FIELD_STRING;
            out_value.string_data = payload.ptr;
            out_value.string_len = payload.len;
        },
    }
}

pub fn getFieldCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_out_value: ?*c.scrapbot_luau_field_value,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
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

    const value = world.getComponentFieldValue(.{ .index = entity_index, .generation = entity_generation }, component_id, field_name) catch |err| {
        program.setHostError("system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    writeLuauFieldValue(out_value, value);
    return 1;
}

pub fn getFieldResolvedCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    component_row_index: u32,
    raw_field_name: ?[*:0]const u8,
    raw_out_value: ?*c.scrapbot_luau_field_value,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
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

    const value = world.getComponentFieldValueResolved(.{ .index = entity_index, .generation = entity_generation }, .{
        .table_index = component_table_index,
        .row_index = component_row_index,
    }, field_name) catch |err| {
        program.setHostError("system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    writeLuauFieldValue(out_value, value);
    return 1;
}

pub fn setFieldCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_value: ?*const c.scrapbot_luau_field_value,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
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

    const component_value = componentValueFromLuau(world, .{ .index = entity_index, .generation = entity_generation }, component_id, field_name, value) catch |err| {
        program.setHostError("system '{s}' failed to convert value for '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    world.setComponentFieldValue(.{ .index = entity_index, .generation = entity_generation }, component_id, field_name, component_value) catch |err| {
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

pub fn setFieldResolvedCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    component_row_index: u32,
    raw_field_name: ?[*:0]const u8,
    raw_value: ?*const c.scrapbot_luau_field_value,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
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

    const resolved = runtime.ResolvedComponentRow{
        .table_index = component_table_index,
        .row_index = component_row_index,
    };
    const entity = runtime.EntityHandle{ .index = entity_index, .generation = entity_generation };
    const component_value = componentValueFromLuauResolved(world, entity, resolved, field_name, value) catch |err| {
        program.setHostError("system '{s}' failed to convert value for '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    world.setComponentFieldValueResolved(entity, resolved, field_name, component_value) catch |err| {
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

pub fn spawnEntityCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_id: ?[*:0]const u8,
    raw_name: ?[*:0]const u8,
    raw_out_entity: ?*u32,
    raw_out_entity_generation: ?*u32,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const id = std.mem.span(raw_id orelse return 0);
    const name = std.mem.span(raw_name orelse return 0);
    const out_entity = raw_out_entity orelse return 0;
    const out_entity_generation = raw_out_entity_generation orelse return 0;

    const entity = world.createEntity(id, name) catch |err| {
        program.setHostError("system '{s}' failed to spawn entity '{s}': {s}", .{
            program.activeSystemId(),
            id,
            @errorName(err),
        });
        return 0;
    };
    out_entity.* = entity.index;
    out_entity_generation.* = entity.generation;
    program.immediate_script_spawns.append(program.allocator, entity) catch {
        _ = world.removeEntity(entity) catch {};
        program.setHostError("system '{s}' failed to record spawned entity '{s}': {s}", .{
            program.activeSystemId(),
            id,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    return 1;
}

pub fn despawnEntityCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const entity = runtime.EntityHandle{ .index = entity_index, .generation = entity_generation };
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

    program.queued_script_commands.append(program.allocator, .{ .despawn_entity = entity }) catch {
        program.setHostError("system '{s}' failed to queue despawn entity {d}: {s}", .{
            program.activeSystemId(),
            entity_index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    return 1;
}

pub fn addComponentCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    raw_fields: ?[*]const c.scrapbot_luau_component_field_value,
    field_count: usize,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
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
    const entity = runtime.EntityHandle{ .index = entity_index, .generation = entity_generation };
    _ = world.entity(entity) catch |err| {
        program.setHostError("system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(err),
        });
        return 0;
    };
    const raw_slice = if (field_count == 0) &[_]c.scrapbot_luau_component_field_value{} else (raw_fields orelse return 0)[0..field_count];
    const fields = program.allocator.alloc(script.QueuedComponentFieldValue, field_count) catch {
        program.setHostError("system '{s}' failed to allocate component fields for '{s}'", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    };
    var initialized_fields: usize = 0;
    var fields_owned = true;
    defer {
        if (fields_owned) {
            for (fields[0..initialized_fields]) |*field| {
                field.deinit(program.allocator);
            }
            program.allocator.free(fields);
        }
    }

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
        const component_value = componentValueFromLuauType(field_definition.value_type, &raw_field.value) catch |err| {
            program.setHostError("system '{s}' failed to convert value for '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
        const owned_field_name = program.allocator.dupe(u8, field_name) catch {
            program.setHostError("system '{s}' failed to queue field name for '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(error.OutOfMemory),
            });
            return 0;
        };
        fields[index] = .{
            .name = owned_field_name,
            .value = cloneComponentValue(program.allocator, component_value) catch |err| {
                program.allocator.free(owned_field_name);
                program.setHostError("system '{s}' failed to queue value for '{s}.{s}': {s}", .{
                    program.activeSystemId(),
                    component_id,
                    field_name,
                    @errorName(err),
                });
                return 0;
            },
        };
        initialized_fields += 1;
    }

    const owned_component_id = program.allocator.dupe(u8, component_id) catch {
        program.setHostError("system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    var component_id_owned = true;
    defer {
        if (component_id_owned) {
            program.allocator.free(owned_component_id);
        }
    }

    program.queued_script_commands.append(program.allocator, .{ .add_component = .{
        .entity = entity,
        .component_id = owned_component_id,
        .fields = fields,
    } }) catch {
        program.setHostError("system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    fields_owned = false;
    component_id_owned = false;
    return 1;
}

pub fn removeComponentCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
) callconv(.c) c_int {
    const program: *script.Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to remove component '{s}' without declaring it in writes", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    }
    const entity = runtime.EntityHandle{ .index = entity_index, .generation = entity_generation };
    _ = world.entity(entity) catch |err| {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(err),
        });
        return 0;
    };
    const owned_component_id = program.allocator.dupe(u8, component_id) catch {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    var component_id_owned = true;
    defer {
        if (component_id_owned) {
            program.allocator.free(owned_component_id);
        }
    }
    program.queued_script_commands.append(program.allocator, .{ .remove_component = .{
        .entity = entity,
        .component_id = owned_component_id,
    } }) catch {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    component_id_owned = false;
    return 1;
}

fn queueDespawnEntity(program: *script.Program, world: *runtime.World, entity: runtime.EntityHandle) c_int {
    _ = world.entity(entity) catch |err| {
        program.setHostError("system '{s}' failed to despawn entity {d}: {s}", .{
            program.activeSystemId(),
            entity.index,
            @errorName(err),
        });
        return 0;
    };

    var components = world.entityComponents(entity) catch |err| {
        program.setHostError("system '{s}' failed to inspect entity {d}: {s}", .{
            program.activeSystemId(),
            entity.index,
            @errorName(err),
        });
        return 0;
    };
    while (components.next()) |component_id| {
        if (!program.activeSystemAllowsWrite(component_id)) {
            program.setHostError("system '{s}' tried to despawn entity {d} without declaring write access to '{s}'", .{
                program.activeSystemId(),
                entity.index,
                component_id,
            });
            return 0;
        }
    }

    program.queued_script_commands.append(program.allocator, .{ .despawn_entity = entity }) catch {
        program.setHostError("system '{s}' failed to queue despawn entity {d}: {s}", .{
            program.activeSystemId(),
            entity.index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    return 1;
}

fn queueRemoveComponent(program: *script.Program, world: *runtime.World, entity: runtime.EntityHandle, component_id: []const u8) c_int {
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to remove component '{s}' without declaring it in writes", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    }
    _ = world.entity(entity) catch |err| {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(err),
        });
        return 0;
    };
    const owned_component_id = program.allocator.dupe(u8, component_id) catch {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    var component_id_owned = true;
    defer {
        if (component_id_owned) {
            program.allocator.free(owned_component_id);
        }
    }
    program.queued_script_commands.append(program.allocator, .{ .remove_component = .{
        .entity = entity,
        .component_id = owned_component_id,
    } }) catch {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    component_id_owned = false;
    return 1;
}

fn componentValueFromLuau(
    world: *runtime.World,
    entity: runtime.EntityHandle,
    component_id: []const u8,
    field_name: []const u8,
    value: *const c.scrapbot_luau_field_value,
) !runtime.ComponentValue {
    return switch (value.tag) {
        c.SCRAPBOT_LUAU_FIELD_BOOLEAN => .{ .boolean = value.boolean_value != 0 },
        c.SCRAPBOT_LUAU_FIELD_STRING => .{ .string = stringFromLuau(value) },
        c.SCRAPBOT_LUAU_FIELD_VEC3 => blk: {
            const vec3 = value.vec3_value;
            if (!std.math.isFinite(vec3[0]) or !std.math.isFinite(vec3[1]) or !std.math.isFinite(vec3[2])) {
                return script.ScriptError.InvalidScript;
            }
            break :blk .{ .vec3 = .{ vec3[0], vec3[1], vec3[2] } };
        },
        c.SCRAPBOT_LUAU_FIELD_NUMBER => blk: {
            if (!std.math.isFinite(value.number_value)) {
                return script.ScriptError.InvalidScript;
            }

            const current = try world.getComponentFieldValue(entity, component_id, field_name);
            break :blk switch (current) {
                .int => .{ .int = try i32FromLuauNumber(value.number_value) },
                .float => .{ .float = try f32FromLuauNumber(value.number_value) },
                else => return script.ScriptError.InvalidScript,
            };
        },
        else => script.ScriptError.InvalidScript,
    };
}

fn componentValueFromLuauResolved(
    world: *runtime.World,
    entity: runtime.EntityHandle,
    resolved: runtime.ResolvedComponentRow,
    field_name: []const u8,
    value: *const c.scrapbot_luau_field_value,
) !runtime.ComponentValue {
    return switch (value.tag) {
        c.SCRAPBOT_LUAU_FIELD_BOOLEAN => .{ .boolean = value.boolean_value != 0 },
        c.SCRAPBOT_LUAU_FIELD_STRING => .{ .string = stringFromLuau(value) },
        c.SCRAPBOT_LUAU_FIELD_VEC3 => blk: {
            const vec3 = value.vec3_value;
            if (!std.math.isFinite(vec3[0]) or !std.math.isFinite(vec3[1]) or !std.math.isFinite(vec3[2])) {
                return script.ScriptError.InvalidScript;
            }
            break :blk .{ .vec3 = .{ vec3[0], vec3[1], vec3[2] } };
        },
        c.SCRAPBOT_LUAU_FIELD_NUMBER => blk: {
            if (!std.math.isFinite(value.number_value)) {
                return script.ScriptError.InvalidScript;
            }

            const current = try world.getComponentFieldValueResolved(entity, resolved, field_name);
            break :blk switch (current) {
                .int => .{ .int = try i32FromLuauNumber(value.number_value) },
                .float => .{ .float = try f32FromLuauNumber(value.number_value) },
                else => return script.ScriptError.InvalidScript,
            };
        },
        else => script.ScriptError.InvalidScript,
    };
}

fn componentValueFromLuauType(field_type: runtime.FieldType, value: *const c.scrapbot_luau_field_value) !runtime.ComponentValue {
    return switch (field_type) {
        .boolean => switch (value.tag) {
            c.SCRAPBOT_LUAU_FIELD_BOOLEAN => .{ .boolean = value.boolean_value != 0 },
            else => script.ScriptError.InvalidScript,
        },
        .string => switch (value.tag) {
            c.SCRAPBOT_LUAU_FIELD_STRING => .{ .string = stringFromLuau(value) },
            else => script.ScriptError.InvalidScript,
        },
        .vec3 => switch (value.tag) {
            c.SCRAPBOT_LUAU_FIELD_VEC3 => blk: {
                const vec3 = value.vec3_value;
                if (!std.math.isFinite(vec3[0]) or !std.math.isFinite(vec3[1]) or !std.math.isFinite(vec3[2])) {
                    return script.ScriptError.InvalidScript;
                }
                break :blk .{ .vec3 = .{ vec3[0], vec3[1], vec3[2] } };
            },
            else => script.ScriptError.InvalidScript,
        },
        .int => switch (value.tag) {
            c.SCRAPBOT_LUAU_FIELD_NUMBER => .{ .int = try i32FromLuauNumber(value.number_value) },
            c.SCRAPBOT_LUAU_FIELD_INT => .{ .int = value.int_value },
            else => script.ScriptError.InvalidScript,
        },
        .float => switch (value.tag) {
            c.SCRAPBOT_LUAU_FIELD_NUMBER => .{ .float = try f32FromLuauNumber(value.number_value) },
            c.SCRAPBOT_LUAU_FIELD_FLOAT => .{ .float = @floatCast(value.number_value) },
            else => script.ScriptError.InvalidScript,
        },
    };
}

fn componentValueFromNativeType(field_type: runtime.FieldType, value: native_api.FieldValue) !runtime.ComponentValue {
    return switch (field_type) {
        .boolean => switch (value.field_type) {
            .boolean => .{ .boolean = value.boolean_value != 0 },
            else => script.ScriptError.InvalidScript,
        },
        .int => switch (value.field_type) {
            .int => .{ .int = value.int_value },
            else => script.ScriptError.InvalidScript,
        },
        .float => switch (value.field_type) {
            .float => blk: {
                if (!std.math.isFinite(value.float_value)) {
                    return script.ScriptError.InvalidScript;
                }
                break :blk .{ .float = value.float_value };
            },
            else => script.ScriptError.InvalidScript,
        },
        .vec3 => switch (value.field_type) {
            .vec3 => blk: {
                const vec3 = value.vec3_value;
                if (!std.math.isFinite(vec3.x) or !std.math.isFinite(vec3.y) or !std.math.isFinite(vec3.z)) {
                    return script.ScriptError.InvalidScript;
                }
                break :blk .{ .vec3 = .{ vec3.x, vec3.y, vec3.z } };
            },
            else => script.ScriptError.InvalidScript,
        },
        .string => switch (value.field_type) {
            .string => .{ .string = value.string_value.asSlice() orelse return script.ScriptError.InvalidScript },
            else => script.ScriptError.InvalidScript,
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

fn stringFromLuau(value: *const c.scrapbot_luau_field_value) []const u8 {
    if (value.string_len == 0) {
        return "";
    }
    return value.string_data[0..value.string_len];
}

pub fn cloneComponentValue(allocator: std.mem.Allocator, value: runtime.ComponentValue) !runtime.ComponentValue {
    return switch (value) {
        .boolean => |payload| .{ .boolean = payload },
        .int => |payload| .{ .int = payload },
        .float => |payload| .{ .float = payload },
        .vec3 => |payload| .{ .vec3 = payload },
        .string => |payload| .{ .string = try allocator.dupe(u8, payload) },
    };
}

fn i32FromLuauNumber(value: f64) !i32 {
    if (!std.math.isFinite(value)) {
        return script.ScriptError.InvalidScript;
    }
    const min = @as(f64, @floatFromInt(std.math.minInt(i32)));
    const max = @as(f64, @floatFromInt(std.math.maxInt(i32)));
    if (value < min or value > max or value != @floor(value)) {
        return script.ScriptError.InvalidScript;
    }
    return @intFromFloat(value);
}

fn f32FromLuauNumber(value: f64) !f32 {
    if (!std.math.isFinite(value)) {
        return script.ScriptError.InvalidScript;
    }
    const narrowed: f32 = @floatCast(value);
    if (!std.math.isFinite(narrowed)) {
        return script.ScriptError.InvalidScript;
    }
    return narrowed;
}
