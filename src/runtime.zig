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
pub const geometry_primitive_component_id = "machina.geometry.primitive";
pub const surface_material_component_id = "machina.material.surface";
pub const camera_component_id = "machina.camera";
pub const directional_light_component_id = "machina.light.directional";
pub const shadow_caster_component_id = "machina.shadow.caster";
pub const shadow_receiver_component_id = "machina.shadow.receiver";
pub const ui_canvas_component_id = "machina.ui.canvas";
pub const ui_rect_component_id = "machina.ui.rect";
pub const ui_text_component_id = "machina.ui.text";
pub const ui_button_component_id = "machina.ui.button";
pub const ui_command_component_id = "machina.ui.command";
pub const ui_command_event_component_id = "machina.ui.command_event";
pub const ui_command_event_entity_id = "machina.ui.command_event.current";
pub const ui_scroll_view_component_id = "machina.ui.scroll_view";
pub const ui_vbox_component_id = "machina.ui.vbox";
pub const ui_stack_component_id = "machina.ui.stack";
pub const ui_layout_item_component_id = "machina.ui.layout.item";
pub const ui_spacer_component_id = "machina.ui.spacer";
pub const ui_text_block_component_id = "machina.ui.text_block";
pub const ui_toggle_component_id = "machina.ui.toggle";
pub const ui_progress_bar_component_id = "machina.ui.progress_bar";
pub const ui_separator_component_id = "machina.ui.separator";
pub const input_entity_id = "machina.input.frame";
pub const input_pointer_component_id = "machina.input.pointer";
pub const input_keyboard_component_id = "machina.input.keyboard";
pub const input_frame_component_id = "machina.input.frame";
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
    native: u32,
};

pub const SystemProfileSnapshot = struct {
    id: []const u8,
    phase: SystemPhase,
    sample_count: u32,
    window_size: u32,
    last_ns: u64,
    rolling_average_ns: u64,
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

pub fn registerEngineComponents(registry: *ComponentRegistry) !void {
    const transform_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "rotation", .value_type = .vec3 },
        .{ .name = "scale", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = transform_component_id,
        .version = 1,
        .fields = &transform_fields,
    });

    const cube_fields = [_]ComponentFieldDefinition{
        .{ .name = "color", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = cube_renderer_component_id,
        .version = 1,
        .fields = &cube_fields,
    });

    const geometry_fields = [_]ComponentFieldDefinition{
        .{ .name = "primitive", .value_type = .string },
        .{ .name = "segments", .value_type = .int },
        .{ .name = "rings", .value_type = .int },
    };
    try registry.registerEngineComponent(.{
        .id = geometry_primitive_component_id,
        .version = 1,
        .fields = &geometry_fields,
    });

    const material_fields = [_]ComponentFieldDefinition{
        .{ .name = "base_color", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = surface_material_component_id,
        .version = 1,
        .fields = &material_fields,
    });

    const camera_fields = [_]ComponentFieldDefinition{
        .{ .name = "fov_y_degrees", .value_type = .float },
        .{ .name = "near", .value_type = .float },
        .{ .name = "far", .value_type = .float },
    };
    try registry.registerEngineComponent(.{
        .id = camera_component_id,
        .version = 1,
        .fields = &camera_fields,
    });

    const directional_light_fields = [_]ComponentFieldDefinition{
        .{ .name = "direction", .value_type = .vec3 },
        .{ .name = "color", .value_type = .vec3 },
        .{ .name = "intensity", .value_type = .float },
        .{ .name = "ambient", .value_type = .float },
    };
    try registry.registerEngineComponent(.{
        .id = directional_light_component_id,
        .version = 1,
        .fields = &directional_light_fields,
    });

    try registry.registerEngineComponent(.{
        .id = shadow_caster_component_id,
        .version = 1,
    });

    try registry.registerEngineComponent(.{
        .id = shadow_receiver_component_id,
        .version = 1,
    });

    try registry.registerEngineComponent(.{
        .id = ui_canvas_component_id,
        .version = 1,
    });

    const ui_rect_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "size", .value_type = .vec3 },
        .{ .name = "color", .value_type = .vec3 },
        .{ .name = "corner_radius", .value_type = .float },
    };
    try registry.registerEngineComponent(.{
        .id = ui_rect_component_id,
        .version = 1,
        .fields = &ui_rect_fields,
    });

    const ui_text_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "size", .value_type = .float },
        .{ .name = "color", .value_type = .vec3 },
        .{ .name = "value", .value_type = .string },
    };
    try registry.registerEngineComponent(.{
        .id = ui_text_component_id,
        .version = 1,
        .fields = &ui_text_fields,
    });

    try registry.registerEngineComponent(.{
        .id = ui_button_component_id,
        .version = 1,
    });

    const ui_command_fields = [_]ComponentFieldDefinition{
        .{ .name = "command", .value_type = .string },
    };
    try registry.registerEngineComponent(.{
        .id = ui_command_component_id,
        .version = 1,
        .fields = &ui_command_fields,
    });

    const ui_command_event_fields = [_]ComponentFieldDefinition{
        .{ .name = "command", .value_type = .string },
        .{ .name = "source", .value_type = .string },
    };
    try registry.registerEngineComponent(.{
        .id = ui_command_event_component_id,
        .version = 1,
        .fields = &ui_command_event_fields,
    });

    const ui_scroll_view_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "size", .value_type = .vec3 },
        .{ .name = "content_offset", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = ui_scroll_view_component_id,
        .version = 1,
        .fields = &ui_scroll_view_fields,
    });

    const ui_vbox_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "spacing", .value_type = .float },
    };
    try registry.registerEngineComponent(.{
        .id = ui_vbox_component_id,
        .version = 1,
        .fields = &ui_vbox_fields,
    });

    const ui_stack_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "spacing", .value_type = .float },
        .{ .name = "direction", .value_type = .string },
        .{ .name = "padding", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = ui_stack_component_id,
        .version = 1,
        .fields = &ui_stack_fields,
    });

    const ui_layout_item_fields = [_]ComponentFieldDefinition{
        .{ .name = "parent", .value_type = .string },
        .{ .name = "order", .value_type = .int },
        .{ .name = "min_size", .value_type = .vec3 },
        .{ .name = "grow", .value_type = .float },
        .{ .name = "align", .value_type = .string },
    };
    try registry.registerEngineComponent(.{
        .id = ui_layout_item_component_id,
        .version = 1,
        .fields = &ui_layout_item_fields,
    });

    const ui_spacer_fields = [_]ComponentFieldDefinition{
        .{ .name = "size", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = ui_spacer_component_id,
        .version = 1,
        .fields = &ui_spacer_fields,
    });

    const ui_text_block_fields = [_]ComponentFieldDefinition{
        .{ .name = "size", .value_type = .vec3 },
        .{ .name = "horizontal_align", .value_type = .string },
        .{ .name = "vertical_align", .value_type = .string },
    };
    try registry.registerEngineComponent(.{
        .id = ui_text_block_component_id,
        .version = 1,
        .fields = &ui_text_block_fields,
    });

    const ui_toggle_fields = [_]ComponentFieldDefinition{
        .{ .name = "checked", .value_type = .boolean },
    };
    try registry.registerEngineComponent(.{
        .id = ui_toggle_component_id,
        .version = 1,
        .fields = &ui_toggle_fields,
    });

    const ui_progress_bar_fields = [_]ComponentFieldDefinition{
        .{ .name = "value", .value_type = .float },
        .{ .name = "max", .value_type = .float },
        .{ .name = "fill_color", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = ui_progress_bar_component_id,
        .version = 1,
        .fields = &ui_progress_bar_fields,
    });

    const ui_separator_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "size", .value_type = .vec3 },
        .{ .name = "color", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = ui_separator_component_id,
        .version = 1,
        .fields = &ui_separator_fields,
    });

    const input_pointer_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "has_position", .value_type = .boolean },
        .{ .name = "primary_down", .value_type = .boolean },
        .{ .name = "primary_pressed", .value_type = .boolean },
        .{ .name = "primary_released", .value_type = .boolean },
        .{ .name = "wheel_delta", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = input_pointer_component_id,
        .version = 1,
        .fields = &input_pointer_fields,
    });

    const input_keyboard_fields = [_]ComponentFieldDefinition{
        .{ .name = "ctrl_down", .value_type = .boolean },
        .{ .name = "shift_down", .value_type = .boolean },
        .{ .name = "alt_down", .value_type = .boolean },
        .{ .name = "super_down", .value_type = .boolean },
        .{ .name = "editor_toggle_pressed", .value_type = .boolean },
    };
    try registry.registerEngineComponent(.{
        .id = input_keyboard_component_id,
        .version = 1,
        .fields = &input_keyboard_fields,
    });

    const input_frame_fields = [_]ComponentFieldDefinition{
        .{ .name = "ui_visible", .value_type = .boolean },
        .{ .name = "debug_overlay_visible", .value_type = .boolean },
        .{ .name = "viewport", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = input_frame_component_id,
        .version = 1,
        .fields = &input_frame_fields,
    });
}

