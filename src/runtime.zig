const std = @import("std");

pub const WorldError = error{
    DuplicateEntityId,
    InvalidEntity,
};

pub const TypeIdError = error{
    InvalidTypeId,
    ReservedTypeId,
};

pub const RegistryError = TypeIdError || error{
    InvalidFieldName,
    DuplicateComponentField,
    DuplicateComponentType,
    DuplicateSystemType,
    UnknownComponentType,
    DuplicateSystemAccess,
};

const engine_namespace = "machina";

pub const FieldType = enum {
    boolean,
    int,
    float,
    string,
};

pub const ComponentFieldDefinition = struct {
    name: []const u8,
    value_type: FieldType,
};

pub const ComponentDefinition = struct {
    id: []const u8,
    version: u32 = 1,
    fields: []const ComponentFieldDefinition = &.{},
};

pub const SystemDefinition = struct {
    id: []const u8,
    reads: []const []const u8 = &.{},
    writes: []const []const u8 = &.{},
    before: []const []const u8 = &.{},
    after: []const []const u8 = &.{},
};

const RegistrationOwner = enum {
    engine,
    external,
};

pub const ComponentRegistry = struct {
    allocator: std.mem.Allocator,
    components: std.ArrayList(ComponentDefinition) = .empty,
    systems: std.ArrayList(SystemDefinition) = .empty,

    pub fn init(allocator: std.mem.Allocator) ComponentRegistry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ComponentRegistry) void {
        const allocator = self.allocator;
        for (self.systems.items) |system| {
            self.freeSystemDefinition(system);
        }
        self.systems.deinit(allocator);

        for (self.components.items) |component| {
            self.freeComponentDefinition(component);
        }
        self.components.deinit(allocator);

        self.* = .{ .allocator = allocator };
    }

    pub fn registerComponent(self: *ComponentRegistry, definition: ComponentDefinition) !void {
        return self.registerComponentAs(.external, definition);
    }

    pub fn registerEngineComponent(self: *ComponentRegistry, definition: ComponentDefinition) !void {
        return self.registerComponentAs(.engine, definition);
    }

    pub fn registerSystem(self: *ComponentRegistry, definition: SystemDefinition) !void {
        return self.registerSystemAs(.external, definition);
    }

    pub fn registerEngineSystem(self: *ComponentRegistry, definition: SystemDefinition) !void {
        return self.registerSystemAs(.engine, definition);
    }

    pub fn componentCount(self: ComponentRegistry) usize {
        return self.components.items.len;
    }

    pub fn systemCount(self: ComponentRegistry) usize {
        return self.systems.items.len;
    }

    pub fn findComponent(self: ComponentRegistry, id: []const u8) ?*const ComponentDefinition {
        for (self.components.items) |*component| {
            if (std.mem.eql(u8, component.id, id)) {
                return component;
            }
        }
        return null;
    }

    pub fn findSystem(self: ComponentRegistry, id: []const u8) ?*const SystemDefinition {
        for (self.systems.items) |*system| {
            if (std.mem.eql(u8, system.id, id)) {
                return system;
            }
        }
        return null;
    }

    fn registerComponentAs(self: *ComponentRegistry, owner: RegistrationOwner, definition: ComponentDefinition) !void {
        try validateTypeIdForOwner(definition.id, owner);
        for (definition.fields, 0..) |field, index| {
            try validateFieldName(field.name);
            for (definition.fields[0..index]) |prior_field| {
                if (std.mem.eql(u8, field.name, prior_field.name)) {
                    return RegistryError.DuplicateComponentField;
                }
            }
        }

        if (self.findComponent(definition.id)) |existing| {
            if (componentDefinitionsEqual(existing.*, definition)) {
                return;
            }
            return RegistryError.DuplicateComponentType;
        }

        const owned = try self.copyComponentDefinition(definition);
        errdefer self.freeComponentDefinition(owned);
        try self.components.append(self.allocator, owned);
    }

    fn registerSystemAs(self: *ComponentRegistry, owner: RegistrationOwner, definition: SystemDefinition) !void {
        try validateTypeIdForOwner(definition.id, owner);
        try self.validateSystemAccess(definition);

        if (self.findSystem(definition.id)) |existing| {
            if (systemDefinitionsEqual(existing.*, definition)) {
                return;
            }
            return RegistryError.DuplicateSystemType;
        }

        const owned = try self.copySystemDefinition(definition);
        errdefer self.freeSystemDefinition(owned);
        try self.systems.append(self.allocator, owned);
    }

    fn validateSystemAccess(self: ComponentRegistry, definition: SystemDefinition) !void {
        for (definition.reads) |component_id| {
            try validateTypeId(component_id);
            if (self.findComponent(component_id) == null) {
                return RegistryError.UnknownComponentType;
            }
            if (countString(definition.reads, component_id) > 1 or containsString(definition.writes, component_id)) {
                return RegistryError.DuplicateSystemAccess;
            }
        }

        for (definition.writes) |component_id| {
            try validateTypeId(component_id);
            if (self.findComponent(component_id) == null) {
                return RegistryError.UnknownComponentType;
            }
            if (countString(definition.writes, component_id) > 1) {
                return RegistryError.DuplicateSystemAccess;
            }
        }

        for (definition.before) |system_id| {
            try validateTypeId(system_id);
        }
        for (definition.after) |system_id| {
            try validateTypeId(system_id);
        }
    }

    fn copyComponentDefinition(self: ComponentRegistry, definition: ComponentDefinition) !ComponentDefinition {
        const id = try self.allocator.dupe(u8, definition.id);
        errdefer self.allocator.free(id);

        const fields = try self.allocator.alloc(ComponentFieldDefinition, definition.fields.len);
        errdefer self.allocator.free(fields);

        var field_count: usize = 0;
        errdefer {
            for (fields[0..field_count]) |field| {
                self.allocator.free(field.name);
            }
        }

        for (definition.fields, 0..) |field, index| {
            fields[index] = .{
                .name = try self.allocator.dupe(u8, field.name),
                .value_type = field.value_type,
            };
            field_count += 1;
        }

        return .{
            .id = id,
            .version = definition.version,
            .fields = fields,
        };
    }

    fn copySystemDefinition(self: ComponentRegistry, definition: SystemDefinition) !SystemDefinition {
        const id = try self.allocator.dupe(u8, definition.id);
        errdefer self.allocator.free(id);

        const reads = try self.copyStringList(definition.reads);
        errdefer self.freeStringList(reads);
        const writes = try self.copyStringList(definition.writes);
        errdefer self.freeStringList(writes);
        const before = try self.copyStringList(definition.before);
        errdefer self.freeStringList(before);
        const after = try self.copyStringList(definition.after);

        return .{
            .id = id,
            .reads = reads,
            .writes = writes,
            .before = before,
            .after = after,
        };
    }

    fn copyStringList(self: ComponentRegistry, values: []const []const u8) ![]const []const u8 {
        const copied = try self.allocator.alloc([]const u8, values.len);
        errdefer self.allocator.free(copied);

        var count: usize = 0;
        errdefer {
            for (copied[0..count]) |value| {
                self.allocator.free(value);
            }
        }

        for (values, 0..) |value, index| {
            copied[index] = try self.allocator.dupe(u8, value);
            count += 1;
        }

        return copied;
    }

    fn freeComponentDefinition(self: ComponentRegistry, definition: ComponentDefinition) void {
        self.allocator.free(definition.id);
        for (definition.fields) |field| {
            self.allocator.free(field.name);
        }
        self.allocator.free(definition.fields);
    }

    fn freeSystemDefinition(self: ComponentRegistry, definition: SystemDefinition) void {
        self.allocator.free(definition.id);
        self.freeStringList(definition.reads);
        self.freeStringList(definition.writes);
        self.freeStringList(definition.before);
        self.freeStringList(definition.after);
    }

    fn freeStringList(self: ComponentRegistry, values: []const []const u8) void {
        for (values) |value| {
            self.allocator.free(value);
        }
        self.allocator.free(values);
    }
};

