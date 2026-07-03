const std = @import("std");

pub const FieldType = enum(u32) {
    boolean,
    int,
    float,
    vec3,
    string,
};

pub const SystemPhase = enum(u32) {
    startup,
    update,
    fixed_update,
    render,
};

pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn addScaled(self: Vec3, other: Vec3, scale: f32) Vec3 {
        return .{
            .x = self.x + other.x * scale,
            .y = self.y + other.y * scale,
            .z = self.z + other.z * scale,
        };
    }
};

pub const Entity = extern struct {
    index: u32,
    generation: u32,
};

pub const ComponentField = extern struct {
    name: [*:0]const u8,
    field_type: FieldType,
};

pub const ComponentDefinition = extern struct {
    id: [*:0]const u8,
    version: u32 = 1,
    fields: ?[*]const ComponentField = null,
    field_count: usize = 0,
};

pub const StringList = extern struct {
    items: ?[*]const [*:0]const u8 = null,
    len: usize = 0,
};

pub const SystemContext = extern struct {
    world: ?*anyopaque,
    api: *const SystemApi,
    delta_seconds: f32,
    system_id: [*:0]const u8,
};

pub const SystemRunFn = *const fn (*SystemContext) callconv(.c) c_int;

pub const SystemDefinition = extern struct {
    id: [*:0]const u8,
    phase: SystemPhase = .update,
    reads: StringList = .{},
    writes: StringList = .{},
    before: StringList = .{},
    after: StringList = .{},
    run: SystemRunFn,
};

pub const RegisterComponentFn = *const fn (?*anyopaque, *const ComponentDefinition) callconv(.c) c_int;
pub const RegisterSystemFn = *const fn (?*anyopaque, *const SystemDefinition) callconv(.c) c_int;

pub const RegisterApi = extern struct {
    context: ?*anyopaque,
    register_component: RegisterComponentFn,
    register_system: RegisterSystemFn,
};

pub const RegisterFn = *const fn (*const RegisterApi) callconv(.c) c_int;

pub const QueryNextFn = *const fn (
    ?*anyopaque,
    ?[*]const [*:0]const u8,
    usize,
    *usize,
    *Entity,
) callconv(.c) c_int;
pub const GetVec3Fn = *const fn (?*anyopaque, Entity, [*:0]const u8, [*:0]const u8, *Vec3) callconv(.c) c_int;
pub const SetVec3Fn = *const fn (?*anyopaque, Entity, [*:0]const u8, [*:0]const u8, Vec3) callconv(.c) c_int;
pub const GetF32Fn = *const fn (?*anyopaque, Entity, [*:0]const u8, [*:0]const u8, *f32) callconv(.c) c_int;
pub const SetF32Fn = *const fn (?*anyopaque, Entity, [*:0]const u8, [*:0]const u8, f32) callconv(.c) c_int;
pub const HostErrorFn = *const fn (?*anyopaque) callconv(.c) ?[*:0]const u8;

pub const SystemApi = extern struct {
    query_next: QueryNextFn,
    get_vec3: GetVec3Fn,
    set_vec3: SetVec3Fn,
    get_f32: GetF32Fn,
    set_f32: SetF32Fn,
    host_error: HostErrorFn,
};

pub const RegisterError = error{NativeRegistrationFailed};
pub const HostError = error{NativeHostError};

pub const ComponentSpec = struct {
    id: [*:0]const u8,
    version: u32 = 1,
    fields: []const ComponentField = &.{},
};

pub const SystemSpec = struct {
    id: [*:0]const u8,
    phase: SystemPhase = .update,
    reads: []const [*:0]const u8 = &.{},
    writes: []const [*:0]const u8 = &.{},
    before: []const [*:0]const u8 = &.{},
    after: []const [*:0]const u8 = &.{},
    run: SystemRunFn,
};

pub fn registerComponent(api: *const RegisterApi, spec: ComponentSpec) RegisterError!void {
    var definition = ComponentDefinition{
        .id = spec.id,
        .version = spec.version,
        .fields = if (spec.fields.len == 0) null else spec.fields.ptr,
        .field_count = spec.fields.len,
    };
    if (api.register_component(api.context, &definition) == 0) {
        return error.NativeRegistrationFailed;
    }
}

pub fn registerSystem(api: *const RegisterApi, spec: SystemSpec) RegisterError!void {
    var definition = SystemDefinition{
        .id = spec.id,
        .phase = spec.phase,
        .reads = stringList(spec.reads),
        .writes = stringList(spec.writes),
        .before = stringList(spec.before),
        .after = stringList(spec.after),
        .run = spec.run,
    };
    if (api.register_system(api.context, &definition) == 0) {
        return error.NativeRegistrationFailed;
    }
}

pub fn queryNext(context: *SystemContext, component_ids: []const [*:0]const u8, cursor: *usize) HostError!?Entity {
    var entity: Entity = undefined;
    const status = context.api.query_next(context.world, if (component_ids.len == 0) null else component_ids.ptr, component_ids.len, cursor, &entity);
    return switch (status) {
        1 => entity,
        0 => null,
        else => error.NativeHostError,
    };
}

pub fn getVec3(context: *SystemContext, entity: Entity, component_id: [*:0]const u8, field_name: [*:0]const u8) HostError!Vec3 {
    var value: Vec3 = undefined;
    if (context.api.get_vec3(context.world, entity, component_id, field_name, &value) == 0) {
        return error.NativeHostError;
    }
    return value;
}

pub fn setVec3(context: *SystemContext, entity: Entity, component_id: [*:0]const u8, field_name: [*:0]const u8, value: Vec3) HostError!void {
    if (context.api.set_vec3(context.world, entity, component_id, field_name, value) == 0) {
        return error.NativeHostError;
    }
}

pub fn getF32(context: *SystemContext, entity: Entity, component_id: [*:0]const u8, field_name: [*:0]const u8) HostError!f32 {
    var value: f32 = undefined;
    if (context.api.get_f32(context.world, entity, component_id, field_name, &value) == 0) {
        return error.NativeHostError;
    }
    return value;
}

pub fn setF32(context: *SystemContext, entity: Entity, component_id: [*:0]const u8, field_name: [*:0]const u8, value: f32) HostError!void {
    if (context.api.set_f32(context.world, entity, component_id, field_name, value) == 0) {
        return error.NativeHostError;
    }
}

pub fn hostError(context: *SystemContext) ?[:0]const u8 {
    const message = context.api.host_error(context.world) orelse return null;
    return std.mem.span(message);
}

fn stringList(values: []const [*:0]const u8) StringList {
    return .{
        .items = if (values.len == 0) null else values.ptr,
        .len = values.len,
    };
}
