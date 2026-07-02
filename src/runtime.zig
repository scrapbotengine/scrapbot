const std = @import("std");

pub const WorldError = std.mem.Allocator.Error || error{
    DuplicateEntityId,
    InvalidEntity,
    UnknownComponent,
    UnknownField,
    InvalidFieldType,
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

pub const ScheduleError = error{
    CyclicSystemOrder,
};

const engine_namespace = "machina";
pub const transform_component_id = "machina.transform";
pub const cube_renderer_component_id = "machina.render.cube";
pub const spin_component_id = "spin";

pub const FieldType = enum {
    boolean,
    int,
    float,
    vec3,
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

pub const SystemPhase = enum {
    startup,
    update,
    fixed_update,
    render,
};

pub const SystemDefinition = struct {
    id: []const u8,
    phase: SystemPhase = .update,
    reads: []const []const u8 = &.{},
    writes: []const []const u8 = &.{},
    before: []const []const u8 = &.{},
    after: []const []const u8 = &.{},
    runner: SystemRunner = .none,
};

pub const SystemRunner = union(enum) {
    none,
    luau: u32,
};

pub const ScheduledSystem = struct {
    registry_index: usize,
    id: []const u8,
    runner: SystemRunner,
};

pub const SystemBatch = struct {
    phase: SystemPhase,
    systems: []const ScheduledSystem,
};

pub const SystemSchedule = struct {
    allocator: std.mem.Allocator,
    batches: []const SystemBatch,

    pub fn deinit(self: *SystemSchedule) void {
        const allocator = self.allocator;
        for (self.batches) |batch| {
            for (batch.systems) |system| {
                allocator.free(system.id);
            }
            allocator.free(batch.systems);
        }
        allocator.free(self.batches);
        self.* = .{
            .allocator = allocator,
            .batches = &.{},
        };
    }

    pub fn batchCount(self: SystemSchedule) usize {
        return self.batches.len;
    }

    pub fn systemCount(self: SystemSchedule) usize {
        var count: usize = 0;
        for (self.batches) |batch| {
            count += batch.systems.len;
        }
        return count;
    }
};

const RegistrationContext = enum {
    engine,
    project,
    package,
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

    pub fn registerProjectComponent(self: *ComponentRegistry, definition: ComponentDefinition) !void {
        return self.registerComponentAs(.project, definition);
    }

    pub fn registerPackageComponent(self: *ComponentRegistry, definition: ComponentDefinition) !void {
        return self.registerComponentAs(.package, definition);
    }

    pub fn registerEngineComponent(self: *ComponentRegistry, definition: ComponentDefinition) !void {
        return self.registerComponentAs(.engine, definition);
    }

    pub fn registerProjectSystem(self: *ComponentRegistry, definition: SystemDefinition) !void {
        return self.registerSystemAs(.project, definition);
    }

    pub fn registerPackageSystem(self: *ComponentRegistry, definition: SystemDefinition) !void {
        return self.registerSystemAs(.package, definition);
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

    pub fn buildSchedule(self: ComponentRegistry, allocator: std.mem.Allocator, phase: SystemPhase) !SystemSchedule {
        var phase_indices: std.ArrayList(usize) = .empty;
        defer phase_indices.deinit(allocator);

        for (self.systems.items, 0..) |system, index| {
            if (system.phase == phase) {
                try phase_indices.append(allocator, index);
            }
        }

        const system_count = phase_indices.items.len;
        const remaining_dependencies = try allocator.alloc(usize, system_count);
        defer allocator.free(remaining_dependencies);
        const scheduled = try allocator.alloc(bool, system_count);
        defer allocator.free(scheduled);

        @memset(remaining_dependencies, 0);
        @memset(scheduled, false);

        for (0..system_count) |target_local| {
            for (0..system_count) |source_local| {
                if (source_local == target_local) {
                    continue;
                }
                if (self.mustRunBefore(phase_indices.items[source_local], phase_indices.items[target_local])) {
                    remaining_dependencies[target_local] += 1;
                }
            }
        }

        var batches: std.ArrayList(SystemBatch) = .empty;
        errdefer {
            for (batches.items) |batch| {
                for (batch.systems) |system| {
                    allocator.free(system.id);
                }
                allocator.free(batch.systems);
            }
            batches.deinit(allocator);
        }

        var scheduled_count: usize = 0;
        while (scheduled_count < system_count) {
            var batch_local_indices: std.ArrayList(usize) = .empty;
            defer batch_local_indices.deinit(allocator);

            for (0..system_count) |local_index| {
                if (scheduled[local_index] or remaining_dependencies[local_index] != 0) {
                    continue;
                }
                if (self.conflictsWithBatch(phase_indices.items[local_index], phase_indices.items, batch_local_indices.items)) {
                    continue;
                }

                try batch_local_indices.append(allocator, local_index);
                scheduled[local_index] = true;
            }

            if (batch_local_indices.items.len == 0) {
                return ScheduleError.CyclicSystemOrder;
            }

            const systems = try allocator.alloc(ScheduledSystem, batch_local_indices.items.len);
            var copied_system_count: usize = 0;
            var systems_transferred = false;
            errdefer {
                if (!systems_transferred) {
                    for (systems[0..copied_system_count]) |system| {
                        allocator.free(system.id);
                    }
                    allocator.free(systems);
                }
            }

            for (batch_local_indices.items, 0..) |local_index, batch_index| {
                const registry_index = phase_indices.items[local_index];
                systems[batch_index] = .{
                    .registry_index = registry_index,
                    .id = try allocator.dupe(u8, self.systems.items[registry_index].id),
                    .runner = self.systems.items[registry_index].runner,
                };
                copied_system_count += 1;
            }

            try batches.append(allocator, .{
                .phase = phase,
                .systems = systems,
            });
            systems_transferred = true;

            scheduled_count += batch_local_indices.items.len;

            for (batch_local_indices.items) |source_local| {
                for (0..system_count) |target_local| {
                    if (scheduled[target_local]) {
                        continue;
                    }
                    if (self.mustRunBefore(phase_indices.items[source_local], phase_indices.items[target_local])) {
                        remaining_dependencies[target_local] -= 1;
                    }
                }
            }
        }

        return .{
            .allocator = allocator,
            .batches = try batches.toOwnedSlice(allocator),
        };
    }

    fn registerComponentAs(self: *ComponentRegistry, context: RegistrationContext, definition: ComponentDefinition) !void {
        try validateTypeIdForContext(definition.id, context);
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

    fn registerSystemAs(self: *ComponentRegistry, context: RegistrationContext, definition: SystemDefinition) !void {
        try validateTypeIdForContext(definition.id, context);
        try self.validateSystemAccess(definition, context);

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

    fn validateSystemAccess(self: ComponentRegistry, definition: SystemDefinition, context: RegistrationContext) !void {
        for (definition.reads) |component_id| {
            try validateReferenceTypeIdForContext(component_id, context);
            if (self.findComponent(component_id) == null) {
                return RegistryError.UnknownComponentType;
            }
            if (countString(definition.reads, component_id) > 1 or containsString(definition.writes, component_id)) {
                return RegistryError.DuplicateSystemAccess;
            }
        }

        for (definition.writes) |component_id| {
            try validateReferenceTypeIdForContext(component_id, context);
            if (self.findComponent(component_id) == null) {
                return RegistryError.UnknownComponentType;
            }
            if (countString(definition.writes, component_id) > 1) {
                return RegistryError.DuplicateSystemAccess;
            }
        }

        for (definition.before) |system_id| {
            try validateReferenceTypeIdForContext(system_id, context);
        }
        for (definition.after) |system_id| {
            try validateReferenceTypeIdForContext(system_id, context);
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
            .phase = definition.phase,
            .reads = reads,
            .writes = writes,
            .before = before,
            .after = after,
            .runner = definition.runner,
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

    fn mustRunBefore(self: ComponentRegistry, source_index: usize, target_index: usize) bool {
        const source = self.systems.items[source_index];
        const target = self.systems.items[target_index];
        return containsString(source.before, target.id) or containsString(target.after, source.id);
    }

    fn conflictsWithBatch(
        self: ComponentRegistry,
        candidate_index: usize,
        phase_indices: []const usize,
        batch_local_indices: []const usize,
    ) bool {
        const candidate = self.systems.items[candidate_index];
        for (batch_local_indices) |local_index| {
            const other = self.systems.items[phase_indices[local_index]];
            if (systemsConflict(candidate, other)) {
                return true;
            }
        }
        return false;
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

pub const ComponentValue = union(FieldType) {
    boolean: bool,
    int: i32,
    float: f32,
    vec3: [3]f32,
    string: []const u8,
};

pub const ComponentFieldValue = struct {
    name: []const u8,
    value: ComponentValue,
};

const ComponentColumnValues = union(FieldType) {
    boolean: std.ArrayList(bool),
    int: std.ArrayList(i32),
    float: std.ArrayList(f32),
    vec3: std.ArrayList([3]f32),
    string: std.ArrayList([]const u8),

    fn init(value: ComponentValue) ComponentColumnValues {
        return switch (value) {
            .boolean => .{ .boolean = .empty },
            .int => .{ .int = .empty },
            .float => .{ .float = .empty },
            .vec3 => .{ .vec3 = .empty },
            .string => .{ .string = .empty },
        };
    }

    fn deinit(self: *ComponentColumnValues, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .boolean => |*values| values.deinit(allocator),
            .int => |*values| values.deinit(allocator),
            .float => |*values| values.deinit(allocator),
            .vec3 => |*values| values.deinit(allocator),
            .string => |*values| {
                for (values.items) |value| {
                    allocator.free(value);
                }
                values.deinit(allocator);
            },
        }
    }

    fn appendCopy(self: *ComponentColumnValues, allocator: std.mem.Allocator, value: ComponentValue) WorldError!void {
        switch (self.*) {
            .boolean => |*values| switch (value) {
                .boolean => |payload| try values.append(allocator, payload),
                else => return WorldError.InvalidFieldType,
            },
            .int => |*values| switch (value) {
                .int => |payload| try values.append(allocator, payload),
                else => return WorldError.InvalidFieldType,
            },
            .float => |*values| switch (value) {
                .float => |payload| try values.append(allocator, payload),
                else => return WorldError.InvalidFieldType,
            },
            .vec3 => |*values| switch (value) {
                .vec3 => |payload| try values.append(allocator, payload),
                else => return WorldError.InvalidFieldType,
            },
            .string => |*values| switch (value) {
                .string => |payload| {
                    const owned = try allocator.dupe(u8, payload);
                    errdefer allocator.free(owned);
                    try values.append(allocator, owned);
                },
                else => return WorldError.InvalidFieldType,
            },
        }
    }

    fn setCopy(self: *ComponentColumnValues, allocator: std.mem.Allocator, row: usize, value: ComponentValue) WorldError!void {
        switch (self.*) {
            .boolean => |*values| switch (value) {
                .boolean => |payload| values.items[row] = payload,
                else => return WorldError.InvalidFieldType,
            },
            .int => |*values| switch (value) {
                .int => |payload| values.items[row] = payload,
                else => return WorldError.InvalidFieldType,
            },
            .float => |*values| switch (value) {
                .float => |payload| values.items[row] = payload,
                else => return WorldError.InvalidFieldType,
            },
            .vec3 => |*values| switch (value) {
                .vec3 => |payload| values.items[row] = payload,
                else => return WorldError.InvalidFieldType,
            },
            .string => |*values| switch (value) {
                .string => |payload| {
                    const owned = try allocator.dupe(u8, payload);
                    allocator.free(values.items[row]);
                    values.items[row] = owned;
                },
                else => return WorldError.InvalidFieldType,
            },
        }
    }

    fn popValue(self: *ComponentColumnValues, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .boolean => |*values| _ = values.pop(),
            .int => |*values| _ = values.pop(),
            .float => |*values| _ = values.pop(),
            .vec3 => |*values| _ = values.pop(),
            .string => |*values| {
                const value = values.pop().?;
                allocator.free(value);
            },
        }
    }

    fn valueAt(self: ComponentColumnValues, row: usize) ComponentValue {
        return switch (self) {
            .boolean => |values| .{ .boolean = values.items[row] },
            .int => |values| .{ .int = values.items[row] },
            .float => |values| .{ .float = values.items[row] },
            .vec3 => |values| .{ .vec3 = values.items[row] },
            .string => |values| .{ .string = values.items[row] },
        };
    }

    fn valueType(self: ComponentColumnValues) FieldType {
        return switch (self) {
            .boolean => .boolean,
            .int => .int,
            .float => .float,
            .vec3 => .vec3,
            .string => .string,
        };
    }
};

const ComponentColumn = struct {
    name: []const u8,
    values: ComponentColumnValues,

    fn deinit(self: *ComponentColumn, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.values.deinit(allocator);
    }
};

const ComponentTable = struct {
    id: []const u8,
    entities: std.ArrayList(EntityHandle) = .empty,
    rows_by_entity: std.ArrayList(?usize) = .empty,
    columns: []ComponentColumn = &.{},

    fn deinit(self: *ComponentTable, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        for (self.columns) |*column| {
            column.deinit(allocator);
        }
        allocator.free(self.columns);
        self.rows_by_entity.deinit(allocator);
        self.entities.deinit(allocator);
    }
};

pub const World = struct {
    allocator: std.mem.Allocator,
    entities: std.ArrayList(Entity) = .empty,
    component_tables: std.ArrayList(ComponentTable) = .empty,

    pub fn init(allocator: std.mem.Allocator) World {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *World) void {
        const allocator = self.allocator;
        for (self.entities.items) |stored_entity| {
            allocator.free(stored_entity.id);
            allocator.free(stored_entity.name);
        }
        for (self.component_tables.items) |*component_table| {
            component_table.deinit(allocator);
        }
        self.component_tables.deinit(allocator);
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

        var grown_tables: usize = 0;
        errdefer {
            for (self.component_tables.items[0..grown_tables]) |*table| {
                _ = table.rows_by_entity.pop();
            }
        }
        for (self.component_tables.items) |*table| {
            try table.rows_by_entity.append(self.allocator, null);
            grown_tables += 1;
        }

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
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = transform.position } },
            .{ .name = "rotation", .value = .{ .vec3 = transform.rotation } },
            .{ .name = "scale", .value = .{ .vec3 = transform.scale } },
        };
        try self.setComponent(handle, transform_component_id, &fields);
    }

    pub fn setCubeRenderer(self: *World, handle: EntityHandle, cube_renderer: CubeRenderer) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "color", .value = .{ .vec3 = cube_renderer.color } },
        };
        try self.setComponent(handle, cube_renderer_component_id, &fields);
    }

    pub fn setSpin(self: *World, handle: EntityHandle, spin: Spin) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "angular_velocity", .value = .{ .vec3 = spin.angular_velocity } },
        };
        try self.setComponent(handle, spin_component_id, &fields);
    }

    pub fn getTransform(self: World, handle: EntityHandle) WorldError!?Transform {
        if (!try self.hasComponent(handle, transform_component_id)) {
            return null;
        }
        return .{
            .position = try self.getVec3(handle, transform_component_id, "position"),
            .rotation = try self.getVec3(handle, transform_component_id, "rotation"),
            .scale = try self.getVec3(handle, transform_component_id, "scale"),
        };
    }

    pub fn setComponent(self: *World, handle: EntityHandle, component_id: []const u8, fields: []const ComponentFieldValue) WorldError!void {
        const index = try self.componentIndex(handle);
        const table_index = try self.ensureComponentTable(component_id, fields);
        const table = &self.component_tables.items[table_index];
        if (table.rows_by_entity.items[index]) |row| {
            try self.updateComponentRow(table, row, fields);
        } else {
            try self.appendComponentRow(table, handle, index, fields);
        }
    }

    pub fn hasComponent(self: World, handle: EntityHandle, component_id: []const u8) WorldError!bool {
        const index = try self.componentIndex(handle);
        const table = self.findComponentTable(component_id) orelse return false;
        return table.rows_by_entity.items[index] != null;
    }

    pub fn hasComponents(self: World, handle: EntityHandle, component_ids: []const []const u8) WorldError!bool {
        for (component_ids) |component_id| {
            if (!try self.hasComponent(handle, component_id)) {
                return false;
            }
        }
        return true;
    }

    pub fn queryNext(self: World, component_ids: []const []const u8, cursor: *usize) ?EntityHandle {
        const driver = self.queryDriverTable(component_ids) orelse return null;
        while (cursor.* < driver.entities.items.len) : (cursor.* += 1) {
            const handle = driver.entities.items[cursor.*];
            if (self.hasComponents(handle, component_ids) catch false) {
                cursor.* += 1;
                return handle;
            }
        }
        return null;
    }

    pub fn getVec3(self: World, handle: EntityHandle, component_id: []const u8, field_name: []const u8) WorldError![3]f32 {
        const value = try self.getFieldValue(handle, component_id, field_name);
        return switch (value) {
            .vec3 => |payload| payload,
            else => WorldError.InvalidFieldType,
        };
    }

    pub fn setVec3(self: *World, handle: EntityHandle, component_id: []const u8, field_name: []const u8, value: [3]f32) WorldError!void {
        if (!std.math.isFinite(value[0]) or !std.math.isFinite(value[1]) or !std.math.isFinite(value[2])) {
            return WorldError.InvalidFieldType;
        }
        try self.setFieldValue(handle, component_id, field_name, .{ .vec3 = value });
    }

    pub fn getComponentFieldValue(self: World, handle: EntityHandle, component_id: []const u8, field_name: []const u8) WorldError!ComponentValue {
        return self.getFieldValue(handle, component_id, field_name);
    }

    pub fn setComponentFieldValue(self: *World, handle: EntityHandle, component_id: []const u8, field_name: []const u8, value: ComponentValue) WorldError!void {
        try self.setFieldValue(handle, component_id, field_name, value);
    }

    pub fn renderableCubeCount(self: World) usize {
        var count: usize = 0;
        var cursor: usize = 0;
        const component_ids = [_][]const u8{ transform_component_id, cube_renderer_component_id };
        while (self.queryNext(&component_ids, &cursor)) |_| {
            count += 1;
        }
        return count;
    }

    pub fn renderableCubeAt(self: World, render_index: usize) ?RenderableCube {
        var found: usize = 0;
        var cursor: usize = 0;
        const component_ids = [_][]const u8{ transform_component_id, cube_renderer_component_id };
        while (self.queryNext(&component_ids, &cursor)) |handle| {
            const stored_entity = self.entity(handle) catch return null;
            if (found == render_index) {
                const transform = (self.getTransform(handle) catch return null) orelse return null;
                const color = self.getVec3(handle, cube_renderer_component_id, "color") catch return null;
                const spin = self.getVec3(handle, spin_component_id, "angular_velocity") catch .{ 0.0, 0.0, 0.0 };
                return .{
                    .entity = handle,
                    .id = stored_entity.id,
                    .name = stored_entity.name,
                    .position = transform.position,
                    .rotation = transform.rotation,
                    .scale = transform.scale,
                    .color = color,
                    .spin = spin,
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

    fn findComponentTable(self: World, component_id: []const u8) ?*const ComponentTable {
        for (self.component_tables.items) |*table| {
            if (std.mem.eql(u8, table.id, component_id)) {
                return table;
            }
        }
        return null;
    }

    fn findMutableComponentTable(self: *World, component_id: []const u8) ?*ComponentTable {
        for (self.component_tables.items) |*table| {
            if (std.mem.eql(u8, table.id, component_id)) {
                return table;
            }
        }
        return null;
    }

    fn queryDriverTable(self: World, component_ids: []const []const u8) ?*const ComponentTable {
        if (component_ids.len == 0) {
            return null;
        }

        var driver: ?*const ComponentTable = null;
        for (component_ids) |component_id| {
            const table = self.findComponentTable(component_id) orelse return null;
            if (driver == null or table.entities.items.len < driver.?.entities.items.len) {
                driver = table;
            }
        }
        return driver;
    }

    fn getFieldValue(self: World, handle: EntityHandle, component_id: []const u8, field_name: []const u8) WorldError!ComponentValue {
        const index = try self.componentIndex(handle);
        const table = self.findComponentTable(component_id) orelse return WorldError.UnknownComponent;
        const row = table.rows_by_entity.items[index] orelse return WorldError.UnknownComponent;
        const column = findColumn(table.*, field_name) orelse return WorldError.UnknownField;
        return column.values.valueAt(row);
    }

    fn setFieldValue(self: *World, handle: EntityHandle, component_id: []const u8, field_name: []const u8, value: ComponentValue) WorldError!void {
        const index = try self.componentIndex(handle);
        const table = self.findMutableComponentTable(component_id) orelse return WorldError.UnknownComponent;
        const row = table.rows_by_entity.items[index] orelse return WorldError.UnknownComponent;
        const column = findMutableColumn(table, field_name) orelse return WorldError.UnknownField;
        try column.values.setCopy(self.allocator, row, value);
    }

    fn ensureComponentTable(self: *World, component_id: []const u8, fields: []const ComponentFieldValue) WorldError!usize {
        for (self.component_tables.items, 0..) |*table, index| {
            if (std.mem.eql(u8, table.id, component_id)) {
                try validateComponentTableFields(table.*, fields);
                return index;
            }
        }

        var table = try self.createComponentTable(component_id, fields);
        errdefer table.deinit(self.allocator);
        try self.component_tables.append(self.allocator, table);
        return self.component_tables.items.len - 1;
    }

    fn createComponentTable(self: World, component_id: []const u8, fields: []const ComponentFieldValue) WorldError!ComponentTable {
        const owned_id = try self.allocator.dupe(u8, component_id);
        errdefer self.allocator.free(owned_id);

        const columns = try self.allocator.alloc(ComponentColumn, fields.len);
        errdefer self.allocator.free(columns);

        var initialized_columns: usize = 0;
        errdefer {
            for (columns[0..initialized_columns]) |*column| {
                column.deinit(self.allocator);
            }
        }

        for (fields, 0..) |field, index| {
            if (findFieldValue(fields[0..index], field.name) != null) {
                return WorldError.UnknownField;
            }
            columns[index] = .{
                .name = try self.allocator.dupe(u8, field.name),
                .values = ComponentColumnValues.init(field.value),
            };
            initialized_columns += 1;
        }

        var rows_by_entity: std.ArrayList(?usize) = .empty;
        errdefer rows_by_entity.deinit(self.allocator);
        try rows_by_entity.ensureTotalCapacity(self.allocator, self.entities.items.len);
        for (0..self.entities.items.len) |_| {
            try rows_by_entity.append(self.allocator, null);
        }

        return .{
            .id = owned_id,
            .rows_by_entity = rows_by_entity,
            .columns = columns,
        };
    }

    fn appendComponentRow(self: *World, table: *ComponentTable, handle: EntityHandle, entity_index: usize, fields: []const ComponentFieldValue) WorldError!void {
        try validateComponentTableFields(table.*, fields);

        const row = table.entities.items.len;
        try table.entities.append(self.allocator, handle);
        errdefer _ = table.entities.pop();
        table.rows_by_entity.items[entity_index] = row;

        var appended_columns: usize = 0;
        errdefer {
            for (table.columns[0..appended_columns]) |*column| {
                column.values.popValue(self.allocator);
            }
            table.rows_by_entity.items[entity_index] = null;
        }

        for (table.columns) |*column| {
            const field = findFieldValue(fields, column.name) orelse return WorldError.UnknownField;
            try column.values.appendCopy(self.allocator, field.value);
            appended_columns += 1;
        }
    }

    fn updateComponentRow(self: *World, table: *ComponentTable, row: usize, fields: []const ComponentFieldValue) WorldError!void {
        try validateComponentTableFields(table.*, fields);
        for (table.columns) |*column| {
            const field = findFieldValue(fields, column.name) orelse return WorldError.UnknownField;
            try column.values.setCopy(self.allocator, row, field.value);
        }
    }
};

fn findFieldValue(fields: []const ComponentFieldValue, field_name: []const u8) ?ComponentFieldValue {
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return field;
        }
    }
    return null;
}

fn findColumn(table: ComponentTable, field_name: []const u8) ?*const ComponentColumn {
    for (table.columns) |*column| {
        if (std.mem.eql(u8, column.name, field_name)) {
            return column;
        }
    }
    return null;
}

fn findMutableColumn(table: *ComponentTable, field_name: []const u8) ?*ComponentColumn {
    for (table.columns) |*column| {
        if (std.mem.eql(u8, column.name, field_name)) {
            return column;
        }
    }
    return null;
}

fn validateComponentTableFields(table: ComponentTable, fields: []const ComponentFieldValue) WorldError!void {
    if (fields.len != table.columns.len) {
        return WorldError.UnknownField;
    }

    for (table.columns) |column| {
        const field = findFieldValue(fields, column.name) orelse return WorldError.UnknownField;
        if (std.meta.activeTag(field.value) != column.values.valueType()) {
            return WorldError.InvalidFieldType;
        }
    }

    for (fields) |field| {
        _ = findColumn(table, field.name) orelse return WorldError.UnknownField;
    }
}

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
    _ = try validateTypeIdShape(id);
}

