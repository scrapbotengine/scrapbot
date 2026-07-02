const std = @import("std");

pub const GeometryError = std.mem.Allocator.Error || error{
    UnknownPrimitive,
    MeshTooLarge,
};

pub const Primitive = enum {
    box,
    plane,
    sphere,
    uv_sphere,
    ico_sphere,
};

pub const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
};

pub const Mesh = struct {
    vertices: []Vertex,
    indices: []u16,

    pub fn deinit(self: *Mesh, allocator: std.mem.Allocator) void {
        allocator.free(self.indices);
        allocator.free(self.vertices);
        self.* = .{
            .vertices = &.{},
            .indices = &.{},
        };
    }
};

const Triangle = struct {
    a: [3]f32,
    b: [3]f32,
    c: [3]f32,
};

pub fn parsePrimitive(value: []const u8) ?Primitive {
    if (std.mem.eql(u8, value, "box")) return .box;
    if (std.mem.eql(u8, value, "plane")) return .plane;
    if (std.mem.eql(u8, value, "sphere")) return .sphere;
    if (std.mem.eql(u8, value, "uv_sphere") or std.mem.eql(u8, value, "uvsphere")) return .uv_sphere;
    if (std.mem.eql(u8, value, "ico_sphere") or std.mem.eql(u8, value, "icosphere")) return .ico_sphere;
    return null;
}

pub fn generatePrimitive(
    allocator: std.mem.Allocator,
    primitive: Primitive,
    segments_value: i32,
    rings_value: i32,
) GeometryError!Mesh {
    return switch (primitive) {
        .box => generateBox(allocator),
        .plane => generatePlane(allocator),
        .sphere, .uv_sphere => generateUvSphere(
            allocator,
            resolution(segments_value, 24, 3, 96),
            resolution(rings_value, 12, 2, 96),
        ),
        .ico_sphere => generateIcoSphere(allocator, resolution(segments_value, 2, 0, 5)),
    };
}

fn generateBox(allocator: std.mem.Allocator) GeometryError!Mesh {
    const vertices = [_]Vertex{
        .{ .position = .{ -1.0, -1.0, 1.0 }, .normal = .{ 0.0, 0.0, 1.0 } },
        .{ .position = .{ 1.0, -1.0, 1.0 }, .normal = .{ 0.0, 0.0, 1.0 } },
        .{ .position = .{ 1.0, 1.0, 1.0 }, .normal = .{ 0.0, 0.0, 1.0 } },
        .{ .position = .{ -1.0, 1.0, 1.0 }, .normal = .{ 0.0, 0.0, 1.0 } },

        .{ .position = .{ 1.0, -1.0, -1.0 }, .normal = .{ 0.0, 0.0, -1.0 } },
        .{ .position = .{ -1.0, -1.0, -1.0 }, .normal = .{ 0.0, 0.0, -1.0 } },
        .{ .position = .{ -1.0, 1.0, -1.0 }, .normal = .{ 0.0, 0.0, -1.0 } },
        .{ .position = .{ 1.0, 1.0, -1.0 }, .normal = .{ 0.0, 0.0, -1.0 } },

        .{ .position = .{ -1.0, 1.0, 1.0 }, .normal = .{ 0.0, 1.0, 0.0 } },
        .{ .position = .{ 1.0, 1.0, 1.0 }, .normal = .{ 0.0, 1.0, 0.0 } },
        .{ .position = .{ 1.0, 1.0, -1.0 }, .normal = .{ 0.0, 1.0, 0.0 } },
        .{ .position = .{ -1.0, 1.0, -1.0 }, .normal = .{ 0.0, 1.0, 0.0 } },

        .{ .position = .{ -1.0, -1.0, -1.0 }, .normal = .{ 0.0, -1.0, 0.0 } },
        .{ .position = .{ 1.0, -1.0, -1.0 }, .normal = .{ 0.0, -1.0, 0.0 } },
        .{ .position = .{ 1.0, -1.0, 1.0 }, .normal = .{ 0.0, -1.0, 0.0 } },
        .{ .position = .{ -1.0, -1.0, 1.0 }, .normal = .{ 0.0, -1.0, 0.0 } },

        .{ .position = .{ 1.0, -1.0, 1.0 }, .normal = .{ 1.0, 0.0, 0.0 } },
        .{ .position = .{ 1.0, -1.0, -1.0 }, .normal = .{ 1.0, 0.0, 0.0 } },
        .{ .position = .{ 1.0, 1.0, -1.0 }, .normal = .{ 1.0, 0.0, 0.0 } },
        .{ .position = .{ 1.0, 1.0, 1.0 }, .normal = .{ 1.0, 0.0, 0.0 } },

        .{ .position = .{ -1.0, -1.0, -1.0 }, .normal = .{ -1.0, 0.0, 0.0 } },
        .{ .position = .{ -1.0, -1.0, 1.0 }, .normal = .{ -1.0, 0.0, 0.0 } },
        .{ .position = .{ -1.0, 1.0, 1.0 }, .normal = .{ -1.0, 0.0, 0.0 } },
        .{ .position = .{ -1.0, 1.0, -1.0 }, .normal = .{ -1.0, 0.0, 0.0 } },
    };
    const indices = [_]u16{
        0,  1,  2,  0,  2,  3,
        4,  5,  6,  4,  6,  7,
        8,  9,  10, 8,  10, 11,
        12, 13, 14, 12, 14, 15,
        16, 17, 18, 16, 18, 19,
        20, 21, 22, 20, 22, 23,
    };
    return copyMesh(allocator, &vertices, &indices);
}