pub const EntityHandle = struct {
    index: u32,
};

pub const Entity = struct {
    id: []const u8,
    name: []const u8,
};

pub const Transform = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    rotation: [3]f32 = .{ 0.0, 0.0, 0.0 },
    scale: [3]f32 = .{ 1.0, 1.0, 1.0 },
};

pub const CubeRenderer = struct {
    color: [3]f32 = .{ 0.0, 0.56, 1.0 },
};

pub const Spin = struct {
    angular_velocity: [3]f32 = .{ 0.62, 1.0, 0.0 },
};

pub const RenderableCube = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    position: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
    color: [3]f32,
    spin: [3]f32,
};

pub const World = struct {
    allocator: std.mem.Allocator,
    entities: std.ArrayList(Entity) = .empty,
    transforms: std.ArrayList(?Transform) = .empty,
    cube_renderers: std.ArrayList(?CubeRenderer) = .empty,
    spins: std.ArrayList(?Spin) = .empty,

    pub fn init(allocator: std.mem.Allocator) World {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *World) void {
        const allocator = self.allocator;
        for (self.entities.items) |stored_entity| {
            allocator.free(stored_entity.id);
            allocator.free(stored_entity.name);
        }
        self.spins.deinit(allocator);
        self.cube_renderers.deinit(allocator);
        self.transforms.deinit(allocator);
        self.entities.deinit(allocator);
        self.* = .{ .allocator = allocator };
    }

    pub fn createEntity(self: *World, id: []const u8, name: []const u8) !EntityHandle {
        if (self.findEntityById(id) != null) {
            return WorldError.DuplicateEntityId;
        }

        const owned_id = try self.allocator.dupe(u8, id);
        errdefer self.allocator.free(owned_id);
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        const handle = EntityHandle{ .index = @intCast(self.entities.items.len) };
        try self.entities.append(self.allocator, .{
            .id = owned_id,
            .name = owned_name,
        });
        errdefer _ = self.entities.pop();

        try self.transforms.append(self.allocator, null);
        errdefer _ = self.transforms.pop();
        try self.cube_renderers.append(self.allocator, null);
        errdefer _ = self.cube_renderers.pop();
        try self.spins.append(self.allocator, null);

        return handle;
    }

    pub fn entityCount(self: World) usize {
        return self.entities.items.len;
    }

    pub fn entity(self: World, handle: EntityHandle) WorldError!Entity {
        const index = handle.index;
        if (index >= self.entities.items.len) {
            return WorldError.InvalidEntity;
        }
        return self.entities.items[index];
    }

    pub fn findEntityById(self: World, id: []const u8) ?EntityHandle {
        for (self.entities.items, 0..) |stored_entity, index| {
            if (std.mem.eql(u8, stored_entity.id, id)) {
                return .{ .index = @intCast(index) };
            }
        }
        return null;
    }

    pub fn setTransform(self: *World, handle: EntityHandle, transform: Transform) WorldError!void {
        const index = try self.componentIndex(handle);
        self.transforms.items[index] = transform;
    }

    pub fn setCubeRenderer(self: *World, handle: EntityHandle, cube_renderer: CubeRenderer) WorldError!void {
        const index = try self.componentIndex(handle);
        self.cube_renderers.items[index] = cube_renderer;
    }

    pub fn setSpin(self: *World, handle: EntityHandle, spin: Spin) WorldError!void {
        const index = try self.componentIndex(handle);
        self.spins.items[index] = spin;
    }

    pub fn renderableCubeCount(self: World) usize {
        var count: usize = 0;
        for (self.entities.items, 0..) |_, index| {
            if (self.transforms.items[index] != null and self.cube_renderers.items[index] != null) {
                count += 1;
            }
        }
        return count;
    }

    pub fn renderableCubeAt(self: World, render_index: usize) ?RenderableCube {
        var found: usize = 0;
        for (self.entities.items, 0..) |stored_entity, index| {
            const transform = self.transforms.items[index] orelse continue;
            const cube_renderer = self.cube_renderers.items[index] orelse continue;
            if (found == render_index) {
                const spin = self.spins.items[index] orelse Spin{};
                return .{
                    .entity = .{ .index = @intCast(index) },
                    .id = stored_entity.id,
                    .name = stored_entity.name,
                    .position = transform.position,
                    .rotation = transform.rotation,
                    .scale = transform.scale,
                    .color = cube_renderer.color,
                    .spin = spin.angular_velocity,
                };
            }
            found += 1;
        }
        return null;
    }

    pub fn renderableCubes(self: *const World) RenderableCubeIterator {
        return .{ .world = self };
    }

    fn componentIndex(self: World, handle: EntityHandle) WorldError!usize {
        const index = handle.index;
        if (index >= self.entities.items.len) {
            return WorldError.InvalidEntity;
        }
        return index;
    }
};

