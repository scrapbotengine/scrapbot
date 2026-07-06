const std = @import("std");
const render = @import("../render.zig");
const runtime = @import("../runtime.zig");

const Io = std.Io;

pub const Scene = struct {
    name: []const u8,
    world: runtime.World,

    pub fn renderScene(self: *Scene) render.Scene {
        return .{ .world = &self.world };
    }

    pub fn entityCount(self: Scene) usize {
        return self.world.entityCount();
    }

    pub fn componentInstanceCount(self: Scene) usize {
        return self.world.componentInstanceCount();
    }

    pub fn renderableCubeCount(self: Scene) usize {
        return self.world.renderableCubeCount();
    }

    pub fn renderableMeshCount(self: Scene) usize {
        return self.world.renderableMeshCount();
    }
};

pub fn freeScene(allocator: std.mem.Allocator, scene: Scene) void {
    allocator.free(scene.name);
    var world = scene.world;
    world.deinit();
}

pub fn loadSceneFile(io: Io, allocator: std.mem.Allocator, root_dir: Io.Dir, scene_path: []const u8, registry: runtime.ComponentRegistry) !Scene {
    const contents = root_dir.readFileAlloc(io, scene_path, allocator, .limited(256 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return error.MissingDefaultScene,
        else => return err,
    };
    defer allocator.free(contents);

    const name = try readRequiredRootString(allocator, contents, "name") orelse return error.InvalidProject;
    errdefer allocator.free(name);

    const version_value = readRequiredRootInt(contents, "version") orelse return error.UnsupportedProjectVersion;
    if (version_value != 1) {
        return error.UnsupportedProjectVersion;
    }

    var parser = SceneParser{
        .allocator = allocator,
        .world = runtime.World.init(allocator),
        .registry = registry,
    };
    return .{
        .name = name,
        .world = try parser.parse(contents),
    };
}

const SceneParser = struct {
    allocator: std.mem.Allocator,
    world: runtime.World,
    registry: runtime.ComponentRegistry,
    active_entity: ?EntityDraft = null,

    fn parse(self: *SceneParser, contents: []const u8) !runtime.World {
        errdefer {
            if (self.active_entity) |*entity| {
                entity.deinit();
                self.active_entity = null;
            }
            self.world.deinit();
        }

        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') {
                continue;
            }

            if (std.mem.eql(u8, trimmed, "[[entities]]")) {
                try self.flushEntity();
                self.active_entity = EntityDraft.init(self.allocator);
                continue;
            }

            if (trimmed[0] == '[') {
                if (self.active_entity) |*entity| {
                    const component_id = parseComponentTableHeader(trimmed) orelse return error.InvalidSceneEntity;
                    if (self.registry.findComponent(component_id) == null) {
                        return error.InvalidSceneEntity;
                    }
                    entity.active_component = component_id;
                    _ = try entity.ensureComponent(component_id);
                    continue;
                }
                return error.InvalidSceneEntity;
            }

            if (self.active_entity) |*entity| {
                try entity.readProperty(trimmed, self.registry);
            }
        }

        try self.flushEntity();
        if (self.world.entityCount() == 0) {
            return error.MissingSceneContent;
        }
        if (self.world.componentInstanceCountFor(runtime.renderer_component_id) > 1) {
            return error.InvalidSceneEntity;
        }

        const world = self.world;
        self.world = runtime.World.init(self.allocator);
        return world;
    }

    fn flushEntity(self: *SceneParser) !void {
        var entity = self.active_entity orelse return;
        defer entity.deinit();
        self.active_entity = null;
        if (!entity.id_seen or !entity.name_seen or entity.components.items.len == 0) {
            return error.InvalidSceneEntity;
        }
        const handle = self.world.createAuthoredEntity(entity.id, entity.name) catch |err| switch (err) {
            runtime.WorldError.DuplicateEntityId => return error.DuplicateSceneEntityId,
            else => return err,
        };
        for (entity.components.items) |*component| {
            const definition = self.registry.findComponent(component.id) orelse return error.InvalidSceneEntity;
            try addSceneComponentDefaults(self.allocator, component);
            if (!componentHasEveryDefinedField(component.*, definition.*)) {
                return error.InvalidSceneEntity;
            }
            try validateSceneComponentValues(component.*);
            try self.world.setComponent(handle, component.id, component.fields.items);
        }
    }
};