pub fn validateProjectTypeId(id: []const u8) TypeIdError!void {
    try validateTypeId(id);
    if (isEngineTypeId(id)) {
        return TypeIdError.ReservedTypeId;
    }
}

pub fn validatePackageTypeId(id: []const u8) TypeIdError!void {
    const segment_count = try validateTypeIdShape(id);
    if (segment_count < 2) {
        return TypeIdError.InvalidTypeId;
    }
    if (isEngineTypeId(id)) {
        return TypeIdError.ReservedTypeId;
    }
}

pub fn validateEngineTypeId(id: []const u8) TypeIdError!void {
    try validateTypeId(id);
    if (!std.mem.startsWith(u8, id, engine_namespace ++ ".")) {
        return TypeIdError.ReservedTypeId;
    }
}

fn validateTypeIdForContext(id: []const u8, context: RegistrationContext) TypeIdError!void {
    switch (context) {
        .engine => try validateEngineTypeId(id),
        .project => try validateProjectTypeId(id),
        .package => try validatePackageTypeId(id),
    }
}

fn validateReferenceTypeIdForContext(id: []const u8, context: RegistrationContext) TypeIdError!void {
    switch (context) {
        .engine, .project => try validateTypeId(id),
        .package => {
            const segment_count = try validateTypeIdShape(id);
            if (segment_count < 2) {
                return TypeIdError.InvalidTypeId;
            }
        },
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

fn validateTypeIdShape(id: []const u8) TypeIdError!usize {
    var segment_count: usize = 0;
    var segments = std.mem.splitScalar(u8, id, '.');
    while (segments.next()) |segment| {
        try validateIdentifierSegment(segment);
        segment_count += 1;
    }

    if (segment_count == 0) {
        return TypeIdError.InvalidTypeId;
    }
    return segment_count;
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
    return std.mem.eql(u8, left.id, right.id) and left.phase == right.phase and
        systemRunnersEqual(left.runner, right.runner) and
        stringListsEqual(left.reads, right.reads) and
        stringListsEqual(left.writes, right.writes) and
        stringListsEqual(left.before, right.before) and
        stringListsEqual(left.after, right.after);
}

fn systemRunnersEqual(left: SystemRunner, right: SystemRunner) bool {
    return switch (left) {
        .none => right == .none,
        .luau => |left_ref| switch (right) {
            .none => false,
            .luau => |right_ref| left_ref == right_ref,
        },
    };
}

fn systemsConflict(left: SystemDefinition, right: SystemDefinition) bool {
    for (left.writes) |component_id| {
        if (containsString(right.reads, component_id) or containsString(right.writes, component_id)) {
            return true;
        }
    }
    for (right.writes) |component_id| {
        if (containsString(left.reads, component_id) or containsString(left.writes, component_id)) {
            return true;
        }
    }
    return false;
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

test "world queries and mutates component field storage" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("spinner", "Spinner");
    try world.setTransform(entity, .{ .rotation = .{ 0.1, 0.2, 0.3 } });
    try world.setSpin(entity, .{ .angular_velocity = .{ 1.0, 2.0, -4.0 } });

    var cursor: usize = 0;
    const query = [_][]const u8{ transform_component_id, spin_component_id };
    const queried = world.queryNext(&query, &cursor) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(entity.index, queried.index);
    try std.testing.expect(world.queryNext(&query, &cursor) == null);

    const rotation = try world.getVec3(entity, transform_component_id, "rotation");
    const angular_velocity = try world.getVec3(entity, spin_component_id, "angular_velocity");
    try world.setVec3(entity, transform_component_id, "rotation", .{
        rotation[0] + angular_velocity[0] * 0.5,
        rotation[1] + angular_velocity[1] * 0.5,
        rotation[2] + angular_velocity[2] * 0.5,
    });

    const transform_after = (try world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 0.6), transform_after.rotation[0]);
    try std.testing.expectEqual(@as(f32, 1.2), transform_after.rotation[1]);
    try std.testing.expectEqual(@as(f32, -1.7), transform_after.rotation[2]);
    try std.testing.expectError(WorldError.UnknownComponent, world.getVec3(entity, "stamina", "value"));
    try std.testing.expectError(WorldError.InvalidFieldType, world.setVec3(entity, transform_component_id, "rotation", .{ std.math.inf(f32), 0.0, 0.0 }));
}

test "world stores component fields in sparse SoA tables" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const untagged = try world.createEntity("untagged", "Untagged");
    const plain = try world.createEntity("plain", "Plain");
    const spinner = try world.createEntity("spinner", "Spinner");
    try world.setTransform(plain, .{ .position = .{ -1.0, 0.0, 0.0 } });
    try world.setTransform(spinner, .{
        .position = .{ 1.0, 2.0, 3.0 },
        .rotation = .{ 0.1, 0.2, 0.3 },
        .scale = .{ 2.0, 2.0, 2.0 },
    });
    try world.setSpin(spinner, .{ .angular_velocity = .{ 0.0, 1.0, 0.0 } });

    const transform_table = world.findComponentTable(transform_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), transform_table.entities.items.len);
    try std.testing.expectEqual(plain.index, transform_table.entities.items[0].index);
    try std.testing.expectEqual(spinner.index, transform_table.entities.items[1].index);
    try std.testing.expectEqual(@as(usize, 3), transform_table.rows_by_entity.items.len);
    try std.testing.expect(transform_table.rows_by_entity.items[untagged.index] == null);
    try std.testing.expectEqual(@as(usize, 1), transform_table.rows_by_entity.items[spinner.index] orelse return error.TestExpectedEqual);

    const rotation_column = findColumn(transform_table.*, "rotation") orelse return error.TestExpectedEqual;
    const rotation_values = switch (rotation_column.values) {
        .vec3 => |values| values,
        else => return error.TestExpectedEqual,
    };
    try std.testing.expectEqual(@as(usize, 2), rotation_values.items.len);
    try std.testing.expectEqual(@as(f32, 0.2), rotation_values.items[1][1]);

    var cursor: usize = 0;
    const query = [_][]const u8{ transform_component_id, spin_component_id };
    try std.testing.expectEqual(spinner.index, (world.queryNext(&query, &cursor) orelse return error.TestExpectedEqual).index);
    try std.testing.expectEqual(@as(usize, 1), cursor);

    try world.setVec3(spinner, transform_component_id, "rotation", .{ 0.5, 0.6, 0.7 });
    const updated_table = world.findComponentTable(transform_component_id) orelse return error.TestExpectedEqual;
    const updated_rotation_column = findColumn(updated_table.*, "rotation") orelse return error.TestExpectedEqual;
    const updated_rotation_values = switch (updated_rotation_column.values) {
        .vec3 => |values| values,
        else => return error.TestExpectedEqual,
    };
    try std.testing.expectEqual(@as(usize, 2), updated_table.entities.items.len);
    try std.testing.expectEqual(@as(f32, 0.6), updated_rotation_values.items[1][1]);
}