fn generatePlane(allocator: std.mem.Allocator) GeometryError!Mesh {
    const vertices = [_]Vertex{
        .{ .position = .{ -1.0, 0.0, -1.0 }, .normal = .{ 0.0, 1.0, 0.0 } },
        .{ .position = .{ 1.0, 0.0, -1.0 }, .normal = .{ 0.0, 1.0, 0.0 } },
        .{ .position = .{ 1.0, 0.0, 1.0 }, .normal = .{ 0.0, 1.0, 0.0 } },
        .{ .position = .{ -1.0, 0.0, 1.0 }, .normal = .{ 0.0, 1.0, 0.0 } },
    };
    const indices = [_]u16{ 0, 1, 2, 0, 2, 3 };
    return copyMesh(allocator, &vertices, &indices);
}

fn generateUvSphere(allocator: std.mem.Allocator, segments: usize, rings: usize) GeometryError!Mesh {
    const vertex_count = (rings + 1) * (segments + 1);
    const index_count = rings * segments * 6;
    if (vertex_count > std.math.maxInt(u16) + 1) {
        return GeometryError.MeshTooLarge;
    }

    const vertices = try allocator.alloc(Vertex, vertex_count);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u16, index_count);
    errdefer allocator.free(indices);

    var vertex_index: usize = 0;
    for (0..rings + 1) |ring| {
        const v = @as(f32, @floatFromInt(ring)) / @as(f32, @floatFromInt(rings));
        const theta = v * std.math.pi;
        const y = @cos(theta);
        const radius = @sin(theta);
        for (0..segments + 1) |segment| {
            const u = @as(f32, @floatFromInt(segment)) / @as(f32, @floatFromInt(segments));
            const phi = u * std.math.pi * 2.0;
            const position = [3]f32{
                radius * @cos(phi),
                y,
                radius * @sin(phi),
            };
            vertices[vertex_index] = .{
                .position = position,
                .normal = normalize(position),
            };
            vertex_index += 1;
        }
    }

    var index: usize = 0;
    for (0..rings) |ring| {
        for (0..segments) |segment| {
            const a = ring * (segments + 1) + segment;
            const b = a + segments + 1;
            indices[index + 0] = try toIndex(a);
            indices[index + 1] = try toIndex(b);
            indices[index + 2] = try toIndex(a + 1);
            indices[index + 3] = try toIndex(a + 1);
            indices[index + 4] = try toIndex(b);
            indices[index + 5] = try toIndex(b + 1);
            index += 6;
        }
    }

    return .{
        .vertices = vertices,
        .indices = indices,
    };
}