fn addSceneComponentDefaults(allocator: std.mem.Allocator, component: *ComponentDraft) !void {
    if (std.mem.eql(u8, component.id, runtime.ui_canvas_component_id)) {
        try addSceneComponentDefaultField(allocator, component, "design_size", .{ .vec3 = .{ 0.0, 0.0, 0.0 } });
        try addSceneComponentDefaultField(allocator, component, "scale_mode", .{ .string = "none" });
    } else if (std.mem.eql(u8, component.id, runtime.ui_rect_component_id)) {
        try addSceneComponentDefaultField(allocator, component, "corner_radius", .{ .float = 0.0 });
    } else if (std.mem.eql(u8, component.id, runtime.ui_table_component_id)) {
        try addSceneComponentDefaultField(allocator, component, "columns", .{ .int = 2 });
        try addSceneComponentDefaultField(allocator, component, "row_height", .{ .float = 1.0 });
        try addSceneComponentDefaultField(allocator, component, "column_gap", .{ .float = 0.0 });
        try addSceneComponentDefaultField(allocator, component, "row_gap", .{ .float = 0.0 });
        try addSceneComponentDefaultField(allocator, component, "padding", .{ .vec3 = .{ 0.0, 0.0, 0.0 } });
        try addSceneComponentDefaultField(allocator, component, "first_column_ratio", .{ .float = 0.5 });
    } else if (std.mem.eql(u8, component.id, runtime.ui_layout_item_component_id)) {
        try addSceneComponentDefaultField(allocator, component, "min_size", .{ .vec3 = .{ 0.0, 0.0, 0.0 } });
        try addSceneComponentDefaultField(allocator, component, "preferred_size", .{ .vec3 = .{ 0.0, 0.0, 0.0 } });
        try addSceneComponentDefaultField(allocator, component, "max_size", .{ .vec3 = .{ 0.0, 0.0, 0.0 } });
        try addSceneComponentDefaultField(allocator, component, "grow", .{ .float = 0.0 });
        try addSceneComponentDefaultField(allocator, component, "shrink", .{ .float = 0.0 });
        try addSceneComponentDefaultField(allocator, component, "align", .{ .string = "start" });
        try addSceneComponentDefaultField(allocator, component, "margin", .{ .vec3 = .{ 0.0, 0.0, 0.0 } });
    } else if (std.mem.eql(u8, component.id, runtime.renderer_component_id)) {
        try addSceneComponentDefaultField(allocator, component, "hdr", .{ .boolean = true });
        try addSceneComponentDefaultField(allocator, component, "tone_mapping", .{ .string = "aces" });
        try addSceneComponentDefaultField(allocator, component, "exposure", .{ .float = 0.0 });
        try addSceneComponentDefaultField(allocator, component, "postprocess_enabled", .{ .boolean = true });
        try addSceneComponentDefaultField(allocator, component, "antialiasing", .{ .string = "fxaa" });
        try addSceneComponentDefaultField(allocator, component, "bloom_enabled", .{ .boolean = true });
        try addSceneComponentDefaultField(allocator, component, "bloom_threshold", .{ .float = 0.85 });
        try addSceneComponentDefaultField(allocator, component, "bloom_intensity", .{ .float = 0.12 });
        try addSceneComponentDefaultField(allocator, component, "bloom_radius", .{ .float = 1.0 });
        try addSceneComponentDefaultField(allocator, component, "vignette_enabled", .{ .boolean = true });
        try addSceneComponentDefaultField(allocator, component, "vignette_strength", .{ .float = 0.24 });
        try addSceneComponentDefaultField(allocator, component, "vignette_radius", .{ .float = 0.82 });
        try addSceneComponentDefaultField(allocator, component, "chromatic_aberration_enabled", .{ .boolean = true });
        try addSceneComponentDefaultField(allocator, component, "chromatic_aberration_strength", .{ .float = 0.0025 });
    }
}

fn validateSceneComponentValues(component: ComponentDraft) !void {
    if (!std.mem.eql(u8, component.id, runtime.renderer_component_id)) {
        return;
    }

    const tone_mapping = componentString(component, "tone_mapping") orelse return error.InvalidSceneEntity;
    if (!isOneOf(tone_mapping, &.{ "none", "reinhard", "aces" })) {
        return error.InvalidSceneEntity;
    }
    const antialiasing = componentString(component, "antialiasing") orelse return error.InvalidSceneEntity;
    if (!isOneOf(antialiasing, &.{ "none", "fxaa" })) {
        return error.InvalidSceneEntity;
    }

    try validateFiniteFloat(component, "exposure", null);
    try validateFiniteFloat(component, "bloom_threshold", 0.0);
    try validateFiniteFloat(component, "bloom_intensity", 0.0);
    try validateFiniteFloat(component, "bloom_radius", 0.0);
    try validateFiniteFloat(component, "vignette_strength", 0.0);
    try validateFiniteFloat(component, "vignette_radius", 0.0001);
    try validateFiniteFloat(component, "chromatic_aberration_strength", 0.0);
}