test "type ids distinguish project-local, package, and engine namespaces" {
    try validateProjectTypeId("stamina");
    try validateProjectTypeId("inventory_item");
    try validateProjectTypeId("com.acme.stamina");
    try validateProjectTypeId("game.stamina");
    try validatePackageTypeId("com.acme.stamina");
    try validateEngineTypeId("machina.transform");

    try std.testing.expectError(TypeIdError.InvalidTypeId, validateProjectTypeId("Com.Acme.Stamina"));
    try std.testing.expectError(TypeIdError.InvalidTypeId, validateProjectTypeId("com.acme-stamina"));
    try std.testing.expectError(TypeIdError.InvalidTypeId, validateProjectTypeId("com..stamina"));
    try std.testing.expectError(TypeIdError.InvalidTypeId, validatePackageTypeId("stamina"));
    try std.testing.expectError(TypeIdError.ReservedTypeId, validateProjectTypeId("machina.transform"));
    try std.testing.expectError(TypeIdError.ReservedTypeId, validatePackageTypeId("machina.transform"));
    try std.testing.expectError(TypeIdError.ReservedTypeId, validateEngineTypeId("stamina"));
    try std.testing.expectError(TypeIdError.ReservedTypeId, validateEngineTypeId("com.acme.stamina"));
}