fn generateIcoSphere(allocator: std.mem.Allocator, subdivisions: usize) GeometryError!Mesh {
    var triangles: std.ArrayList(Triangle) = .empty;
    defer triangles.deinit(allocator);

    const phi = (1.0 + @sqrt(5.0)) / 2.0;
    const points = [_][3]f32{
        normalize(.{ -1.0, phi, 0.0 }),
        normalize(.{ 1.0, phi, 0.0 }),
        normalize(.{ -1.0, -phi, 0.0 }),
        normalize(.{ 1.0, -phi, 0.0 }),
        normalize(.{ 0.0, -1.0, phi }),
        normalize(.{ 0.0, 1.0, phi }),
        normalize(.{ 0.0, -1.0, -phi }),
        normalize(.{ 0.0, 1.0, -phi }),
        normalize(.{ phi, 0.0, -1.0 }),
        normalize(.{ phi, 0.0, 1.0 }),
        normalize(.{ -phi, 0.0, -1.0 }),
        normalize(.{ -phi, 0.0, 1.0 }),
    };
    const faces = [_][3]usize{
        .{ 0, 11, 5 },
        .{ 0, 5, 1 },
        .{ 0, 1, 7 },
        .{ 0, 7, 10 },
        .{ 0, 10, 11 },
        .{ 1, 5, 9 },
        .{ 5, 11, 4 },
        .{ 11, 10, 2 },
        .{ 10, 7, 6 },
        .{ 7, 1, 8 },
        .{ 3, 9, 4 },
        .{ 3, 4, 2 },
        .{ 3, 2, 6 },
        .{ 3, 6, 8 },
        .{ 3, 8, 9 },
        .{ 4, 9, 5 },
        .{ 2, 4, 11 },
        .{ 6, 2, 10 },
        .{ 8, 6, 7 },
        .{ 9, 8, 1 },
    };

    for (faces) |face| {
        try triangles.append(allocator, .{
            .a = points[face[0]],
            .b = points[face[1]],
            .c = points[face[2]],
        });
    }

    for (0..subdivisions) |_| {
        var next: std.ArrayList(Triangle) = .empty;
        errdefer next.deinit(allocator);

        for (triangles.items) |triangle| {
            const ab = normalize(midpoint(triangle.a, triangle.b));
            const bc = normalize(midpoint(triangle.b, triangle.c));
            const ca = normalize(midpoint(triangle.c, triangle.a));
            try next.append(allocator, .{ .a = triangle.a, .b = ab, .c = ca });
            try next.append(allocator, .{ .a = triangle.b, .b = bc, .c = ab });
            try next.append(allocator, .{ .a = triangle.c, .b = ca, .c = bc });
            try next.append(allocator, .{ .a = ab, .b = bc, .c = ca });
        }

        triangles.deinit(allocator);
        triangles = next;
    }

    const vertex_count = triangles.items.len * 3;
    if (vertex_count > std.math.maxInt(u16) + 1) {
        return GeometryError.MeshTooLarge;
    }

    const vertices = try allocator.alloc(Vertex, vertex_count);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u16, vertex_count);
    errdefer allocator.free(indices);

    var index: usize = 0;
    for (triangles.items) |triangle| {
        for ([_][3]f32{ triangle.a, triangle.b, triangle.c }) |position| {
            vertices[index] = .{
                .position = position,
                .normal = normalize(position),
            };
            indices[index] = try toIndex(index);
            index += 1;
        }
    }

    return .{
        .vertices = vertices,
        .indices = indices,
    };
}

fn copyMesh(allocator: std.mem.Allocator, vertices: []const Vertex, indices: []const u16) GeometryError!Mesh {
    const owned_vertices = try allocator.dupe(Vertex, vertices);
    errdefer allocator.free(owned_vertices);
    const owned_indices = try allocator.dupe(u16, indices);
    return .{
        .vertices = owned_vertices,
        .indices = owned_indices,
    };
}

fn resolution(value: i32, default: usize, minimum: usize, maximum: usize) usize {
    if (value <= 0) {
        return default;
    }
    const unsigned: usize = @intCast(value);
    return @min(@max(unsigned, minimum), maximum);
}

fn toIndex(value: usize) GeometryError!u16 {
    if (value > std.math.maxInt(u16)) {
        return GeometryError.MeshTooLarge;
    }
    return @intCast(value);
}

fn midpoint(a: [3]f32, b: [3]f32) [3]f32 {
    return .{
        (a[0] + b[0]) * 0.5,
        (a[1] + b[1]) * 0.5,
        (a[2] + b[2]) * 0.5,
    };
}

fn normalize(value: [3]f32) [3]f32 {
    const length = @sqrt(value[0] * value[0] + value[1] * value[1] + value[2] * value[2]);
    if (length == 0.0) {
        return .{ 0.0, 1.0, 0.0 };
    }
    return .{ value[0] / length, value[1] / length, value[2] / length };
}

test "built-in geometry generators produce indexed meshes" {
    const allocator = std.testing.allocator;

    var box = try generatePrimitive(allocator, .box, 0, 0);
    defer box.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 24), box.vertices.len);
    try std.testing.expectEqual(@as(usize, 36), box.indices.len);

    var plane = try generatePrimitive(allocator, .plane, 0, 0);
    defer plane.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 4), plane.vertices.len);
    try std.testing.expectEqual(@as(usize, 6), plane.indices.len);

    var uv_sphere = try generatePrimitive(allocator, .uv_sphere, 8, 4);
    defer uv_sphere.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 45), uv_sphere.vertices.len);
    try std.testing.expectEqual(@as(usize, 192), uv_sphere.indices.len);

    var ico_sphere = try generatePrimitive(allocator, .ico_sphere, 1, 0);
    defer ico_sphere.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 240), ico_sphere.vertices.len);
    try std.testing.expectEqual(@as(usize, 240), ico_sphere.indices.len);
}

test "primitive parser accepts built-in geometry names" {
    try std.testing.expectEqual(Primitive.box, parsePrimitive("box").?);
    try std.testing.expectEqual(Primitive.plane, parsePrimitive("plane").?);
    try std.testing.expectEqual(Primitive.sphere, parsePrimitive("sphere").?);
    try std.testing.expectEqual(Primitive.uv_sphere, parsePrimitive("uv_sphere").?);
    try std.testing.expectEqual(Primitive.ico_sphere, parsePrimitive("icosphere").?);
    try std.testing.expect(parsePrimitive("capsule") == null);
}
