const std = @import("std");
const components = @import("components.zig");
const storage = @import("storage.zig");

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

const engine_namespace = "scrapbot";
pub const transform_component_id = "scrapbot.transform";
pub const cube_renderer_component_id = "scrapbot.render.cube";
pub const geometry_primitive_component_id = "scrapbot.geometry.primitive";
pub const surface_material_component_id = "scrapbot.material.surface";
pub const renderer_component_id = "scrapbot.renderer";
pub const camera_component_id = "scrapbot.camera";
pub const directional_light_component_id = "scrapbot.light.directional";
pub const shadow_caster_component_id = "scrapbot.shadow.caster";
pub const shadow_receiver_component_id = "scrapbot.shadow.receiver";
pub const ui_canvas_component_id = "scrapbot.ui.canvas";
pub const ui_rect_component_id = "scrapbot.ui.rect";
pub const ui_border_component_id = "scrapbot.ui.border";
pub const ui_text_component_id = "scrapbot.ui.text";
pub const ui_button_component_id = "scrapbot.ui.button";
pub const ui_hit_area_component_id = "scrapbot.ui.hit_area";
pub const ui_command_component_id = "scrapbot.ui.command";
pub const ui_command_event_component_id = "scrapbot.ui.command_event";
pub const ui_command_event_entity_id = "scrapbot.ui.command_event.current";
pub const ui_scroll_view_component_id = "scrapbot.ui.scroll_view";
pub const ui_vgroup_component_id = "scrapbot.ui.vgroup";
pub const ui_hgroup_component_id = "scrapbot.ui.hgroup";
pub const ui_table_component_id = "scrapbot.ui.table";
pub const ui_stack_component_id = "scrapbot.ui.stack";
pub const ui_layout_item_component_id = "scrapbot.ui.layout.item";
pub const ui_spacer_component_id = "scrapbot.ui.spacer";
pub const ui_text_block_component_id = "scrapbot.ui.text_block";
pub const ui_toggle_component_id = "scrapbot.ui.toggle";
pub const ui_progress_bar_component_id = "scrapbot.ui.progress_bar";
pub const ui_separator_component_id = "scrapbot.ui.separator";
pub const input_entity_id = "scrapbot.input.frame";
pub const input_pointer_component_id = "scrapbot.input.pointer";
pub const input_keyboard_component_id = "scrapbot.input.keyboard";
pub const input_frame_component_id = "scrapbot.input.frame";
pub const spin_component_id = "spin";

pub const FieldType = components.FieldType;
pub const ComponentFieldDefinition = components.ComponentFieldDefinition;
pub const ComponentDefinition = components.ComponentDefinition;
pub const SystemPhase = components.SystemPhase;
pub const SystemDefinition = components.SystemDefinition;
pub const SystemRunner = components.SystemRunner;
pub const SystemProfileSnapshot = components.SystemProfileSnapshot;
pub const ScheduledSystem = components.ScheduledSystem;
pub const SystemBatch = components.SystemBatch;
pub const SystemSchedule = components.SystemSchedule;
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

    const renderer_fields = [_]ComponentFieldDefinition{
        .{ .name = "hdr", .value_type = .boolean },
        .{ .name = "tone_mapping", .value_type = .string },
        .{ .name = "exposure", .value_type = .float },
        .{ .name = "postprocess_enabled", .value_type = .boolean },
        .{ .name = "antialiasing", .value_type = .string },
        .{ .name = "bloom_enabled", .value_type = .boolean },
        .{ .name = "bloom_threshold", .value_type = .float },
        .{ .name = "bloom_intensity", .value_type = .float },
        .{ .name = "bloom_radius", .value_type = .float },
        .{ .name = "vignette_enabled", .value_type = .boolean },
        .{ .name = "vignette_strength", .value_type = .float },
        .{ .name = "vignette_radius", .value_type = .float },
        .{ .name = "chromatic_aberration_enabled", .value_type = .boolean },
        .{ .name = "chromatic_aberration_strength", .value_type = .float },
    };
    try registry.registerEngineComponent(.{
        .id = renderer_component_id,
        .version = 1,
        .fields = &renderer_fields,
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

    const ui_canvas_fields = [_]ComponentFieldDefinition{
        .{ .name = "design_size", .value_type = .vec3 },
        .{ .name = "scale_mode", .value_type = .string },
    };
    try registry.registerEngineComponent(.{
        .id = ui_canvas_component_id,
        .version = 1,
        .fields = &ui_canvas_fields,
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

    const ui_border_fields = [_]ComponentFieldDefinition{
        .{ .name = "color", .value_type = .vec3 },
        .{ .name = "thickness", .value_type = .float },
    };
    try registry.registerEngineComponent(.{
        .id = ui_border_component_id,
        .version = 1,
        .fields = &ui_border_fields,
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

    const ui_hit_area_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "size", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = ui_hit_area_component_id,
        .version = 1,
        .fields = &ui_hit_area_fields,
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

    const ui_vgroup_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "size", .value_type = .vec3 },
        .{ .name = "spacing", .value_type = .float },
        .{ .name = "padding", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = ui_vgroup_component_id,
        .version = 1,
        .fields = &ui_vgroup_fields,
    });

    const ui_hgroup_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "size", .value_type = .vec3 },
        .{ .name = "spacing", .value_type = .float },
        .{ .name = "padding", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = ui_hgroup_component_id,
        .version = 1,
        .fields = &ui_hgroup_fields,
    });

    const ui_table_fields = [_]ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "size", .value_type = .vec3 },
        .{ .name = "columns", .value_type = .int },
        .{ .name = "row_height", .value_type = .float },
        .{ .name = "column_gap", .value_type = .float },
        .{ .name = "row_gap", .value_type = .float },
        .{ .name = "padding", .value_type = .vec3 },
        .{ .name = "first_column_ratio", .value_type = .float },
    };
    try registry.registerEngineComponent(.{
        .id = ui_table_component_id,
        .version = 1,
        .fields = &ui_table_fields,
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
        .{ .name = "preferred_size", .value_type = .vec3 },
        .{ .name = "max_size", .value_type = .vec3 },
        .{ .name = "grow", .value_type = .float },
        .{ .name = "shrink", .value_type = .float },
        .{ .name = "align", .value_type = .string },
        .{ .name = "margin", .value_type = .vec3 },
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
        .{ .name = "delta", .value_type = .vec3 },
        .{ .name = "has_position", .value_type = .boolean },
        .{ .name = "primary_down", .value_type = .boolean },
        .{ .name = "primary_pressed", .value_type = .boolean },
        .{ .name = "primary_released", .value_type = .boolean },
        .{ .name = "secondary_down", .value_type = .boolean },
        .{ .name = "secondary_pressed", .value_type = .boolean },
        .{ .name = "secondary_released", .value_type = .boolean },
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
        .{ .name = "move_forward", .value_type = .boolean },
        .{ .name = "move_back", .value_type = .boolean },
        .{ .name = "move_left", .value_type = .boolean },
        .{ .name = "move_right", .value_type = .boolean },
        .{ .name = "move_up", .value_type = .boolean },
        .{ .name = "move_down", .value_type = .boolean },
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
        .{ .name = "pixel_scale", .value_type = .float },
    };
    try registry.registerEngineComponent(.{
        .id = input_frame_component_id,
        .version = 1,
        .fields = &input_frame_fields,
    });
}