pub const EntityHandle = struct {
    index: u32,
    generation: u32 = 0,
};

pub const ResolvedComponentRow = struct {
    table_index: u32,
    row_index: u32,
};

pub const Entity = struct {
    id: []const u8,
    name: []const u8,
    generation: u32 = 0,
};

pub const EntityComponentIterator = struct {
    world: *const World,
    handle: EntityHandle,
    index: usize = 0,

    pub fn next(self: *EntityComponentIterator) ?[]const u8 {
        _ = self.world.entity(self.handle) catch return null;
        while (self.index < self.world.component_tables.items.len) {
            const table = &self.world.component_tables.items[self.index];
            self.index += 1;
            if (self.handle.index >= table.rows_by_entity.items.len) {
                continue;
            }
            if (table.rows_by_entity.items[self.handle.index] != null) {
                return table.id;
            }
        }
        return null;
    }
};

pub const Transform = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    rotation: [3]f32 = .{ 0.0, 0.0, 0.0 },
    scale: [3]f32 = .{ 1.0, 1.0, 1.0 },
};

pub const CubeRenderer = struct {
    color: [3]f32 = .{ 0.0, 0.56, 1.0 },
};

pub const GeometryPrimitive = struct {
    primitive: []const u8 = "box",
    segments: i32 = 0,
    rings: i32 = 0,
};

pub const SurfaceMaterial = struct {
    base_color: [3]f32 = .{ 0.0, 0.56, 1.0 },
};

pub const Camera = struct {
    fov_y_degrees: f32 = 48.0,
    near: f32 = 0.1,
    far: f32 = 100.0,
};

pub const DirectionalLight = struct {
    direction: [3]f32 = .{ 0.35, 0.68, 0.64 },
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
    intensity: f32 = 0.78,
    ambient: f32 = 0.18,
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

pub const RenderableMesh = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    position: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
    primitive: []const u8,
    segments: i32,
    rings: i32,
    base_color: [3]f32,
    spin: [3]f32,
    casts_shadow: bool,
    receives_shadow: bool,
};

pub const RenderCamera = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    transform: Transform,
    fov_y_degrees: f32,
    near: f32,
    far: f32,
};

pub const RenderDirectionalLight = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    direction: [3]f32,
    color: [3]f32,
    intensity: f32,
    ambient: f32,
};

pub const UiRectComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
    corner_radius: f32 = 0.0,
};

pub const UiTextComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    size: f32 = 2.0,
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
    value: []const u8 = "",
};

pub const UiCommandComponent = struct {
    command: []const u8,
};

pub const UiScrollViewComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
    content_offset: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

pub const UiVBoxComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    spacing: f32 = 0.0,
};

pub const UiStackComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    spacing: f32 = 0.0,
    direction: []const u8 = "vertical",
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

pub const UiLayoutItemComponent = struct {
    parent: []const u8,
    order: i32 = 0,
    min_size: [3]f32 = .{ 0.0, 0.0, 0.0 },
    grow: f32 = 0.0,
    @"align": []const u8 = "start",
};

pub const UiSpacerComponent = struct {
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
};

pub const UiTextBlockComponent = struct {
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
    horizontal_align: []const u8 = "start",
    vertical_align: []const u8 = "start",
};

pub const UiToggleComponent = struct {
    checked: bool = false,
};

pub const UiProgressBarComponent = struct {
    value: f32 = 0.0,
    max: f32 = 1.0,
    fill_color: [3]f32 = .{ 0.22, 0.714, 0.82 },
};

pub const UiSeparatorComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
};

pub const UiCommandEventComponent = struct {
    command: []const u8,
    source: []const u8,
};

pub const UiCommandEvent = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    command: []const u8,
    source: []const u8,
};

pub const UiRect = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    position: [3]f32,
    size: [3]f32,
    color: [3]f32,
    corner_radius: f32,
    is_button: bool,
};

pub const UiText = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    position: [3]f32,
    size: f32,
    color: [3]f32,
    value: []const u8,
};

pub const UiSeparator = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    position: [3]f32,
    size: [3]f32,
    color: [3]f32,
};

pub const InputPointerComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    has_position: bool = false,
    primary_down: bool = false,
    primary_pressed: bool = false,
    primary_released: bool = false,
    wheel_delta: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

pub const InputKeyboardComponent = struct {
    ctrl_down: bool = false,
    shift_down: bool = false,
    alt_down: bool = false,
    super_down: bool = false,
    editor_toggle_pressed: bool = false,
};