pub const RenderableCubeIterator = struct {
    world: *const World,
    index: usize = 0,

    pub fn next(self: *RenderableCubeIterator) ?RenderableCube {
        const count = self.world.renderableCubeCount();
        while (self.index < count) : (self.index += 1) {
            const cube = self.world.renderableCubeAt(self.index) orelse continue;
            self.index += 1;
            return cube;
        }
        return null;
    }
};

pub fn validateTypeId(id: []const u8) TypeIdError!void {
    var segment_count: usize = 0;
    var segments = std.mem.splitScalar(u8, id, '.');
    while (segments.next()) |segment| {
        try validateIdentifierSegment(segment);
        segment_count += 1;
    }

    if (segment_count < 2) {
        return TypeIdError.InvalidTypeId;
    }
}

pub fn validateExternalTypeId(id: []const u8) TypeIdError!void {
    try validateTypeIdForOwner(id, .external);
}

fn validateTypeIdForOwner(id: []const u8, owner: RegistrationOwner) TypeIdError!void {
    try validateTypeId(id);
    if (owner == .external and isEngineTypeId(id)) {
        return TypeIdError.ReservedTypeId;
    }
}

fn validateFieldName(name: []const u8) RegistryError!void {
    validateIdentifierSegment(name) catch return RegistryError.InvalidFieldName;
}