fn validateFiniteFloat(component: ComponentDraft, field_name: []const u8, min_value: ?f32) !void {
    const value = componentFloat(component, field_name) orelse return error.InvalidSceneEntity;
    if (!std.math.isFinite(value)) {
        return error.InvalidSceneEntity;
    }
    if (min_value) |minimum| {
        if (value < minimum) {
            return error.InvalidSceneEntity;
        }
    }
}

fn componentString(component: ComponentDraft, field_name: []const u8) ?[]const u8 {
    for (component.fields.items) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return switch (field.value) {
                .string => |value| value,
                else => null,
            };
        }
    }
    return null;
}

fn componentFloat(component: ComponentDraft, field_name: []const u8) ?f32 {
    for (component.fields.items) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return switch (field.value) {
                .float => |value| value,
                else => null,
            };
        }
    }
    return null;
}

fn isOneOf(value: []const u8, candidates: []const []const u8) bool {
    for (candidates) |candidate| {
        if (std.mem.eql(u8, value, candidate)) {
            return true;
        }
    }
    return false;
}

fn addSceneComponentDefaultField(allocator: std.mem.Allocator, component: *ComponentDraft, name: []const u8, value: runtime.ComponentValue) !void {
    if (componentHasField(component.*, name)) {
        return;
    }
    try component.fields.append(allocator, .{
        .name = name,
        .value = value,
    });
}

const EntityDraft = struct {
    allocator: std.mem.Allocator,
    id_seen: bool = false,
    name_seen: bool = false,
    id: []const u8 = "",
    name: []const u8 = "",
    components: std.ArrayList(ComponentDraft) = .empty,
    active_component: ?[]const u8 = null,

    fn init(allocator: std.mem.Allocator) EntityDraft {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *EntityDraft) void {
        for (self.components.items) |*component| {
            component.deinit(self.allocator);
        }
        self.components.deinit(self.allocator);
    }

    fn readProperty(self: *EntityDraft, line: []const u8, registry: runtime.ComponentRegistry) !void {
        const eq_index = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidSceneEntity;
        const key = std.mem.trim(u8, line[0..eq_index], " \t");
        const value = std.mem.trim(u8, line[eq_index + 1 ..], " \t");

        if (self.active_component) |component_id| {
            try self.readComponentProperty(component_id, key, value, registry);
        } else if (std.mem.eql(u8, key, "id")) {
            self.id = stringValue(value) orelse return error.InvalidSceneEntity;
            self.id_seen = true;
        } else if (std.mem.eql(u8, key, "name")) {
            self.name = stringValue(value) orelse return error.InvalidSceneEntity;
            self.name_seen = true;
        } else {
            return error.InvalidSceneEntity;
        }
    }

    fn readComponentProperty(self: *EntityDraft, component_id: []const u8, key: []const u8, value: []const u8, registry: runtime.ComponentRegistry) !void {
        const definition = registry.findComponent(component_id) orelse return error.InvalidSceneEntity;
        const field_definition = findComponentField(definition.*, key) orelse return error.InvalidSceneEntity;
        const component = try self.ensureComponent(component_id);
        for (component.fields.items) |field| {
            if (std.mem.eql(u8, field.name, key)) {
                return error.InvalidSceneEntity;
            }
        }
        const field_value = try readComponentValue(field_definition.value_type, value);
        try component.fields.append(self.allocator, .{
            .name = key,
            .value = field_value,
        });
    }

    fn ensureComponent(self: *EntityDraft, component_id: []const u8) !*ComponentDraft {
        for (self.components.items) |*component| {
            if (std.mem.eql(u8, component.id, component_id)) {
                return component;
            }
        }
        try self.components.append(self.allocator, .{ .id = component_id });
        return &self.components.items[self.components.items.len - 1];
    }
};