pub const InputFrameComponent = struct {
    ui_visible: bool = true,
    debug_overlay_visible: bool = false,
    viewport: [3]f32 = .{ 0.0, 0.0, 0.0 },
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

    fn swapRemove(self: *ComponentColumnValues, allocator: std.mem.Allocator, row: usize) void {
        switch (self.*) {
            .boolean => |*values| {
                values.items[row] = values.items[values.items.len - 1];
                _ = values.pop();
            },
            .int => |*values| {
                values.items[row] = values.items[values.items.len - 1];
                _ = values.pop();
            },
            .float => |*values| {
                values.items[row] = values.items[values.items.len - 1];
                _ = values.pop();
            },
            .vec3 => |*values| {
                values.items[row] = values.items[values.items.len - 1];
                _ = values.pop();
            },
            .string => |*values| {
                const last_index = values.items.len - 1;
                if (row == last_index) {
                    allocator.free(values.pop().?);
                } else {
                    allocator.free(values.items[row]);
                    values.items[row] = values.items[last_index];
                    _ = values.pop();
                }
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
    query_plan_generation: u64 = 1,
    next_entity_generation: u32 = 1,

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

    pub fn queryPlanGeneration(self: World) u64 {
        return self.query_plan_generation;
    }

    pub fn createEntity(self: *World, id: []const u8, name: []const u8) !EntityHandle {
        if (self.findEntityById(id) != null) {
            return WorldError.DuplicateEntityId;
        }

        const owned_id = try self.allocator.dupe(u8, id);
        errdefer self.allocator.free(owned_id);
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        const generation = self.nextEntityGeneration();
        const handle = EntityHandle{
            .index = @intCast(self.entities.items.len),
            .generation = generation,
        };
        try self.entities.append(self.allocator, .{
            .id = owned_id,
            .name = owned_name,
            .generation = generation,
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

    pub fn componentInstanceCount(self: World) usize {
        var count: usize = 0;
        for (self.component_tables.items) |table| {
            count += table.entities.items.len;
        }
        return count;
    }

    pub fn componentInstanceCountFor(self: World, component_id: []const u8) usize {
        const table = self.findComponentTable(component_id) orelse return 0;
        return table.entities.items.len;
    }

    pub fn componentFieldCount(self: World, component_id: []const u8) usize {
        const table = self.findComponentTable(component_id) orelse return 0;
        return table.columns.len;
    }

    pub fn componentFieldNameAt(self: World, component_id: []const u8, field_index: usize) ?[]const u8 {
        const table = self.findComponentTable(component_id) orelse return null;
        if (field_index >= table.columns.len) {
            return null;
        }
        return table.columns[field_index].name;
    }

    pub fn entity(self: World, handle: EntityHandle) WorldError!Entity {
        const index = handle.index;
        if (index >= self.entities.items.len) {
            return WorldError.InvalidEntity;
        }
        if (handle.generation != 0 and self.entities.items[index].generation != handle.generation) {
            return WorldError.InvalidEntity;
        }
        return self.entities.items[index];
    }

    pub fn entityComponents(self: *const World, handle: EntityHandle) WorldError!EntityComponentIterator {
        _ = try self.componentIndex(handle);
        return .{
            .world = self,
            .handle = handle,
        };
    }

    pub fn findEntityById(self: World, id: []const u8) ?EntityHandle {
        for (self.entities.items, 0..) |stored_entity, index| {
            if (std.mem.eql(u8, stored_entity.id, id)) {
                return .{
                    .index = @intCast(index),
                    .generation = stored_entity.generation,
                };
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

    pub fn setGeometryPrimitive(self: *World, handle: EntityHandle, primitive: GeometryPrimitive) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "primitive", .value = .{ .string = primitive.primitive } },
            .{ .name = "segments", .value = .{ .int = primitive.segments } },
            .{ .name = "rings", .value = .{ .int = primitive.rings } },
        };
        try self.setComponent(handle, geometry_primitive_component_id, &fields);
    }

    pub fn setSurfaceMaterial(self: *World, handle: EntityHandle, material: SurfaceMaterial) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "base_color", .value = .{ .vec3 = material.base_color } },
        };
        try self.setComponent(handle, surface_material_component_id, &fields);
    }

    pub fn setCamera(self: *World, handle: EntityHandle, camera: Camera) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "fov_y_degrees", .value = .{ .float = camera.fov_y_degrees } },
            .{ .name = "near", .value = .{ .float = camera.near } },
            .{ .name = "far", .value = .{ .float = camera.far } },
        };
        try self.setComponent(handle, camera_component_id, &fields);
    }

    pub fn setDirectionalLight(self: *World, handle: EntityHandle, light: DirectionalLight) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "direction", .value = .{ .vec3 = light.direction } },
            .{ .name = "color", .value = .{ .vec3 = light.color } },
            .{ .name = "intensity", .value = .{ .float = light.intensity } },
            .{ .name = "ambient", .value = .{ .float = light.ambient } },
        };
        try self.setComponent(handle, directional_light_component_id, &fields);
    }

    pub fn setShadowCaster(self: *World, handle: EntityHandle) WorldError!void {
        try self.setComponent(handle, shadow_caster_component_id, &.{});
    }

    pub fn setShadowReceiver(self: *World, handle: EntityHandle) WorldError!void {
        try self.setComponent(handle, shadow_receiver_component_id, &.{});
    }

    pub fn setUiCanvas(self: *World, handle: EntityHandle) WorldError!void {
        try self.setComponent(handle, ui_canvas_component_id, &.{});
    }

    pub fn setUiRect(self: *World, handle: EntityHandle, rect: UiRectComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = rect.position } },
            .{ .name = "size", .value = .{ .vec3 = rect.size } },
            .{ .name = "color", .value = .{ .vec3 = rect.color } },
            .{ .name = "corner_radius", .value = .{ .float = rect.corner_radius } },
        };
        try self.setComponent(handle, ui_rect_component_id, &fields);
    }

    pub fn setUiText(self: *World, handle: EntityHandle, text: UiTextComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = text.position } },
            .{ .name = "size", .value = .{ .float = text.size } },
            .{ .name = "color", .value = .{ .vec3 = text.color } },
            .{ .name = "value", .value = .{ .string = text.value } },
        };
        try self.setComponent(handle, ui_text_component_id, &fields);
    }

    pub fn setUiButton(self: *World, handle: EntityHandle) WorldError!void {
        try self.setComponent(handle, ui_button_component_id, &.{});
    }

    pub fn setUiCommand(self: *World, handle: EntityHandle, command: UiCommandComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "command", .value = .{ .string = command.command } },
        };
        try self.setComponent(handle, ui_command_component_id, &fields);
    }

    pub fn setUiScrollView(self: *World, handle: EntityHandle, scroll_view: UiScrollViewComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = scroll_view.position } },
            .{ .name = "size", .value = .{ .vec3 = scroll_view.size } },
            .{ .name = "content_offset", .value = .{ .vec3 = scroll_view.content_offset } },
        };
        try self.setComponent(handle, ui_scroll_view_component_id, &fields);
    }

    pub fn setUiVBox(self: *World, handle: EntityHandle, vbox: UiVBoxComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = vbox.position } },
            .{ .name = "spacing", .value = .{ .float = vbox.spacing } },
        };
        try self.setComponent(handle, ui_vbox_component_id, &fields);
    }

    pub fn setUiStack(self: *World, handle: EntityHandle, stack: UiStackComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = stack.position } },
            .{ .name = "spacing", .value = .{ .float = stack.spacing } },
            .{ .name = "direction", .value = .{ .string = stack.direction } },
            .{ .name = "padding", .value = .{ .vec3 = stack.padding } },
        };
        try self.setComponent(handle, ui_stack_component_id, &fields);
    }

    pub fn setUiLayoutItem(self: *World, handle: EntityHandle, item: UiLayoutItemComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "parent", .value = .{ .string = item.parent } },
            .{ .name = "order", .value = .{ .int = item.order } },
            .{ .name = "min_size", .value = .{ .vec3 = item.min_size } },
            .{ .name = "grow", .value = .{ .float = item.grow } },
            .{ .name = "align", .value = .{ .string = item.@"align" } },
        };
        try self.setComponent(handle, ui_layout_item_component_id, &fields);
    }

    pub fn setUiSpacer(self: *World, handle: EntityHandle, spacer: UiSpacerComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "size", .value = .{ .vec3 = spacer.size } },
        };
        try self.setComponent(handle, ui_spacer_component_id, &fields);
    }

    pub fn setUiTextBlock(self: *World, handle: EntityHandle, text_block: UiTextBlockComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "size", .value = .{ .vec3 = text_block.size } },
            .{ .name = "horizontal_align", .value = .{ .string = text_block.horizontal_align } },
            .{ .name = "vertical_align", .value = .{ .string = text_block.vertical_align } },
        };
        try self.setComponent(handle, ui_text_block_component_id, &fields);
    }

    pub fn setUiToggle(self: *World, handle: EntityHandle, toggle: UiToggleComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "checked", .value = .{ .boolean = toggle.checked } },
        };
        try self.setComponent(handle, ui_toggle_component_id, &fields);
    }

    pub fn setUiProgressBar(self: *World, handle: EntityHandle, progress: UiProgressBarComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "value", .value = .{ .float = progress.value } },
            .{ .name = "max", .value = .{ .float = progress.max } },
            .{ .name = "fill_color", .value = .{ .vec3 = progress.fill_color } },
        };
        try self.setComponent(handle, ui_progress_bar_component_id, &fields);
    }

    pub fn setUiSeparator(self: *World, handle: EntityHandle, separator: UiSeparatorComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = separator.position } },
            .{ .name = "size", .value = .{ .vec3 = separator.size } },
            .{ .name = "color", .value = .{ .vec3 = separator.color } },
        };
        try self.setComponent(handle, ui_separator_component_id, &fields);
    }

    pub fn setUiCommandEvent(self: *World, handle: EntityHandle, event: UiCommandEventComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "command", .value = .{ .string = event.command } },
            .{ .name = "source", .value = .{ .string = event.source } },
        };
        try self.setComponent(handle, ui_command_event_component_id, &fields);
    }

    pub fn setInputPointer(self: *World, handle: EntityHandle, pointer: InputPointerComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = pointer.position } },
            .{ .name = "has_position", .value = .{ .boolean = pointer.has_position } },
            .{ .name = "primary_down", .value = .{ .boolean = pointer.primary_down } },
            .{ .name = "primary_pressed", .value = .{ .boolean = pointer.primary_pressed } },
            .{ .name = "primary_released", .value = .{ .boolean = pointer.primary_released } },
            .{ .name = "wheel_delta", .value = .{ .vec3 = pointer.wheel_delta } },
        };
        try self.setComponent(handle, input_pointer_component_id, &fields);
    }

    pub fn setInputKeyboard(self: *World, handle: EntityHandle, keyboard: InputKeyboardComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "ctrl_down", .value = .{ .boolean = keyboard.ctrl_down } },
            .{ .name = "shift_down", .value = .{ .boolean = keyboard.shift_down } },
            .{ .name = "alt_down", .value = .{ .boolean = keyboard.alt_down } },
            .{ .name = "super_down", .value = .{ .boolean = keyboard.super_down } },
            .{ .name = "editor_toggle_pressed", .value = .{ .boolean = keyboard.editor_toggle_pressed } },
        };
        try self.setComponent(handle, input_keyboard_component_id, &fields);
    }

    pub fn setInputFrame(self: *World, handle: EntityHandle, frame: InputFrameComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "ui_visible", .value = .{ .boolean = frame.ui_visible } },
            .{ .name = "debug_overlay_visible", .value = .{ .boolean = frame.debug_overlay_visible } },
            .{ .name = "viewport", .value = .{ .vec3 = frame.viewport } },
        };
        try self.setComponent(handle, input_frame_component_id, &fields);
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

    pub fn getFloat(self: World, handle: EntityHandle, component_id: []const u8, field_name: []const u8) WorldError!f32 {
        const value = try self.getFieldValue(handle, component_id, field_name);
        return switch (value) {
            .float => |payload| payload,
            else => WorldError.InvalidFieldType,
        };
    }

    pub fn getBoolean(self: World, handle: EntityHandle, component_id: []const u8, field_name: []const u8) WorldError!bool {
        const value = try self.getFieldValue(handle, component_id, field_name);
        return switch (value) {
            .boolean => |payload| payload,
            else => WorldError.InvalidFieldType,
        };
    }

    pub fn getInt(self: World, handle: EntityHandle, component_id: []const u8, field_name: []const u8) WorldError!i32 {
        const value = try self.getFieldValue(handle, component_id, field_name);
        return switch (value) {
            .int => |payload| payload,
            else => WorldError.InvalidFieldType,
        };
    }

    pub fn getString(self: World, handle: EntityHandle, component_id: []const u8, field_name: []const u8) WorldError![]const u8 {
        const value = try self.getFieldValue(handle, component_id, field_name);
        return switch (value) {
            .string => |payload| payload,
            else => WorldError.InvalidFieldType,
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

    pub fn removeComponent(self: *World, handle: EntityHandle, component_id: []const u8) WorldError!bool {
        const entity_index = try self.componentIndex(handle);
        const table = self.findMutableComponentTable(component_id) orelse return false;
        if (entity_index >= table.rows_by_entity.items.len) {
            return false;
        }
        const row = table.rows_by_entity.items[entity_index] orelse return false;
        const last_row = table.entities.items.len - 1;
        const removed_entity = table.entities.items[row];
        const moved_entity = table.entities.items[last_row];

        table.entities.items[row] = moved_entity;
        _ = table.entities.pop();
        table.rows_by_entity.items[removed_entity.index] = null;
        if (row != last_row) {
            table.rows_by_entity.items[moved_entity.index] = row;
        }

        for (table.columns) |*column| {
            column.values.swapRemove(self.allocator, row);
        }

        return true;
    }

    pub fn removeEntity(self: *World, handle: EntityHandle) WorldError!bool {
        const entity_index = try self.componentIndex(handle);
        const last_entity_index = self.entities.items.len - 1;

        while (true) {
            var removed_component = false;
            for (self.component_tables.items) |*table| {
                if (entity_index < table.rows_by_entity.items.len and table.rows_by_entity.items[entity_index] != null) {
                    _ = try self.removeComponent(handle, table.id);
                    removed_component = true;
                    break;
                }
            }
            if (!removed_component) {
                break;
            }
        }

        self.allocator.free(self.entities.items[entity_index].id);
        self.allocator.free(self.entities.items[entity_index].name);

        if (entity_index != last_entity_index) {
            self.entities.items[entity_index] = self.entities.items[last_entity_index];
        }
        _ = self.entities.pop();

        for (self.component_tables.items) |*table| {
            const moved_row = if (entity_index != last_entity_index and last_entity_index < table.rows_by_entity.items.len) table.rows_by_entity.items[last_entity_index] else null;
            if (entity_index < table.rows_by_entity.items.len) {
                table.rows_by_entity.items[entity_index] = moved_row;
            }
            if (moved_row) |row| {
                table.entities.items[row] = .{
                    .index = @intCast(entity_index),
                    .generation = self.entities.items[entity_index].generation,
                };
            }
            if (table.rows_by_entity.items.len > 0) {
                _ = table.rows_by_entity.pop();
            }
        }

        return true;
    }

    pub fn hasComponent(self: World, handle: EntityHandle, component_id: []const u8) WorldError!bool {
        const index = try self.componentIndex(handle);
        const table = self.findComponentTable(component_id) orelse return false;
        if (index >= table.rows_by_entity.items.len) {
            return false;
        }
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

    pub fn resolveComponentTableIndex(self: World, component_id: []const u8) ?u32 {
        for (self.component_tables.items, 0..) |table, index| {
            if (std.mem.eql(u8, table.id, component_id)) {
                return @intCast(index);
            }
        }
        return null;
    }

    pub fn queryDriverTableIndex(self: World, component_table_indices: []const u32) WorldError!?u32 {
        if (component_table_indices.len == 0) {
            return null;
        }

        var driver_index: ?u32 = null;
        var driver_len: usize = std.math.maxInt(usize);
        for (component_table_indices) |table_index| {
            const table = try self.componentTableAt(table_index);
            if (driver_index == null or table.entities.items.len < driver_len) {
                driver_index = table_index;
                driver_len = table.entities.items.len;
            }
        }
        return driver_index;
    }

    pub fn queryNextResolved(
        self: World,
        component_table_indices: []const u32,
        driver_table_index: u32,
        cursor: *usize,
        out_rows: []u32,
    ) WorldError!?EntityHandle {
        if (component_table_indices.len == 0 or out_rows.len < component_table_indices.len) {
            return WorldError.UnknownComponent;
        }

        const driver = try self.componentTableAt(driver_table_index);
        while (cursor.* < driver.entities.items.len) : (cursor.* += 1) {
            const handle = driver.entities.items[cursor.*];
            var matches = true;
            for (component_table_indices, 0..) |table_index, index| {
                const table = try self.componentTableAt(table_index);
                const row = rowForEntity(table.*, handle) orelse {
                    matches = false;
                    break;
                };
                out_rows[index] = @intCast(row);
            }

            if (matches) {
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

    pub fn getComponentFieldValueResolved(self: World, handle: EntityHandle, resolved: ResolvedComponentRow, field_name: []const u8) WorldError!ComponentValue {
        return self.getFieldValueResolved(handle, resolved, field_name);
    }

    pub fn setComponentFieldValue(self: *World, handle: EntityHandle, component_id: []const u8, field_name: []const u8, value: ComponentValue) WorldError!void {
        try self.setFieldValue(handle, component_id, field_name, value);
    }

    pub fn setComponentFieldValueResolved(self: *World, handle: EntityHandle, resolved: ResolvedComponentRow, field_name: []const u8, value: ComponentValue) WorldError!void {
        try self.setFieldValueResolved(handle, resolved, field_name, value);
    }

    pub fn renderableCubeCount(self: World) usize {
        return self.renderableMeshCount();
    }

    pub fn renderableMeshCount(self: World) usize {
        var count: usize = 0;
        for (0..self.entityCount()) |index| {
            if (self.renderableMeshAtEntity(.{ .index = @intCast(index) }) != null) {
                count += 1;
            }
        }
        return count;
    }

    pub fn renderableCubeAt(self: World, render_index: usize) ?RenderableCube {
        const mesh = self.renderableMeshAt(render_index) orelse return null;
        return .{
            .entity = mesh.entity,
            .id = mesh.id,
            .name = mesh.name,
            .position = mesh.position,
            .rotation = mesh.rotation,
            .scale = mesh.scale,
            .color = mesh.base_color,
            .spin = mesh.spin,
        };
    }

    pub fn renderableMeshAt(self: World, render_index: usize) ?RenderableMesh {
        var found: usize = 0;
        for (0..self.entityCount()) |index| {
            const handle = EntityHandle{ .index = @intCast(index) };
            const mesh = self.renderableMeshAtEntity(handle) orelse continue;
            if (found == render_index) {
                return mesh;
            }
            found += 1;
        }
        return null;
    }

    pub fn renderableCubes(self: *const World) RenderableCubeIterator {
        return .{ .world = self };
    }

    pub fn renderableMeshes(self: *const World) RenderableMeshIterator {
        return .{ .world = self };
    }

    pub fn uiRectCount(self: World) usize {
        return self.componentInstanceCountFor(ui_rect_component_id);
    }

    pub fn uiRectAt(self: World, ui_index: usize) ?UiRect {
        var found: usize = 0;
        for (0..self.entityCount()) |index| {
            const rect = self.uiRectAtEntity(.{ .index = @intCast(index) }) orelse continue;
            if (found == ui_index) {
                return rect;
            }
            found += 1;
        }
        return null;
    }

    pub fn uiRects(self: *const World) UiRectIterator {
        return .{ .world = self };
    }

    pub fn uiTextCount(self: World) usize {
        return self.componentInstanceCountFor(ui_text_component_id);
    }

    pub fn uiTextAt(self: World, ui_index: usize) ?UiText {
        var found: usize = 0;
        for (0..self.entityCount()) |index| {
            const text = self.uiTextAtEntity(.{ .index = @intCast(index) }) orelse continue;
            if (found == ui_index) {
                return text;
            }
            found += 1;
        }
        return null;
    }

    pub fn uiTexts(self: *const World) UiTextIterator {
        return .{ .world = self };
    }

    pub fn uiSeparatorCount(self: World) usize {
        return self.componentInstanceCountFor(ui_separator_component_id);
    }

    pub fn uiSeparatorAt(self: World, ui_index: usize) ?UiSeparator {
        var found: usize = 0;
        for (0..self.entityCount()) |index| {
            const separator = self.uiSeparatorAtEntity(.{ .index = @intCast(index) }) orelse continue;
            if (found == ui_index) {
                return separator;
            }
            found += 1;
        }
        return null;
    }

    pub fn uiSeparators(self: *const World) UiSeparatorIterator {
        return .{ .world = self };
    }

    pub fn uiCommandEvent(self: World) ?UiCommandEvent {
        var cursor: usize = 0;
        const component_ids = [_][]const u8{ui_command_event_component_id};
        const handle = self.queryNext(&component_ids, &cursor) orelse return null;
        const stored_entity = self.entity(handle) catch return null;
        return .{
            .entity = handle,
            .id = stored_entity.id,
            .name = stored_entity.name,
            .command = self.getString(handle, ui_command_event_component_id, "command") catch return null,
            .source = self.getString(handle, ui_command_event_component_id, "source") catch return null,
        };
    }

    fn renderableMeshAtEntity(self: World, handle: EntityHandle) ?RenderableMesh {
        const stored_entity = self.entity(handle) catch return null;
        const stored_handle = EntityHandle{
            .index = handle.index,
            .generation = stored_entity.generation,
        };
        const transform = (self.getTransform(handle) catch return null) orelse return null;
        const spin = self.getVec3(handle, spin_component_id, "angular_velocity") catch .{ 0.0, 0.0, 0.0 };
        const casts_shadow = self.hasComponent(handle, shadow_caster_component_id) catch false;
        const receives_shadow = self.hasComponent(handle, shadow_receiver_component_id) catch false;

        if ((self.hasComponent(handle, geometry_primitive_component_id) catch false) and
            (self.hasComponent(handle, surface_material_component_id) catch false))
        {
            return .{
                .entity = stored_handle,
                .id = stored_entity.id,
                .name = stored_entity.name,
                .position = transform.position,
                .rotation = transform.rotation,
                .scale = transform.scale,
                .primitive = self.getString(handle, geometry_primitive_component_id, "primitive") catch return null,
                .segments = self.getInt(handle, geometry_primitive_component_id, "segments") catch return null,
                .rings = self.getInt(handle, geometry_primitive_component_id, "rings") catch return null,
                .base_color = self.getVec3(handle, surface_material_component_id, "base_color") catch return null,
                .spin = spin,
                .casts_shadow = casts_shadow,
                .receives_shadow = receives_shadow,
            };
        }

        if (self.hasComponent(handle, cube_renderer_component_id) catch false) {
            return .{
                .entity = stored_handle,
                .id = stored_entity.id,
                .name = stored_entity.name,
                .position = transform.position,
                .rotation = transform.rotation,
                .scale = transform.scale,
                .primitive = "box",
                .segments = 0,
                .rings = 0,
                .base_color = self.getVec3(handle, cube_renderer_component_id, "color") catch return null,
                .spin = spin,
                .casts_shadow = casts_shadow,
                .receives_shadow = receives_shadow,
            };
        }

        return null;
    }

    fn uiRectAtEntity(self: World, handle: EntityHandle) ?UiRect {
        const stored_entity = self.entity(handle) catch return null;
        if (!(self.hasComponent(handle, ui_rect_component_id) catch false)) {
            return null;
        }
        return .{
            .entity = handle,
            .id = stored_entity.id,
            .name = stored_entity.name,
            .position = self.getVec3(handle, ui_rect_component_id, "position") catch return null,
            .size = self.getVec3(handle, ui_rect_component_id, "size") catch return null,
            .color = self.getVec3(handle, ui_rect_component_id, "color") catch return null,
            .corner_radius = self.getFloat(handle, ui_rect_component_id, "corner_radius") catch return null,
            .is_button = self.hasComponent(handle, ui_button_component_id) catch false,
        };
    }

    fn uiTextAtEntity(self: World, handle: EntityHandle) ?UiText {
        const stored_entity = self.entity(handle) catch return null;
        if (!(self.hasComponent(handle, ui_text_component_id) catch false)) {
            return null;
        }
        return .{
            .entity = handle,
            .id = stored_entity.id,
            .name = stored_entity.name,
            .position = self.getVec3(handle, ui_text_component_id, "position") catch return null,
            .size = self.getFloat(handle, ui_text_component_id, "size") catch return null,
            .color = self.getVec3(handle, ui_text_component_id, "color") catch return null,
            .value = self.getString(handle, ui_text_component_id, "value") catch return null,
        };
    }

    fn uiSeparatorAtEntity(self: World, handle: EntityHandle) ?UiSeparator {
        const stored_entity = self.entity(handle) catch return null;
        if (!(self.hasComponent(handle, ui_separator_component_id) catch false)) {
            return null;
        }
        return .{
            .entity = handle,
            .id = stored_entity.id,
            .name = stored_entity.name,
            .position = self.getVec3(handle, ui_separator_component_id, "position") catch return null,
            .size = self.getVec3(handle, ui_separator_component_id, "size") catch return null,
            .color = self.getVec3(handle, ui_separator_component_id, "color") catch return null,
        };
    }

    pub fn renderCamera(self: World) ?RenderCamera {
        var cursor: usize = 0;
        const component_ids = [_][]const u8{ transform_component_id, camera_component_id };
        const handle = self.queryNext(&component_ids, &cursor) orelse return null;
        const stored_entity = self.entity(handle) catch return null;
        const transform = (self.getTransform(handle) catch return null) orelse return null;
        return .{
            .entity = handle,
            .id = stored_entity.id,
            .name = stored_entity.name,
            .transform = transform,
            .fov_y_degrees = self.getFloat(handle, camera_component_id, "fov_y_degrees") catch return null,
            .near = self.getFloat(handle, camera_component_id, "near") catch return null,
            .far = self.getFloat(handle, camera_component_id, "far") catch return null,
        };
    }

    pub fn renderDirectionalLight(self: World) ?RenderDirectionalLight {
        var cursor: usize = 0;
        const component_ids = [_][]const u8{directional_light_component_id};
        const handle = self.queryNext(&component_ids, &cursor) orelse return null;
        const stored_entity = self.entity(handle) catch return null;
        return .{
            .entity = handle,
            .id = stored_entity.id,
            .name = stored_entity.name,
            .direction = self.getVec3(handle, directional_light_component_id, "direction") catch return null,
            .color = self.getVec3(handle, directional_light_component_id, "color") catch return null,
            .intensity = self.getFloat(handle, directional_light_component_id, "intensity") catch return null,
            .ambient = self.getFloat(handle, directional_light_component_id, "ambient") catch return null,
        };
    }

    fn componentIndex(self: World, handle: EntityHandle) WorldError!usize {
        const index = handle.index;
        if (index >= self.entities.items.len) {
            return WorldError.InvalidEntity;
        }
        if (handle.generation != 0 and self.entities.items[index].generation != handle.generation) {
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

    fn componentTableAt(self: World, table_index: u32) WorldError!*const ComponentTable {
        const index: usize = table_index;
        if (index >= self.component_tables.items.len) {
            return WorldError.UnknownComponent;
        }
        return &self.component_tables.items[index];
    }

    fn mutableComponentTableAt(self: *World, table_index: u32) WorldError!*ComponentTable {
        const index: usize = table_index;
        if (index >= self.component_tables.items.len) {
            return WorldError.UnknownComponent;
        }
        return &self.component_tables.items[index];
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
        if (index >= table.rows_by_entity.items.len) {
            return WorldError.UnknownComponent;
        }
        const row = table.rows_by_entity.items[index] orelse return WorldError.UnknownComponent;
        const column = findColumn(table.*, field_name) orelse return WorldError.UnknownField;
        return column.values.valueAt(row);
    }

    fn getFieldValueResolved(self: World, handle: EntityHandle, resolved: ResolvedComponentRow, field_name: []const u8) WorldError!ComponentValue {
        const index = try self.componentIndex(handle);
        const table = try self.componentTableAt(resolved.table_index);
        const row = resolvedRowForEntity(table.*, .{ .index = @intCast(index) }, resolved.row_index) orelse return WorldError.UnknownComponent;
        const column = findColumn(table.*, field_name) orelse return WorldError.UnknownField;
        return column.values.valueAt(row);
    }

    fn setFieldValue(self: *World, handle: EntityHandle, component_id: []const u8, field_name: []const u8, value: ComponentValue) WorldError!void {
        const index = try self.componentIndex(handle);
        const table = self.findMutableComponentTable(component_id) orelse return WorldError.UnknownComponent;
        if (index >= table.rows_by_entity.items.len) {
            return WorldError.UnknownComponent;
        }
        const row = table.rows_by_entity.items[index] orelse return WorldError.UnknownComponent;
        const column = findMutableColumn(table, field_name) orelse return WorldError.UnknownField;
        try column.values.setCopy(self.allocator, row, value);
    }

    fn setFieldValueResolved(self: *World, handle: EntityHandle, resolved: ResolvedComponentRow, field_name: []const u8, value: ComponentValue) WorldError!void {
        const index = try self.componentIndex(handle);
        const table = try self.mutableComponentTableAt(resolved.table_index);
        const row = resolvedRowForEntity(table.*, .{ .index = @intCast(index) }, resolved.row_index) orelse return WorldError.UnknownComponent;
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
        self.bumpQueryPlanGeneration();
        return self.component_tables.items.len - 1;
    }

    fn bumpQueryPlanGeneration(self: *World) void {
        self.query_plan_generation +%= 1;
        if (self.query_plan_generation == 0) {
            self.query_plan_generation = 1;
        }
    }

    fn nextEntityGeneration(self: *World) u32 {
        const generation = self.next_entity_generation;
        self.next_entity_generation +%= 1;
        if (self.next_entity_generation == 0) {
            self.next_entity_generation = 1;
        }
        return generation;
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

fn rowForEntity(table: ComponentTable, handle: EntityHandle) ?usize {
    const entity_index: usize = handle.index;
    if (entity_index >= table.rows_by_entity.items.len) {
        return null;
    }
    const row = table.rows_by_entity.items[entity_index] orelse return null;
    if (row >= table.entities.items.len or
        table.entities.items[row].index != handle.index or
        (handle.generation != 0 and table.entities.items[row].generation != handle.generation))
    {
        return null;
    }
    return row;
}

fn resolvedRowForEntity(table: ComponentTable, handle: EntityHandle, row_index: u32) ?usize {
    const row: usize = row_index;
    if (row < table.entities.items.len and
        table.entities.items[row].index == handle.index and
        (handle.generation == 0 or table.entities.items[row].generation == handle.generation))
    {
        return row;
    }
    return rowForEntity(table, handle);
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
        while (self.index < self.world.entityCount()) {
            const handle = EntityHandle{ .index = @intCast(self.index) };
            self.index += 1;
            const mesh = self.world.renderableMeshAtEntity(handle) orelse continue;
            return .{
                .entity = mesh.entity,
                .id = mesh.id,
                .name = mesh.name,
                .position = mesh.position,
                .rotation = mesh.rotation,
                .scale = mesh.scale,
                .color = mesh.base_color,
                .spin = mesh.spin,
            };
        }
        return null;
    }
};

pub const RenderableMeshIterator = struct {
    world: *const World,
    index: usize = 0,

    pub fn next(self: *RenderableMeshIterator) ?RenderableMesh {
        while (self.index < self.world.entityCount()) {
            const handle = EntityHandle{ .index = @intCast(self.index) };
            self.index += 1;
            return self.world.renderableMeshAtEntity(handle) orelse continue;
        }
        return null;
    }
};

pub const UiRectIterator = struct {
    world: *const World,
    index: usize = 0,

    pub fn next(self: *UiRectIterator) ?UiRect {
        while (self.index < self.world.entityCount()) {
            const handle = EntityHandle{ .index = @intCast(self.index) };
            self.index += 1;
            return self.world.uiRectAtEntity(handle) orelse continue;
        }
        return null;
    }
};

pub const UiTextIterator = struct {
    world: *const World,
    index: usize = 0,

    pub fn next(self: *UiTextIterator) ?UiText {
        while (self.index < self.world.entityCount()) {
            const handle = EntityHandle{ .index = @intCast(self.index) };
            self.index += 1;
            return self.world.uiTextAtEntity(handle) orelse continue;
        }
        return null;
    }
};

pub const UiSeparatorIterator = struct {
    world: *const World,
    index: usize = 0,

    pub fn next(self: *UiSeparatorIterator) ?UiSeparator {
        while (self.index < self.world.entityCount()) {
            const handle = EntityHandle{ .index = @intCast(self.index) };
            self.index += 1;
            return self.world.uiSeparatorAtEntity(handle) orelse continue;
        }
        return null;
    }
};

pub fn validateTypeId(id: []const u8) TypeIdError!void {
    _ = try validateTypeIdShape(id);
}

pub fn pointInsideUiRect(point: [2]f32, position: [3]f32, size: [3]f32) bool {
    if (!std.math.isFinite(point[0]) or !std.math.isFinite(point[1]) or
        !isFiniteVec3(position) or !isFiniteVec3(size) or size[0] <= 0.0 or size[1] <= 0.0)
    {
        return false;
    }

    return point[0] >= position[0] and
        point[1] >= position[1] and
        point[0] < position[0] + size[0] and
        point[1] < position[1] + size[1];
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

fn isFiniteVec3(value: [3]f32) bool {
    return std.math.isFinite(value[0]) and std.math.isFinite(value[1]) and std.math.isFinite(value[2]);
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
            .native => false,
        },
        .native => |left_ref| switch (right) {
            .none => false,
            .luau => false,
            .native => |right_ref| left_ref == right_ref,
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
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(cube_renderer_component_id));
    try std.testing.expectEqual(@as(usize, 0), world.componentInstanceCountFor(camera_component_id));

    const found = world.findEntityById("entity-1") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(entity.index, found.index);

    const cube = world.renderableCubeAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("entity-1", cube.id);
    try std.testing.expectEqual(@as(f32, 2.0), cube.position[1]);
    try std.testing.expectEqual(@as(f32, 1.0), cube.color[0]);

    const mesh = world.renderableMeshAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("box", mesh.primitive);
    try std.testing.expectEqual(@as(f32, 1.0), mesh.base_color[0]);
    try std.testing.expectEqual(entity.generation, mesh.entity.generation);
}

test "world exposes component field names for inspection" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("entity-1", "Player");
    try world.setTransform(entity, .{ .position = .{ 1.0, 2.0, 3.0 } });

    try std.testing.expectEqual(@as(usize, 3), world.componentFieldCount(transform_component_id));
    try std.testing.expectEqualStrings("position", world.componentFieldNameAt(transform_component_id, 0) orelse return error.TestExpectedEqual);
    try std.testing.expectEqualStrings("rotation", world.componentFieldNameAt(transform_component_id, 1) orelse return error.TestExpectedEqual);
    try std.testing.expectEqualStrings("scale", world.componentFieldNameAt(transform_component_id, 2) orelse return error.TestExpectedEqual);
    try std.testing.expect(world.componentFieldNameAt(transform_component_id, 3) == null);
    try std.testing.expectEqual(@as(usize, 0), world.componentFieldCount("missing.component"));

    const value = try world.getComponentFieldValue(entity, transform_component_id, "position");
    switch (value) {
        .vec3 => |payload| try std.testing.expectEqual(@as(f32, 2.0), payload[1]),
        else => return error.TestExpectedEqual,
    }
}

test "world stores frame input components on a shared input entity" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const input = try world.createEntity(input_entity_id, "Input Frame");
    try world.setInputPointer(input, .{
        .position = .{ 12.0, 34.0, 0.0 },
        .has_position = true,
        .primary_down = true,
        .wheel_delta = .{ 0.0, -2.0, 0.0 },
    });
    try world.setInputKeyboard(input, .{
        .ctrl_down = true,
        .editor_toggle_pressed = true,
    });
    try world.setInputFrame(input, .{
        .ui_visible = true,
        .debug_overlay_visible = true,
        .viewport = .{ 1280.0, 720.0, 0.0 },
    });

    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(input_pointer_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(input_keyboard_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(input_frame_component_id));
    try std.testing.expectEqual(@as(f32, -2.0), (try world.getVec3(input, input_pointer_component_id, "wheel_delta"))[1]);
    try std.testing.expect(try world.getBoolean(input, input_keyboard_component_id, "editor_toggle_pressed"));
    try std.testing.expectEqual(@as(f32, 1280.0), (try world.getVec3(input, input_frame_component_id, "viewport"))[0]);
}

test "world removes component rows without moving entity handles" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    const second = try world.createEntity("second", "Second");
    try world.setUiCommandEvent(first, .{ .command = "one", .source = "first" });
    try world.setUiCommandEvent(second, .{ .command = "two", .source = "second" });

    try std.testing.expect(try world.removeComponent(first, ui_command_event_component_id));
    try std.testing.expect(!try world.hasComponent(first, ui_command_event_component_id));
    try std.testing.expect(try world.hasComponent(second, ui_command_event_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_command_event_component_id));

    const event = world.uiCommandEvent() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(second.index, event.entity.index);
    try std.testing.expectEqualStrings("two", event.command);
    try std.testing.expectEqualStrings("second", event.source);
    try std.testing.expect(!try world.removeComponent(first, ui_command_event_component_id));
}

test "world removes entities and repairs component table handles" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    const middle = try world.createEntity("middle", "Middle");
    const last = try world.createEntity("last", "Last");
    try world.setTransform(first, .{ .position = .{ -1.0, 0.0, 0.0 } });
    try world.setTransform(middle, .{ .position = .{ 0.0, 0.0, 0.0 } });
    try world.setTransform(last, .{ .position = .{ 1.0, 0.0, 0.0 } });
    try world.setSurfaceMaterial(last, .{ .base_color = .{ 0.1, 0.2, 0.3 } });

    try std.testing.expect(try world.removeEntity(middle));
    try std.testing.expectEqual(@as(usize, 2), world.entityCount());
    try std.testing.expect(world.findEntityById("middle") == null);
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(middle));
    try std.testing.expectError(WorldError.InvalidEntity, world.getTransform(middle));

    const moved_last = world.findEntityById("last") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 1), moved_last.index);
    try std.testing.expectEqual(last.generation, moved_last.generation);
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(last));
    const moved_transform = (try world.getTransform(moved_last)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 1.0), moved_transform.position[0]);
    try std.testing.expect(try world.hasComponent(moved_last, surface_material_component_id));

    var cursor: usize = 0;
    const query = [_][]const u8{transform_component_id};
    try std.testing.expectEqual(first.index, (world.queryNext(&query, &cursor) orelse return error.TestExpectedEqual).index);
    try std.testing.expectEqual(moved_last.index, (world.queryNext(&query, &cursor) orelse return error.TestExpectedEqual).index);
    try std.testing.expect(world.queryNext(&query, &cursor) == null);
}