fn validateIdentifierSegment(segment: []const u8) TypeIdError!void {
    if (segment.len == 0 or !isLowerAlpha(segment[0])) {
        return TypeIdError.InvalidTypeId;
    }

    for (segment[1..]) |byte| {
        if (!isLowerAlpha(byte) and !std.ascii.isDigit(byte) and byte != '_') {
            return TypeIdError.InvalidTypeId;
        }
    }
}

fn isEngineTypeId(id: []const u8) bool {
    if (std.mem.eql(u8, id, engine_namespace)) {
        return true;
    }
    return std.mem.startsWith(u8, id, engine_namespace ++ ".");
}

fn isLowerAlpha(byte: u8) bool {
    return byte >= 'a' and byte <= 'z';
}

fn componentDefinitionsEqual(left: ComponentDefinition, right: ComponentDefinition) bool {
    if (!std.mem.eql(u8, left.id, right.id) or left.version != right.version or left.fields.len != right.fields.len) {
        return false;
    }

    for (left.fields, right.fields) |left_field, right_field| {
        if (!std.mem.eql(u8, left_field.name, right_field.name) or left_field.value_type != right_field.value_type) {
            return false;
        }
    }

    return true;
}

fn systemDefinitionsEqual(left: SystemDefinition, right: SystemDefinition) bool {
    return std.mem.eql(u8, left.id, right.id) and
        stringListsEqual(left.reads, right.reads) and
        stringListsEqual(left.writes, right.writes) and
        stringListsEqual(left.before, right.before) and
        stringListsEqual(left.after, right.after);
}

fn stringListsEqual(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) {
        return false;
    }
    for (left, right) |left_value, right_value| {
        if (!std.mem.eql(u8, left_value, right_value)) {
            return false;
        }
    }
    return true;
}

fn containsString(values: []const []const u8, needle: []const u8) bool {
    return countString(values, needle) > 0;
}

fn countString(values: []const []const u8, needle: []const u8) usize {
    var count: usize = 0;
    for (values) |value| {
        if (std.mem.eql(u8, value, needle)) {
            count += 1;
        }
    }
    return count;
}

test "world stores stable entity ids and components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("entity-1", "Player");
    try world.setTransform(entity, .{ .position = .{ 1.0, 2.0, 3.0 } });
    try world.setCubeRenderer(entity, .{ .color = .{ 1.0, 0.0, 0.0 } });

    try std.testing.expectEqual(@as(usize, 1), world.entityCount());
    try std.testing.expectEqual(@as(usize, 1), world.renderableCubeCount());

    const found = world.findEntityById("entity-1") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(entity.index, found.index);

    const cube = world.renderableCubeAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("entity-1", cube.id);
    try std.testing.expectEqual(@as(f32, 2.0), cube.position[1]);
    try std.testing.expectEqual(@as(f32, 1.0), cube.color[0]);
}

