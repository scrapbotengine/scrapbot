const std = @import("std");

pub const WorldError = error{
    DuplicateEntityId,
    InvalidEntity,
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