test "world resolves explicit primitive geometry and surface material renderables" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("sphere", "Sphere");
    try world.setTransform(entity, .{ .position = .{ 0.0, 1.0, 0.0 } });
    try world.setGeometryPrimitive(entity, .{
        .primitive = "uv_sphere",
        .segments = 32,
        .rings = 16,
    });
    try world.setSurfaceMaterial(entity, .{
        .base_color = .{ 0.2, 0.8, 1.0 },
    });
    try world.setShadowCaster(entity);
    try world.setShadowReceiver(entity);

    try std.testing.expectEqual(@as(usize, 1), world.renderableMeshCount());
    try std.testing.expectEqual(@as(usize, 1), world.renderableCubeCount());
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(shadow_caster_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(shadow_receiver_component_id));

    const mesh = world.renderableMeshAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(entity.index, mesh.entity.index);
    try std.testing.expectEqualStrings("uv_sphere", mesh.primitive);
    try std.testing.expectEqual(@as(i32, 32), mesh.segments);
    try std.testing.expectEqual(@as(i32, 16), mesh.rings);
    try std.testing.expectEqual(@as(f32, 0.8), mesh.base_color[1]);
    try std.testing.expect(mesh.casts_shadow);
    try std.testing.expect(mesh.receives_shadow);
}