test "component registry allows reload-identical components and rejects incompatible duplicates" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const fields = [_]ComponentFieldDefinition{
        .{ .name = "current", .value_type = .float },
        .{ .name = "max", .value_type = .float },
    };
    try registry.registerProjectComponent(.{
        .id = "stamina",
        .version = 1,
        .fields = &fields,
    });
    try registry.registerProjectComponent(.{
        .id = "stamina",
        .version = 1,
        .fields = &fields,
    });

    try std.testing.expectEqual(@as(usize, 1), registry.componentCount());

    const incompatible_fields = [_]ComponentFieldDefinition{
        .{ .name = "current", .value_type = .int },
        .{ .name = "max", .value_type = .float },
    };
    try std.testing.expectError(RegistryError.DuplicateComponentType, registry.registerProjectComponent(.{
        .id = "stamina",
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
    try std.testing.expectError(RegistryError.DuplicateComponentField, registry.registerProjectComponent(.{
        .id = "com.acme.stamina",
        .version = 1,
        .fields = &fields,
    }));
}

test "component registry separates project, package, and engine registrations" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerProjectComponent(.{
        .id = "stamina",
        .version = 1,
    });
    try std.testing.expectError(RegistryError.InvalidTypeId, registry.registerPackageComponent(.{
        .id = "mana",
        .version = 1,
    }));
    try registry.registerPackageComponent(.{
        .id = "com.acme.mana",
        .version = 1,
    });
    try std.testing.expectError(RegistryError.ReservedTypeId, registry.registerProjectComponent(.{
        .id = "machina.transform",
        .version = 1,
    }));

    try registry.registerEngineComponent(.{
        .id = "machina.transform",
        .version = 1,
    });
    try std.testing.expectEqual(@as(usize, 3), registry.componentCount());
}

test "system registry validates component access and reload-compatible definitions" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerProjectComponent(.{ .id = "stamina", .version = 1 });
    try registry.registerPackageComponent(.{ .id = "com.acme.mana", .version = 1 });
    try registry.registerEngineComponent(.{ .id = "machina.transform", .version = 1 });

    const reads = [_][]const u8{ "machina.transform", "stamina" };
    const writes = [_][]const u8{"stamina"};
    const after = [_][]const u8{"input"};
    try registry.registerProjectSystem(.{
        .id = "stamina_regen",
        .reads = &reads,
        .writes = &.{},
        .after = &after,
    });
    try registry.registerProjectSystem(.{
        .id = "stamina_regen",
        .reads = &reads,
        .writes = &.{},
        .after = &after,
    });
    try std.testing.expectEqual(@as(usize, 1), registry.systemCount());

    const package_reads = [_][]const u8{"com.acme.mana"};
    try registry.registerPackageSystem(.{
        .id = "com.acme.mana_regen",
        .reads = &package_reads,
    });
    try std.testing.expectEqual(@as(usize, 2), registry.systemCount());

    try std.testing.expectError(RegistryError.UnknownComponentType, registry.registerProjectSystem(.{
        .id = "com.acme.missing_reader",
        .reads = &.{"com.acme.missing"},
    }));
    try std.testing.expectError(RegistryError.InvalidTypeId, registry.registerPackageSystem(.{
        .id = "com.acme.bad_local_access",
        .reads = &.{"stamina"},
    }));
    try std.testing.expectError(RegistryError.DuplicateSystemAccess, registry.registerProjectSystem(.{
        .id = "com.acme.bad_access",
        .reads = &reads,
        .writes = &writes,
    }));
    try std.testing.expectError(RegistryError.ReservedTypeId, registry.registerProjectSystem(.{
        .id = "machina.script_system",
    }));
}