test "world rejects duplicate entity ids" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    _ = try world.createEntity("entity-1", "One");
    try std.testing.expectError(WorldError.DuplicateEntityId, world.createEntity("entity-1", "Two"));
}

test "type ids require explicit dotted lowercase namespaces" {
    try validateExternalTypeId("com.acme.health");
    try validateExternalTypeId("game.health");
    try validateExternalTypeId("local_project.hit_points");

    try std.testing.expectError(TypeIdError.InvalidTypeId, validateExternalTypeId("health"));
    try std.testing.expectError(TypeIdError.InvalidTypeId, validateExternalTypeId("Com.Acme.Health"));
    try std.testing.expectError(TypeIdError.InvalidTypeId, validateExternalTypeId("com.acme-health"));
    try std.testing.expectError(TypeIdError.InvalidTypeId, validateExternalTypeId("com..health"));
    try std.testing.expectError(TypeIdError.ReservedTypeId, validateExternalTypeId("machina.transform"));
}

test "component registry allows reload-identical components and rejects incompatible duplicates" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const fields = [_]ComponentFieldDefinition{
        .{ .name = "current", .value_type = .float },
        .{ .name = "max", .value_type = .float },
    };
    try registry.registerComponent(.{
        .id = "com.acme.health",
        .version = 1,
        .fields = &fields,
    });
    try registry.registerComponent(.{
        .id = "com.acme.health",
        .version = 1,
        .fields = &fields,
    });

    try std.testing.expectEqual(@as(usize, 1), registry.componentCount());

    const incompatible_fields = [_]ComponentFieldDefinition{
        .{ .name = "current", .value_type = .int },
        .{ .name = "max", .value_type = .float },
    };
    try std.testing.expectError(RegistryError.DuplicateComponentType, registry.registerComponent(.{
        .id = "com.acme.health",
        .version = 1,
        .fields = &incompatible_fields,
    }));
}

test "component registry rejects duplicate field names" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const fields = [_]ComponentFieldDefinition{
        .{ .name = "current", .value_type = .float },
        .{ .name = "current", .value_type = .int },
    };
    try std.testing.expectError(RegistryError.DuplicateComponentField, registry.registerComponent(.{
        .id = "com.acme.health",
        .version = 1,
        .fields = &fields,
    }));
}

test "component registry reserves machina namespace for engine registrations" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectError(RegistryError.ReservedTypeId, registry.registerComponent(.{
        .id = "machina.transform",
        .version = 1,
    }));

    try registry.registerEngineComponent(.{
        .id = "machina.transform",
        .version = 1,
    });
    try std.testing.expectEqual(@as(usize, 1), registry.componentCount());
}

test "system registry validates component access and reload-compatible definitions" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerComponent(.{ .id = "com.acme.health", .version = 1 });
    try registry.registerEngineComponent(.{ .id = "machina.transform", .version = 1 });

    const reads = [_][]const u8{ "machina.transform", "com.acme.health" };
    const writes = [_][]const u8{"com.acme.health"};
    const after = [_][]const u8{"machina.input"};
    try registry.registerSystem(.{
        .id = "com.acme.health_regen",
        .reads = &reads,
        .writes = &.{},
        .after = &after,
    });
    try registry.registerSystem(.{
        .id = "com.acme.health_regen",
        .reads = &reads,
        .writes = &.{},
        .after = &after,
    });
    try std.testing.expectEqual(@as(usize, 1), registry.systemCount());

    try std.testing.expectError(RegistryError.UnknownComponentType, registry.registerSystem(.{
        .id = "com.acme.missing_reader",
        .reads = &.{"com.acme.missing"},
    }));
    try std.testing.expectError(RegistryError.DuplicateSystemAccess, registry.registerSystem(.{
        .id = "com.acme.bad_access",
        .reads = &reads,
        .writes = &writes,
    }));
    try std.testing.expectError(RegistryError.ReservedTypeId, registry.registerSystem(.{
        .id = "machina.script_system",
    }));
}