test "world resolves render camera and directional light components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const camera_entity = try world.createEntity("camera", "Camera");
    try world.setTransform(camera_entity, .{ .position = .{ 0.0, 1.5, 6.0 } });
    try world.setCamera(camera_entity, .{
        .fov_y_degrees = 55.0,
        .near = 0.2,
        .far = 250.0,
    });

    const light_entity = try world.createEntity("key-light", "Key Light");
    try world.setDirectionalLight(light_entity, .{
        .direction = .{ -0.25, 0.75, 0.5 },
        .color = .{ 0.9, 0.95, 1.0 },
        .intensity = 1.2,
        .ambient = 0.12,
    });

    const camera = world.renderCamera() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(camera_entity.index, camera.entity.index);
    try std.testing.expectEqual(@as(f32, 6.0), camera.transform.position[2]);
    try std.testing.expectEqual(@as(f32, 55.0), camera.fov_y_degrees);

    const light = world.renderDirectionalLight() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(light_entity.index, light.entity.index);
    try std.testing.expectEqual(@as(f32, 0.75), light.direction[1]);
    try std.testing.expectEqual(@as(f32, 1.2), light.intensity);
}

test "world resolves UI rect and text components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const canvas = try world.createEntity("hud-canvas", "HUD Canvas");
    try world.setUiCanvas(canvas);

    const panel = try world.createEntity("hud-panel", "HUD Panel");
    try world.setUiRect(panel, .{
        .position = .{ 24.0, 24.0, 0.0 },
        .size = .{ 220.0, 72.0, 0.0 },
        .color = .{ 0.02, 0.08, 0.14 },
    });

    const button = try world.createEntity("hud-button", "HUD Button");
    try world.setUiRect(button, .{
        .position = .{ 32.0, 104.0, 0.0 },
        .size = .{ 140.0, 34.0, 0.0 },
        .color = .{ 0.0, 0.48, 0.86 },
        .corner_radius = 6.0,
    });
    try world.setUiButton(button);

    const label = try world.createEntity("hud-label", "HUD Label");
    try world.setUiText(label, .{
        .position = .{ 40.0, 42.0, 0.0 },
        .size = 2.0,
        .color = .{ 0.82, 0.94, 1.0 },
        .value = "BATCHES 4",
    });

    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_canvas_component_id));
    try std.testing.expectEqual(@as(usize, 2), world.uiRectCount());
    try std.testing.expectEqual(@as(usize, 1), world.uiTextCount());

    const resolved_panel = world.uiRectAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(panel.index, resolved_panel.entity.index);
    try std.testing.expectEqual(@as(f32, 220.0), resolved_panel.size[0]);
    try std.testing.expect(!resolved_panel.is_button);

    const resolved_button = world.uiRectAt(1) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(button.index, resolved_button.entity.index);
    try std.testing.expect(resolved_button.is_button);
    try std.testing.expectEqual(@as(f32, 6.0), resolved_button.corner_radius);

    const resolved_label = world.uiTextAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(label.index, resolved_label.entity.index);
    try std.testing.expectEqual(@as(f32, 2.0), resolved_label.size);
    try std.testing.expectEqualStrings("BATCHES 4", resolved_label.value);
}