pub const EntityHandle = components.EntityHandle;
pub const EntityProvenance = components.EntityProvenance;
const CreateEntityOptions = components.CreateEntityOptions;
pub const ResolvedComponentRow = components.ResolvedComponentRow;
pub const Entity = components.Entity;
pub const StructuralEventKind = components.StructuralEventKind;
pub const StructuralEvent = components.StructuralEvent;

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

pub const ComponentStructuralEventIterator = struct {
    events: []const StructuralEvent,
    component_id: []const u8,
    index: usize = 0,

    pub fn next(self: *ComponentStructuralEventIterator) ?StructuralEvent {
        while (self.index < self.events.len) {
            const event = self.events[self.index];
            self.index += 1;
            const event_component_id = event.component_id orelse continue;
            if (std.mem.eql(u8, event_component_id, self.component_id)) {
                return event;
            }
        }
        return null;
    }
};

pub const Transform = components.Transform;
pub const CubeRenderer = components.CubeRenderer;
pub const GeometryPrimitive = components.GeometryPrimitive;
pub const SurfaceMaterial = components.SurfaceMaterial;
pub const Camera = components.Camera;
pub const DirectionalLight = components.DirectionalLight;
pub const Spin = components.Spin;
pub const RenderableCube = components.RenderableCube;
pub const RenderableMesh = components.RenderableMesh;
pub const RenderCamera = components.RenderCamera;
pub const RenderDirectionalLight = components.RenderDirectionalLight;
pub const RendererSettings = components.RendererSettings;
pub const UiRectComponent = components.UiRectComponent;
pub const UiCanvasComponent = components.UiCanvasComponent;
pub const UiBorderComponent = components.UiBorderComponent;
pub const UiTextComponent = components.UiTextComponent;
pub const UiHitAreaComponent = components.UiHitAreaComponent;
pub const UiCommandComponent = components.UiCommandComponent;
pub const UiScrollViewComponent = components.UiScrollViewComponent;
pub const UiHGroupComponent = components.UiHGroupComponent;
pub const UiVGroupComponent = components.UiVGroupComponent;
pub const UiTableComponent = components.UiTableComponent;
pub const UiStackComponent = components.UiStackComponent;
pub const UiLayoutItemComponent = components.UiLayoutItemComponent;
pub const UiSpacerComponent = components.UiSpacerComponent;
pub const UiTextBlockComponent = components.UiTextBlockComponent;
pub const UiToggleComponent = components.UiToggleComponent;
pub const UiProgressBarComponent = components.UiProgressBarComponent;
pub const UiSeparatorComponent = components.UiSeparatorComponent;
pub const UiCommandEventComponent = components.UiCommandEventComponent;
pub const UiCommandEvent = components.UiCommandEvent;
pub const UiRect = components.UiRect;
pub const UiText = components.UiText;
pub const UiSeparator = components.UiSeparator;
pub const InputPointerComponent = components.InputPointerComponent;
pub const InputKeyboardComponent = components.InputKeyboardComponent;
pub const InputFrameComponent = components.InputFrameComponent;
pub const ComponentValue = components.ComponentValue;
pub const ComponentFieldValue = components.ComponentFieldValue;
const ComponentColumnValues = storage.ComponentColumnValues;
pub const ComponentColumn = storage.ComponentColumn;
pub const ComponentTable = storage.ComponentTable;
pub const World = struct {
    allocator: std.mem.Allocator,
    entities: std.ArrayList(Entity) = .empty,
    component_tables: std.ArrayList(ComponentTable) = .empty,
    structural_events: std.ArrayList(StructuralEvent) = .empty,
    query_plan_generation: u64 = 1,
    revision: u64 = 1,
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
        self.structural_events.deinit(allocator);
        self.* = .{ .allocator = allocator };
    }

    pub fn clearRetainingCapacity(self: *World) void {
        for (self.entities.items) |stored_entity| {
            self.allocator.free(stored_entity.id);
            self.allocator.free(stored_entity.name);
        }
        self.entities.clearRetainingCapacity();
        for (self.component_tables.items) |*component_table| {
            component_table.clearRetainingCapacity(self.allocator);
        }
        self.clearStructuralEventsRetainingCapacity();
        self.bumpQueryPlanGeneration();
        self.bumpRevision();
    }

    pub fn queryPlanGeneration(self: World) u64 {
        return self.query_plan_generation;
    }

    pub fn worldRevision(self: World) u64 {
        return self.revision;
    }

    pub fn structuralEvents(self: World) []const StructuralEvent {
        return self.structural_events.items;
    }

    pub fn componentStructuralEvents(self: World, component_id: []const u8) ComponentStructuralEventIterator {
        return .{
            .events = self.structural_events.items,
            .component_id = component_id,
        };
    }

    pub fn clearStructuralEventsRetainingCapacity(self: *World) void {
        self.structural_events.clearRetainingCapacity();
    }

    pub fn createEntity(self: *World, id: []const u8, name: []const u8) !EntityHandle {
        return self.createEntityWithOptions(id, name, .{});
    }

    pub fn createAuthoredEntity(self: *World, id: []const u8, name: []const u8) !EntityHandle {
        return self.createEntityWithOptions(id, name, .{ .provenance = .authored });
    }

    pub fn createEngineTransientEntity(self: *World, id: []const u8, name: []const u8) !EntityHandle {
        return self.createEntityWithOptions(id, name, .{
            .provenance = .engine_transient,
            .emit_structural_events = false,
        });
    }

    fn createEntityWithOptions(self: *World, id: []const u8, name: []const u8, options: CreateEntityOptions) !EntityHandle {
        if (self.findEntityById(id) != null) {
            return WorldError.DuplicateEntityId;
        }
        if (options.emit_structural_events) {
            try self.reserveStructuralEvents(1);
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
            .provenance = options.provenance,
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

        if (options.emit_structural_events) {
            self.appendStructuralEventAssumeCapacity(.{
                .kind = .entity_created,
                .entity = handle,
            });
        }
        self.bumpRevision();
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

    pub fn setRendererSettings(self: *World, handle: EntityHandle, renderer: RendererSettings) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "hdr", .value = .{ .boolean = renderer.hdr } },
            .{ .name = "tone_mapping", .value = .{ .string = renderer.tone_mapping } },
            .{ .name = "exposure", .value = .{ .float = renderer.exposure } },
            .{ .name = "postprocess_enabled", .value = .{ .boolean = renderer.postprocess_enabled } },
            .{ .name = "antialiasing", .value = .{ .string = renderer.antialiasing } },
            .{ .name = "bloom_enabled", .value = .{ .boolean = renderer.bloom_enabled } },
            .{ .name = "bloom_threshold", .value = .{ .float = renderer.bloom_threshold } },
            .{ .name = "bloom_intensity", .value = .{ .float = renderer.bloom_intensity } },
            .{ .name = "bloom_radius", .value = .{ .float = renderer.bloom_radius } },
            .{ .name = "vignette_enabled", .value = .{ .boolean = renderer.vignette_enabled } },
            .{ .name = "vignette_strength", .value = .{ .float = renderer.vignette_strength } },
            .{ .name = "vignette_radius", .value = .{ .float = renderer.vignette_radius } },
            .{ .name = "chromatic_aberration_enabled", .value = .{ .boolean = renderer.chromatic_aberration_enabled } },
            .{ .name = "chromatic_aberration_strength", .value = .{ .float = renderer.chromatic_aberration_strength } },
        };
        try self.setComponent(handle, renderer_component_id, &fields);
    }

    pub fn setShadowCaster(self: *World, handle: EntityHandle) WorldError!void {
        try self.setComponent(handle, shadow_caster_component_id, &.{});
    }

    pub fn setShadowReceiver(self: *World, handle: EntityHandle) WorldError!void {
        try self.setComponent(handle, shadow_receiver_component_id, &.{});
    }

    pub fn setUiCanvas(self: *World, handle: EntityHandle, canvas: UiCanvasComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "design_size", .value = .{ .vec3 = canvas.design_size } },
            .{ .name = "scale_mode", .value = .{ .string = canvas.scale_mode } },
        };
        try self.setComponent(handle, ui_canvas_component_id, &fields);
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

    pub fn setUiBorder(self: *World, handle: EntityHandle, border: UiBorderComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "color", .value = .{ .vec3 = border.color } },
            .{ .name = "thickness", .value = .{ .float = border.thickness } },
        };
        try self.setComponent(handle, ui_border_component_id, &fields);
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

    pub fn setUiHitArea(self: *World, handle: EntityHandle, hit_area: UiHitAreaComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = hit_area.position } },
            .{ .name = "size", .value = .{ .vec3 = hit_area.size } },
        };
        try self.setComponent(handle, ui_hit_area_component_id, &fields);
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

    pub fn setUiHGroup(self: *World, handle: EntityHandle, hgroup: UiHGroupComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = hgroup.position } },
            .{ .name = "size", .value = .{ .vec3 = hgroup.size } },
            .{ .name = "spacing", .value = .{ .float = hgroup.spacing } },
            .{ .name = "padding", .value = .{ .vec3 = hgroup.padding } },
        };
        try self.setComponent(handle, ui_hgroup_component_id, &fields);
    }

    pub fn setUiVGroup(self: *World, handle: EntityHandle, vgroup: UiVGroupComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = vgroup.position } },
            .{ .name = "size", .value = .{ .vec3 = vgroup.size } },
            .{ .name = "spacing", .value = .{ .float = vgroup.spacing } },
            .{ .name = "padding", .value = .{ .vec3 = vgroup.padding } },
        };
        try self.setComponent(handle, ui_vgroup_component_id, &fields);
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

    pub fn setUiTable(self: *World, handle: EntityHandle, table: UiTableComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "position", .value = .{ .vec3 = table.position } },
            .{ .name = "size", .value = .{ .vec3 = table.size } },
            .{ .name = "columns", .value = .{ .int = table.columns } },
            .{ .name = "row_height", .value = .{ .float = table.row_height } },
            .{ .name = "column_gap", .value = .{ .float = table.column_gap } },
            .{ .name = "row_gap", .value = .{ .float = table.row_gap } },
            .{ .name = "padding", .value = .{ .vec3 = table.padding } },
            .{ .name = "first_column_ratio", .value = .{ .float = table.first_column_ratio } },
        };
        try self.setComponent(handle, ui_table_component_id, &fields);
    }

    pub fn setUiLayoutItem(self: *World, handle: EntityHandle, item: UiLayoutItemComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "parent", .value = .{ .string = item.parent } },
            .{ .name = "order", .value = .{ .int = item.order } },
            .{ .name = "min_size", .value = .{ .vec3 = item.min_size } },
            .{ .name = "preferred_size", .value = .{ .vec3 = item.preferred_size } },
            .{ .name = "max_size", .value = .{ .vec3 = item.max_size } },
            .{ .name = "grow", .value = .{ .float = item.grow } },
            .{ .name = "shrink", .value = .{ .float = item.shrink } },
            .{ .name = "align", .value = .{ .string = item.@"align" } },
            .{ .name = "margin", .value = .{ .vec3 = item.margin } },
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
            .{ .name = "delta", .value = .{ .vec3 = pointer.delta } },
            .{ .name = "has_position", .value = .{ .boolean = pointer.has_position } },
            .{ .name = "primary_down", .value = .{ .boolean = pointer.primary_down } },
            .{ .name = "primary_pressed", .value = .{ .boolean = pointer.primary_pressed } },
            .{ .name = "primary_released", .value = .{ .boolean = pointer.primary_released } },
            .{ .name = "secondary_down", .value = .{ .boolean = pointer.secondary_down } },
            .{ .name = "secondary_pressed", .value = .{ .boolean = pointer.secondary_pressed } },
            .{ .name = "secondary_released", .value = .{ .boolean = pointer.secondary_released } },
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
            .{ .name = "move_forward", .value = .{ .boolean = keyboard.move_forward } },
            .{ .name = "move_back", .value = .{ .boolean = keyboard.move_back } },
            .{ .name = "move_left", .value = .{ .boolean = keyboard.move_left } },
            .{ .name = "move_right", .value = .{ .boolean = keyboard.move_right } },
            .{ .name = "move_up", .value = .{ .boolean = keyboard.move_up } },
            .{ .name = "move_down", .value = .{ .boolean = keyboard.move_down } },
            .{ .name = "editor_toggle_pressed", .value = .{ .boolean = keyboard.editor_toggle_pressed } },
        };
        try self.setComponent(handle, input_keyboard_component_id, &fields);
    }

    pub fn setInputFrame(self: *World, handle: EntityHandle, frame: InputFrameComponent) WorldError!void {
        const fields = [_]ComponentFieldValue{
            .{ .name = "ui_visible", .value = .{ .boolean = frame.ui_visible } },
            .{ .name = "debug_overlay_visible", .value = .{ .boolean = frame.debug_overlay_visible } },
            .{ .name = "viewport", .value = .{ .vec3 = frame.viewport } },
            .{ .name = "pixel_scale", .value = .{ .float = frame.pixel_scale } },
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
        return self.setComponentWithStructuralEvents(handle, component_id, fields, true);
    }

    pub fn setComponentSilently(self: *World, handle: EntityHandle, component_id: []const u8, fields: []const ComponentFieldValue) WorldError!void {
        return self.setComponentWithStructuralEvents(handle, component_id, fields, false);
    }

    fn setComponentWithStructuralEvents(self: *World, handle: EntityHandle, component_id: []const u8, fields: []const ComponentFieldValue, emit_requested: bool) WorldError!void {
        const index = try self.componentIndex(handle);
        const emit_structural_event = emit_requested and self.entities.items[index].provenance != .engine_transient;
        const table_index = try self.ensureComponentTable(component_id, fields);
        const table = &self.component_tables.items[table_index];
        if (table.rows_by_entity.items[index]) |row| {
            try self.updateComponentRow(table, row, fields);
        } else {
            if (emit_structural_event) {
                try self.reserveStructuralEvents(1);
            }
            try self.appendComponentRow(table, handle, index, fields);
            if (emit_structural_event) {
                self.appendStructuralEventAssumeCapacity(.{
                    .kind = .component_added,
                    .entity = handle,
                    .component_id = table.id,
                });
            }
        }
        self.bumpRevision();
    }

    pub fn removeComponent(self: *World, handle: EntityHandle, component_id: []const u8) WorldError!bool {
        return self.removeComponentWithStructuralEvents(handle, component_id, true, true);
    }

    pub fn removeAllComponents(self: *World, component_id: []const u8) WorldError!void {
        return self.removeAllComponentsWithStructuralEvents(component_id, true);
    }

    pub fn removeAllComponentsSilently(self: *World, component_id: []const u8) WorldError!void {
        return self.removeAllComponentsWithStructuralEvents(component_id, false);
    }

    fn removeAllComponentsWithStructuralEvents(self: *World, component_id: []const u8, emit_requested: bool) WorldError!void {
        while (true) {
            const table = self.findComponentTable(component_id) orelse return;
            if (table.entities.items.len == 0) {
                return;
            }
            _ = try self.removeComponentWithStructuralEvents(table.entities.items[0], component_id, true, emit_requested);
        }
    }

    fn removeComponentWithStructuralEvents(self: *World, handle: EntityHandle, component_id: []const u8, reserve_event: bool, emit_requested: bool) WorldError!bool {
        const entity_index = try self.componentIndex(handle);
        const emit_structural_event = emit_requested and self.entities.items[entity_index].provenance != .engine_transient;
        const table = self.findMutableComponentTable(component_id) orelse return false;
        if (entity_index >= table.rows_by_entity.items.len) {
            return false;
        }
        const row = table.rows_by_entity.items[entity_index] orelse return false;
        if (emit_structural_event and reserve_event) {
            try self.reserveStructuralEvents(1);
        }
        const removed_handle = table.entities.items[row];
        const removed_component_id = table.id;
        const last_row = table.entities.items.len - 1;
        const moved_entity = table.entities.items[last_row];

        table.entities.items[row] = moved_entity;
        _ = table.entities.pop();
        table.rows_by_entity.items[removed_handle.index] = null;
        if (row != last_row) {
            table.rows_by_entity.items[moved_entity.index] = row;
        }

        for (table.columns) |*column| {
            column.values.swapRemove(self.allocator, row);
        }

        if (emit_structural_event) {
            self.appendStructuralEventAssumeCapacity(.{
                .kind = .component_removed,
                .entity = removed_handle,
                .component_id = removed_component_id,
            });
        }
        self.bumpRevision();
        return true;
    }

    pub fn clearEngineTransientEntities(self: *World) WorldError!void {
        var index: usize = 0;
        while (index < self.entities.items.len) {
            if (self.entities.items[index].provenance != .engine_transient) {
                index += 1;
                continue;
            }
            const handle = EntityHandle{
                .index = @intCast(index),
                .generation = self.entities.items[index].generation,
            };
            _ = try self.removeEntity(handle);
        }
    }

    pub fn removeEntity(self: *World, handle: EntityHandle) WorldError!bool {
        const entity_index = try self.componentIndex(handle);
        const emit_structural_event = self.entities.items[entity_index].provenance != .engine_transient;
        const last_entity_index = self.entities.items.len - 1;
        const removed_handle = EntityHandle{
            .index = @intCast(entity_index),
            .generation = self.entities.items[entity_index].generation,
        };
        if (emit_structural_event) {
            try self.reserveStructuralEvents(self.componentCountForEntity(removed_handle) + 1);
        }

        while (true) {
            var removed_component = false;
            for (self.component_tables.items) |*table| {
                if (entity_index < table.rows_by_entity.items.len and table.rows_by_entity.items[entity_index] != null) {
                    _ = try self.removeComponentWithStructuralEvents(removed_handle, table.id, false, emit_structural_event);
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

        if (emit_structural_event) {
            self.appendStructuralEventAssumeCapacity(.{
                .kind = .entity_removed,
                .entity = removed_handle,
            });
        }
        self.bumpRevision();
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
            if (self.renderableMeshForEntity(.{ .index = @intCast(index) }) != null) {
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
        const collector = RenderableMeshCollector.init(self);
        var found: usize = 0;
        for (0..self.entityCount()) |index| {
            const handle = EntityHandle{ .index = @intCast(index) };
            const mesh = collector.meshAt(handle) orelse continue;
            if (found == render_index) {
                return mesh;
            }
            found += 1;
        }
        return null;
    }

    pub fn renderableMeshForEntity(self: World, handle: EntityHandle) ?RenderableMesh {
        const collector = RenderableMeshCollector.init(self);
        return collector.meshAt(handle);
    }

    pub fn appendRenderableMeshes(self: World, allocator: std.mem.Allocator, out: *std.ArrayList(RenderableMesh)) std.mem.Allocator.Error!void {
        const collector = RenderableMeshCollector.init(self);
        try out.ensureUnusedCapacity(allocator, self.entityCount());
        for (0..self.entityCount()) |index| {
            const handle = EntityHandle{ .index = @intCast(index) };
            const mesh = collector.meshAt(handle) orelse continue;
            out.appendAssumeCapacity(mesh);
        }
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
        const table = self.findComponentTable(ui_rect_component_id) orelse return .{ .world = self };
        return .{
            .world = self,
            .table = table,
            .button_table = self.findComponentTable(ui_button_component_id),
            .position_column = findColumn(table.*, "position"),
            .size_column = findColumn(table.*, "size"),
            .color_column = findColumn(table.*, "color"),
            .corner_radius_column = findColumn(table.*, "corner_radius"),
        };
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
        const table = self.findComponentTable(ui_text_component_id) orelse return .{ .world = self };
        return .{
            .world = self,
            .table = table,
            .position_column = findColumn(table.*, "position"),
            .size_column = findColumn(table.*, "size"),
            .color_column = findColumn(table.*, "color"),
            .value_column = findColumn(table.*, "value"),
        };
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
        const table = self.findComponentTable(ui_separator_component_id) orelse return .{ .world = self };
        return .{
            .world = self,
            .table = table,
            .position_column = findColumn(table.*, "position"),
            .size_column = findColumn(table.*, "size"),
            .color_column = findColumn(table.*, "color"),
        };
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
        return self.renderableMeshForEntity(handle);
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

    pub fn rendererSettings(self: World) ?RendererSettings {
        var cursor: usize = 0;
        const component_ids = [_][]const u8{renderer_component_id};
        const handle = self.queryNext(&component_ids, &cursor) orelse return null;
        const stored_entity = self.entity(handle) catch return null;
        return .{
            .entity = handle,
            .id = stored_entity.id,
            .name = stored_entity.name,
            .hdr = self.getBoolean(handle, renderer_component_id, "hdr") catch return null,
            .tone_mapping = self.getString(handle, renderer_component_id, "tone_mapping") catch return null,
            .exposure = self.getFloat(handle, renderer_component_id, "exposure") catch return null,
            .postprocess_enabled = self.getBoolean(handle, renderer_component_id, "postprocess_enabled") catch return null,
            .antialiasing = self.getString(handle, renderer_component_id, "antialiasing") catch return null,
            .bloom_enabled = self.getBoolean(handle, renderer_component_id, "bloom_enabled") catch return null,
            .bloom_threshold = self.getFloat(handle, renderer_component_id, "bloom_threshold") catch return null,
            .bloom_intensity = self.getFloat(handle, renderer_component_id, "bloom_intensity") catch return null,
            .bloom_radius = self.getFloat(handle, renderer_component_id, "bloom_radius") catch return null,
            .vignette_enabled = self.getBoolean(handle, renderer_component_id, "vignette_enabled") catch return null,
            .vignette_strength = self.getFloat(handle, renderer_component_id, "vignette_strength") catch return null,
            .vignette_radius = self.getFloat(handle, renderer_component_id, "vignette_radius") catch return null,
            .chromatic_aberration_enabled = self.getBoolean(handle, renderer_component_id, "chromatic_aberration_enabled") catch return null,
            .chromatic_aberration_strength = self.getFloat(handle, renderer_component_id, "chromatic_aberration_strength") catch return null,
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

    pub fn findComponentTable(self: World, component_id: []const u8) ?*const ComponentTable {
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
        self.bumpRevision();
    }

    fn setFieldValueResolved(self: *World, handle: EntityHandle, resolved: ResolvedComponentRow, field_name: []const u8, value: ComponentValue) WorldError!void {
        const index = try self.componentIndex(handle);
        const table = try self.mutableComponentTableAt(resolved.table_index);
        const row = resolvedRowForEntity(table.*, .{ .index = @intCast(index) }, resolved.row_index) orelse return WorldError.UnknownComponent;
        const column = findMutableColumn(table, field_name) orelse return WorldError.UnknownField;
        try column.values.setCopy(self.allocator, row, value);
        self.bumpRevision();
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

    fn bumpRevision(self: *World) void {
        self.revision +%= 1;
        if (self.revision == 0) {
            self.revision = 1;
        }
    }

    fn reserveStructuralEvents(self: *World, additional_count: usize) WorldError!void {
        try self.structural_events.ensureUnusedCapacity(self.allocator, additional_count);
    }

    fn appendStructuralEventAssumeCapacity(self: *World, event: StructuralEvent) void {
        self.structural_events.appendAssumeCapacity(event);
    }

    fn nextEntityGeneration(self: *World) u32 {
        const generation = self.next_entity_generation;
        self.next_entity_generation +%= 1;
        if (self.next_entity_generation == 0) {
            self.next_entity_generation = 1;
        }
        return generation;
    }

    fn componentCountForEntity(self: World, handle: EntityHandle) usize {
        var count: usize = 0;
        for (self.component_tables.items) |table| {
            if (rowForEntity(table, handle) != null) {
                count += 1;
            }
        }
        return count;
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

pub fn findColumn(table: ComponentTable, field_name: []const u8) ?*const ComponentColumn {
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

const RenderableMeshCollector = struct {
    world: World,
    transform: ?TransformLookup,
    geometry: ?GeometryLookup,
    material: ?MaterialLookup,
    cube: ?CubeLookup,
    spin: ?SpinLookup,
    shadow_caster: ?*const ComponentTable,
    shadow_receiver: ?*const ComponentTable,

    fn init(world: World) RenderableMeshCollector {
        return .{
            .world = world,
            .transform = TransformLookup.init(world.findComponentTable(transform_component_id)),
            .geometry = GeometryLookup.init(world.findComponentTable(geometry_primitive_component_id)),
            .material = MaterialLookup.init(world.findComponentTable(surface_material_component_id)),
            .cube = CubeLookup.init(world.findComponentTable(cube_renderer_component_id)),
            .spin = SpinLookup.init(world.findComponentTable(spin_component_id)),
            .shadow_caster = world.findComponentTable(shadow_caster_component_id),
            .shadow_receiver = world.findComponentTable(shadow_receiver_component_id),
        };
    }

    fn meshAt(self: RenderableMeshCollector, handle: EntityHandle) ?RenderableMesh {
        const stored_entity = self.world.entity(handle) catch return null;
        const stored_handle = EntityHandle{
            .index = handle.index,
            .generation = stored_entity.generation,
        };
        const transform_lookup = self.transform orelse return null;
        const transform = transform_lookup.valueAt(stored_handle) orelse return null;
        const spin = if (self.spin) |lookup| lookup.valueAt(stored_handle) orelse .{ 0.0, 0.0, 0.0 } else .{ 0.0, 0.0, 0.0 };
        const casts_shadow = hasComponentRow(self.shadow_caster, stored_handle);
        const receives_shadow = hasComponentRow(self.shadow_receiver, stored_handle);

        if (self.geometry) |geometry| {
            if (self.material) |material| {
                if (geometry.valueAt(stored_handle)) |geometry_value| {
                    if (material.valueAt(stored_handle)) |material_value| {
                        return .{
                            .entity = stored_handle,
                            .id = stored_entity.id,
                            .name = stored_entity.name,
                            .position = transform.position,
                            .rotation = transform.rotation,
                            .scale = transform.scale,
                            .primitive = geometry_value.primitive,
                            .segments = geometry_value.segments,
                            .rings = geometry_value.rings,
                            .base_color = material_value.base_color,
                            .spin = spin,
                            .casts_shadow = casts_shadow,
                            .receives_shadow = receives_shadow,
                        };
                    }
                }
            }
        }

        if (self.cube) |cube| {
            if (cube.valueAt(stored_handle)) |cube_value| {
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
                    .base_color = cube_value.color,
                    .spin = spin,
                    .casts_shadow = casts_shadow,
                    .receives_shadow = receives_shadow,
                };
            }
        }

        return null;
    }
};

const TransformLookup = struct {
    table: *const ComponentTable,
    position: *const ComponentColumn,
    rotation: *const ComponentColumn,
    scale: *const ComponentColumn,

    fn init(table: ?*const ComponentTable) ?TransformLookup {
        const resolved = table orelse return null;
        return .{
            .table = resolved,
            .position = findColumn(resolved.*, "position") orelse return null,
            .rotation = findColumn(resolved.*, "rotation") orelse return null,
            .scale = findColumn(resolved.*, "scale") orelse return null,
        };
    }

    fn valueAt(self: TransformLookup, handle: EntityHandle) ?Transform {
        const row = rowForEntity(self.table.*, handle) orelse return null;
        return .{
            .position = vec3ColumnValue(self.position, row) orelse return null,
            .rotation = vec3ColumnValue(self.rotation, row) orelse return null,
            .scale = vec3ColumnValue(self.scale, row) orelse return null,
        };
    }
};

const GeometryLookup = struct {
    table: *const ComponentTable,
    primitive: *const ComponentColumn,
    segments: *const ComponentColumn,
    rings: *const ComponentColumn,

    const Value = struct {
        primitive: []const u8,
        segments: i32,
        rings: i32,
    };

    fn init(table: ?*const ComponentTable) ?GeometryLookup {
        const resolved = table orelse return null;
        return .{
            .table = resolved,
            .primitive = findColumn(resolved.*, "primitive") orelse return null,
            .segments = findColumn(resolved.*, "segments") orelse return null,
            .rings = findColumn(resolved.*, "rings") orelse return null,
        };
    }

    fn valueAt(self: GeometryLookup, handle: EntityHandle) ?Value {
        const row = rowForEntity(self.table.*, handle) orelse return null;
        return .{
            .primitive = stringColumnValue(self.primitive, row) orelse return null,
            .segments = intColumnValue(self.segments, row) orelse return null,
            .rings = intColumnValue(self.rings, row) orelse return null,
        };
    }
};

const MaterialLookup = struct {
    table: *const ComponentTable,
    base_color: *const ComponentColumn,

    const Value = struct {
        base_color: [3]f32,
    };

    fn init(table: ?*const ComponentTable) ?MaterialLookup {
        const resolved = table orelse return null;
        return .{
            .table = resolved,
            .base_color = findColumn(resolved.*, "base_color") orelse return null,
        };
    }

    fn valueAt(self: MaterialLookup, handle: EntityHandle) ?Value {
        const row = rowForEntity(self.table.*, handle) orelse return null;
        return .{
            .base_color = vec3ColumnValue(self.base_color, row) orelse return null,
        };
    }
};

const CubeLookup = struct {
    table: *const ComponentTable,
    color: *const ComponentColumn,

    const Value = struct {
        color: [3]f32,
    };

    fn init(table: ?*const ComponentTable) ?CubeLookup {
        const resolved = table orelse return null;
        return .{
            .table = resolved,
            .color = findColumn(resolved.*, "color") orelse return null,
        };
    }

    fn valueAt(self: CubeLookup, handle: EntityHandle) ?Value {
        const row = rowForEntity(self.table.*, handle) orelse return null;
        return .{
            .color = vec3ColumnValue(self.color, row) orelse return null,
        };
    }
};

const SpinLookup = struct {
    table: *const ComponentTable,
    angular_velocity: *const ComponentColumn,

    fn init(table: ?*const ComponentTable) ?SpinLookup {
        const resolved = table orelse return null;
        return .{
            .table = resolved,
            .angular_velocity = findColumn(resolved.*, "angular_velocity") orelse return null,
        };
    }

    fn valueAt(self: SpinLookup, handle: EntityHandle) ?[3]f32 {
        const row = rowForEntity(self.table.*, handle) orelse return null;
        return vec3ColumnValue(self.angular_velocity, row);
    }
};

fn hasComponentRow(table: ?*const ComponentTable, handle: EntityHandle) bool {
    const resolved = table orelse return false;
    return rowForEntity(resolved.*, handle) != null;
}

fn vec3ColumnValue(column: *const ComponentColumn, row: usize) ?[3]f32 {
    return switch (column.values) {
        .vec3 => |values| values.items[row],
        else => null,
    };
}

fn intColumnValue(column: *const ComponentColumn, row: usize) ?i32 {
    return switch (column.values) {
        .int => |values| values.items[row],
        else => null,
    };
}

fn stringColumnValue(column: *const ComponentColumn, row: usize) ?[]const u8 {
    return switch (column.values) {
        .string => |values| values.items[row],
        else => null,
    };
}

pub const RenderableCubeIterator = struct {
    world: *const World,
    index: usize = 0,

    pub fn next(self: *RenderableCubeIterator) ?RenderableCube {
        const collector = RenderableMeshCollector.init(self.world.*);
        while (self.index < self.world.entityCount()) {
            const handle = EntityHandle{ .index = @intCast(self.index) };
            self.index += 1;
            const mesh = collector.meshAt(handle) orelse continue;
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
        const collector = RenderableMeshCollector.init(self.world.*);
        while (self.index < self.world.entityCount()) {
            const handle = EntityHandle{ .index = @intCast(self.index) };
            self.index += 1;
            return collector.meshAt(handle) orelse continue;
        }
        return null;
    }
};

pub const UiRectIterator = struct {
    world: *const World,
    table: ?*const ComponentTable = null,
    button_table: ?*const ComponentTable = null,
    position_column: ?*const ComponentColumn = null,
    size_column: ?*const ComponentColumn = null,
    color_column: ?*const ComponentColumn = null,
    corner_radius_column: ?*const ComponentColumn = null,
    entity_index: usize = 0,

    pub fn next(self: *UiRectIterator) ?UiRect {
        const table = self.table orelse return null;
        const position_column = self.position_column orelse return null;
        const size_column = self.size_column orelse return null;
        const color_column = self.color_column orelse return null;
        const corner_radius_column = self.corner_radius_column orelse return null;
        while (self.entity_index < table.rows_by_entity.items.len) {
            const entity_index = self.entity_index;
            self.entity_index += 1;
            const row = table.rows_by_entity.items[entity_index] orelse continue;
            const handle = table.entities.items[row];
            const stored_entity = self.world.entity(handle) catch continue;
            return .{
                .entity = handle,
                .id = stored_entity.id,
                .name = stored_entity.name,
                .position = columnVec3At(position_column, row) orelse return null,
                .size = columnVec3At(size_column, row) orelse return null,
                .color = columnVec3At(color_column, row) orelse return null,
                .corner_radius = columnFloatAt(corner_radius_column, row) orelse return null,
                .is_button = if (self.button_table) |button_table| tableHasEntity(button_table.*, handle) else false,
            };
        }
        return null;
    }
};

pub const UiTextIterator = struct {
    world: *const World,
    table: ?*const ComponentTable = null,
    position_column: ?*const ComponentColumn = null,
    size_column: ?*const ComponentColumn = null,
    color_column: ?*const ComponentColumn = null,
    value_column: ?*const ComponentColumn = null,
    entity_index: usize = 0,

    pub fn next(self: *UiTextIterator) ?UiText {
        const table = self.table orelse return null;
        const position_column = self.position_column orelse return null;
        const size_column = self.size_column orelse return null;
        const color_column = self.color_column orelse return null;
        const value_column = self.value_column orelse return null;
        while (self.entity_index < table.rows_by_entity.items.len) {
            const entity_index = self.entity_index;
            self.entity_index += 1;
            const row = table.rows_by_entity.items[entity_index] orelse continue;
            const handle = table.entities.items[row];
            const stored_entity = self.world.entity(handle) catch continue;
            return .{
                .entity = handle,
                .id = stored_entity.id,
                .name = stored_entity.name,
                .position = columnVec3At(position_column, row) orelse return null,
                .size = columnFloatAt(size_column, row) orelse return null,
                .color = columnVec3At(color_column, row) orelse return null,
                .value = columnStringAt(value_column, row) orelse return null,
            };
        }
        return null;
    }
};

pub const UiSeparatorIterator = struct {
    world: *const World,
    table: ?*const ComponentTable = null,
    position_column: ?*const ComponentColumn = null,
    size_column: ?*const ComponentColumn = null,
    color_column: ?*const ComponentColumn = null,
    entity_index: usize = 0,

    pub fn next(self: *UiSeparatorIterator) ?UiSeparator {
        const table = self.table orelse return null;
        const position_column = self.position_column orelse return null;
        const size_column = self.size_column orelse return null;
        const color_column = self.color_column orelse return null;
        while (self.entity_index < table.rows_by_entity.items.len) {
            const entity_index = self.entity_index;
            self.entity_index += 1;
            const row = table.rows_by_entity.items[entity_index] orelse continue;
            const handle = table.entities.items[row];
            const stored_entity = self.world.entity(handle) catch continue;
            return .{
                .entity = handle,
                .id = stored_entity.id,
                .name = stored_entity.name,
                .position = columnVec3At(position_column, row) orelse return null,
                .size = columnVec3At(size_column, row) orelse return null,
                .color = columnVec3At(color_column, row) orelse return null,
            };
        }
        return null;
    }
};

fn tableHasEntity(table: ComponentTable, handle: EntityHandle) bool {
    const index: usize = handle.index;
    if (index >= table.rows_by_entity.items.len) {
        return false;
    }
    const row = table.rows_by_entity.items[index] orelse return false;
    const stored = table.entities.items[row];
    return handle.generation == 0 or stored.generation == 0 or stored.generation == handle.generation;
}

fn columnVec3At(column: *const ComponentColumn, row: usize) ?[3]f32 {
    return switch (column.values) {
        .vec3 => |values| if (row < values.items.len) values.items[row] else null,
        else => null,
    };
}

fn columnFloatAt(column: *const ComponentColumn, row: usize) ?f32 {
    return switch (column.values) {
        .float => |values| if (row < values.items.len) values.items[row] else null,
        else => null,
    };
}

fn columnStringAt(column: *const ComponentColumn, row: usize) ?[]const u8 {
    return switch (column.values) {
        .string => |values| if (row < values.items.len) values.items[row] else null,
        else => null,
    };
}

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

test {
    _ = @import("tests.zig");
}