test "system schedule batches compatible systems and detects order cycles" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerProjectComponent(.{ .id = "stamina" });
    try registry.registerProjectComponent(.{ .id = "focus" });

    try registry.registerProjectSystem(.{
        .id = "observe_stamina",
        .reads = &.{"stamina"},
    });
    try registry.registerProjectSystem(.{
        .id = "observe_focus",
        .reads = &.{"focus"},
    });
    try registry.registerProjectSystem(.{
        .id = "regen_stamina",
        .writes = &.{"stamina"},
        .after = &.{"observe_stamina"},
    });

    var schedule = try registry.buildSchedule(std.testing.allocator, .update);
    defer schedule.deinit();

    try std.testing.expectEqual(@as(usize, 2), schedule.batchCount());
    try std.testing.expectEqual(@as(usize, 3), schedule.systemCount());
    try std.testing.expectEqualStrings("observe_stamina", schedule.batches[0].systems[0].id);
    try std.testing.expectEqualStrings("observe_focus", schedule.batches[0].systems[1].id);
    try std.testing.expectEqualStrings("regen_stamina", schedule.batches[1].systems[0].id);

    var cyclic = ComponentRegistry.init(std.testing.allocator);
    defer cyclic.deinit();
    try cyclic.registerProjectSystem(.{
        .id = "first",
        .after = &.{"second"},
    });
    try cyclic.registerProjectSystem(.{
        .id = "second",
        .after = &.{"first"},
    });

    try std.testing.expectError(ScheduleError.CyclicSystemOrder, cyclic.buildSchedule(std.testing.allocator, .update));
}