test "world stores expanded UI semantic components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const stack = try world.createEntity("toolbar", "Toolbar");
    try world.setUiStack(stack, .{
        .position = .{ 10.0, 12.0, 0.0 },
        .spacing = 6.0,
        .direction = "horizontal",
        .padding = .{ 8.0, 4.0, 0.0 },
    });

    const slot = try world.createEntity("slot", "Slot");
    try world.setUiLayoutItem(slot, .{
        .parent = "toolbar",
        .order = 2,
        .min_size = .{ 64.0, 32.0, 0.0 },
        .grow = 1.0,
        .@"align" = "center",
    });
    try world.setUiSpacer(slot, .{ .size = .{ 24.0, 16.0, 0.0 } });

    const progress = try world.createEntity("progress", "Progress");
    try world.setUiProgressBar(progress, .{
        .value = 3.0,
        .max = 5.0,
        .fill_color = .{ 0.1, 0.7, 0.3 },
    });
    try world.setUiToggle(progress, .{ .checked = true });

    const label = try world.createEntity("label", "Label");
    try world.setUiText(label, .{ .value = "CENTER" });
    try world.setUiTextBlock(label, .{
        .size = .{ 120.0, 48.0, 0.0 },
        .horizontal_align = "center",
        .vertical_align = "center",
    });

    const separator = try world.createEntity("separator", "Separator");
    try world.setUiSeparator(separator, .{
        .position = .{ 0.0, 44.0, 0.0 },
        .size = .{ 120.0, 2.0, 0.0 },
        .color = .{ 0.5, 0.6, 0.7 },
    });

    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_stack_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_spacer_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_text_block_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_toggle_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_progress_bar_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.uiSeparatorCount());

    const resolved_separator = world.uiSeparatorAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(separator.index, resolved_separator.entity.index);
    try std.testing.expectEqual(@as(f32, 2.0), resolved_separator.size[1]);
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