const ComponentDraft = struct {
    id: []const u8,
    fields: std.ArrayList(runtime.ComponentFieldValue) = .empty,

    fn deinit(self: *ComponentDraft, allocator: std.mem.Allocator) void {
        self.fields.deinit(allocator);
    }
};

fn parseComponentTableHeader(header: []const u8) ?[]const u8 {
    const prefix = "[entities.components.";
    if (!std.mem.startsWith(u8, header, prefix) or header[header.len - 1] != ']') {
        return null;
    }
    const raw_id = std.mem.trim(u8, header[prefix.len .. header.len - 1], " \t");
    if (raw_id.len >= 2 and raw_id[0] == '"' and raw_id[raw_id.len - 1] == '"') {
        return raw_id[1 .. raw_id.len - 1];
    }
    return raw_id;
}

fn findComponentField(definition: runtime.ComponentDefinition, field_name: []const u8) ?runtime.ComponentFieldDefinition {
    for (definition.fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return field;
        }
    }
    return null;
}

fn componentHasEveryDefinedField(component: ComponentDraft, definition: runtime.ComponentDefinition) bool {
    for (definition.fields) |field| {
        if (!componentHasField(component, field.name)) {
            return false;
        }
    }
    return true;
}

fn componentHasField(component: ComponentDraft, field_name: []const u8) bool {
    for (component.fields.items) |value| {
        if (std.mem.eql(u8, value.name, field_name)) {
            return true;
        }
    }
    return false;
}

fn readComponentValue(field_type: runtime.FieldType, value: []const u8) !runtime.ComponentValue {
    return switch (field_type) {
        .boolean => .{ .boolean = try readBool(value) },
        .int => .{ .int = std.fmt.parseInt(i32, value, 10) catch return error.InvalidSceneNumber },
        .float => .{ .float = std.fmt.parseFloat(f32, value) catch return error.InvalidSceneNumber },
        .vec3 => .{ .vec3 = try readVec3(value) },
        .string => .{ .string = stringValue(value) orelse return error.InvalidSceneEntity },
    };
}

fn readBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) {
        return true;
    }
    if (std.mem.eql(u8, value, "false")) {
        return false;
    }
    return error.InvalidSceneEntity;
}

fn stringValue(value: []const u8) ?[]const u8 {
    if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') {
        return null;
    }
    return value[1 .. value.len - 1];
}

fn readVec3(value: []const u8) ![3]f32 {
    if (value.len < 5 or value[0] != '[' or value[value.len - 1] != ']') {
        return error.InvalidSceneNumber;
    }

    var result: [3]f32 = undefined;
    var count: usize = 0;
    var parts = std.mem.splitScalar(u8, value[1 .. value.len - 1], ',');
    while (parts.next()) |part| {
        if (count >= result.len) {
            return error.InvalidSceneNumber;
        }
        const trimmed = std.mem.trim(u8, part, " \t\r");
        if (trimmed.len == 0) {
            return error.InvalidSceneNumber;
        }
        result[count] = std.fmt.parseFloat(f32, trimmed) catch return error.InvalidSceneNumber;
        count += 1;
    }

    if (count != result.len) {
        return error.InvalidSceneNumber;
    }
    return result;
}
fn readRequiredRootString(allocator: std.mem.Allocator, contents: []const u8, key: []const u8) !?[]const u8 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }
        if (trimmed[0] == '[') {
            break;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const found_key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, found_key, key)) {
            continue;
        }

        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') {
            return null;
        }
        return try decodeTomlBasicString(allocator, value[1 .. value.len - 1]);
    }

    return null;
}
fn decodeTomlBasicString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        const byte = value[index];
        if (byte != '\\') {
            try out.append(allocator, byte);
            continue;
        }

        index += 1;
        if (index >= value.len) {
            return error.InvalidProject;
        }

        switch (value[index]) {
            '\\' => try out.append(allocator, '\\'),
            '"' => try out.append(allocator, '"'),
            'n' => try out.append(allocator, '\n'),
            'r' => try out.append(allocator, '\r'),
            't' => try out.append(allocator, '\t'),
            else => return error.InvalidProject,
        }
    }

    return try out.toOwnedSlice(allocator);
}
fn readRequiredRootInt(contents: []const u8, key: []const u8) ?u32 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }
        if (trimmed[0] == '[') {
            break;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const found_key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, found_key, key)) {
            continue;
        }

        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        return std.fmt.parseInt(u32, value, 10) catch null;
    }

    return null;
}