test "world resolved queries return reusable component rows" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    const second = try world.createEntity("second", "Second");
    try world.setTransform(first, .{
        .position = .{ 1.0, 0.0, 0.0 },
        .rotation = .{ 0.1, 0.2, 0.3 },
    });
    try world.setTransform(second, .{
        .position = .{ 2.0, 0.0, 0.0 },
        .rotation = .{ 1.1, 1.2, 1.3 },
    });
    try world.setSpin(second, .{ .angular_velocity = .{ 0.0, 2.0, 0.0 } });

    const transform_table = world.resolveComponentTableIndex(transform_component_id) orelse return error.TestExpectedEqual;
    const spin_table = world.resolveComponentTableIndex(spin_component_id) orelse return error.TestExpectedEqual;
    const query_tables = [_]u32{ transform_table, spin_table };
    const driver = (try world.queryDriverTableIndex(&query_tables)) orelse return error.TestExpectedEqual;

    var cursor: usize = 0;
    var rows: [2]u32 = undefined;
    const queried = (try world.queryNextResolved(&query_tables, driver, &cursor, &rows)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(second.index, queried.index);
    try std.testing.expectEqual(spin_table, query_tables[1]);

    const rotation = try world.getComponentFieldValueResolved(queried, .{
        .table_index = transform_table,
        .row_index = rows[0],
    }, "rotation");
    try std.testing.expectEqual(@as(f32, 1.2), rotation.vec3[1]);

    try world.setComponentFieldValueResolved(queried, .{
        .table_index = transform_table,
        .row_index = rows[0],
    }, "rotation", .{ .vec3 = .{ 3.0, 4.0, 5.0 } });
    try std.testing.expectEqual(@as(f32, 4.0), (try world.getVec3(second, transform_component_id, "rotation"))[1]);
    try std.testing.expect((try world.queryNextResolved(&query_tables, driver, &cursor, &rows)) == null);
}

test "world resolved field access repairs stale moved rows" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    const second = try world.createEntity("second", "Second");
    try world.setTransform(first, .{ .position = .{ 1.0, 0.0, 0.0 } });
    try world.setTransform(second, .{ .position = .{ 2.0, 0.0, 0.0 } });

    const transform_table = world.resolveComponentTableIndex(transform_component_id) orelse return error.TestExpectedEqual;
    const stale_second_row = ResolvedComponentRow{
        .table_index = transform_table,
        .row_index = 1,
    };

    try std.testing.expect(try world.removeComponent(first, transform_component_id));
    try world.setComponentFieldValueResolved(second, stale_second_row, "position", .{ .vec3 = .{ 9.0, 8.0, 7.0 } });
    try std.testing.expectEqual(@as(f32, 9.0), (try world.getVec3(second, transform_component_id, "position"))[0]);
    try std.testing.expectError(WorldError.UnknownComponent, world.getComponentFieldValueResolved(first, stale_second_row, "position"));
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

test "engine component schemas are registered from runtime" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registerEngineComponents(&registry);

    try std.testing.expect(registry.findComponent(transform_component_id) != null);
    try std.testing.expect(registry.findComponent(cube_renderer_component_id) != null);
    try std.testing.expect(registry.findComponent(geometry_primitive_component_id) != null);
    try std.testing.expect(registry.findComponent(surface_material_component_id) != null);
    try std.testing.expect(registry.findComponent(camera_component_id) != null);
    try std.testing.expect(registry.findComponent(directional_light_component_id) != null);
    try std.testing.expect(registry.findComponent(shadow_caster_component_id) != null);
    try std.testing.expect(registry.findComponent(shadow_receiver_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_canvas_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_rect_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_text_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_button_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_command_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_command_event_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_scroll_view_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_vbox_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_stack_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_layout_item_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_spacer_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_text_block_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_toggle_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_progress_bar_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_separator_component_id) != null);
    try std.testing.expect(registry.findComponent(input_pointer_component_id) != null);
    try std.testing.expect(registry.findComponent(input_keyboard_component_id) != null);
    try std.testing.expect(registry.findComponent(input_frame_component_id) != null);
    try std.testing.expectEqual(@as(usize, 26), registry.componentCount());

    const transform = registry.findComponent(transform_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 3), transform.fields.len);
    try std.testing.expectEqual(FieldType.vec3, transform.fields[0].value_type);

    const ui_text = registry.findComponent(ui_text_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 4), ui_text.fields.len);
    try std.testing.expectEqual(FieldType.string, ui_text.fields[3].value_type);

    const ui_rect = registry.findComponent(ui_rect_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 4), ui_rect.fields.len);
    try std.testing.expectEqual(FieldType.float, ui_rect.fields[3].value_type);

    const ui_stack = registry.findComponent(ui_stack_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 4), ui_stack.fields.len);
    try std.testing.expectEqual(FieldType.string, ui_stack.fields[2].value_type);

    const ui_layout_item = registry.findComponent(ui_layout_item_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 5), ui_layout_item.fields.len);
    try std.testing.expectEqual(FieldType.vec3, ui_layout_item.fields[2].value_type);
    try std.testing.expectEqual(FieldType.float, ui_layout_item.fields[3].value_type);
    try std.testing.expectEqual(FieldType.string, ui_layout_item.fields[4].value_type);

    const ui_progress_bar = registry.findComponent(ui_progress_bar_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 3), ui_progress_bar.fields.len);
    try std.testing.expectEqual(FieldType.vec3, ui_progress_bar.fields[2].value_type);

    const ui_separator = registry.findComponent(ui_separator_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 3), ui_separator.fields.len);
    try std.testing.expectEqual(FieldType.vec3, ui_separator.fields[2].value_type);

    const ui_command_event = registry.findComponent(ui_command_event_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), ui_command_event.fields.len);
    try std.testing.expectEqual(FieldType.string, ui_command_event.fields[0].value_type);

    const input_pointer = registry.findComponent(input_pointer_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 6), input_pointer.fields.len);
    try std.testing.expectEqual(FieldType.vec3, input_pointer.fields[5].value_type);
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
