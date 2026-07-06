const std = @import("std");
const components = @import("components.zig");

const FieldType = components.FieldType;
const ComponentValue = components.ComponentValue;
const EntityHandle = components.EntityHandle;
pub const StorageError = std.mem.Allocator.Error || error{InvalidFieldType};

pub const ComponentColumnValues = union(FieldType) {
    boolean: std.ArrayList(bool),
    int: std.ArrayList(i32),
    float: std.ArrayList(f32),
    vec3: std.ArrayList([3]f32),
    string: std.ArrayList([]const u8),

    pub fn init(value: ComponentValue) ComponentColumnValues {
        return switch (value) {
            .boolean => .{ .boolean = .empty },
            .int => .{ .int = .empty },
            .float => .{ .float = .empty },
            .vec3 => .{ .vec3 = .empty },
            .string => .{ .string = .empty },
        };
    }

    pub fn deinit(self: *ComponentColumnValues, allocator: std.mem.Allocator) void {
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

    pub fn clearRetainingCapacity(self: *ComponentColumnValues, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .boolean => |*values| values.clearRetainingCapacity(),
            .int => |*values| values.clearRetainingCapacity(),
            .float => |*values| values.clearRetainingCapacity(),
            .vec3 => |*values| values.clearRetainingCapacity(),
            .string => |*values| {
                for (values.items) |value| {
                    allocator.free(value);
                }
                values.clearRetainingCapacity();
            },
        }
    }

    pub fn appendCopy(self: *ComponentColumnValues, allocator: std.mem.Allocator, value: ComponentValue) StorageError!void {
        switch (self.*) {
            .boolean => |*values| switch (value) {
                .boolean => |payload| try values.append(allocator, payload),
                else => return StorageError.InvalidFieldType,
            },
            .int => |*values| switch (value) {
                .int => |payload| try values.append(allocator, payload),
                else => return StorageError.InvalidFieldType,
            },
            .float => |*values| switch (value) {
                .float => |payload| try values.append(allocator, payload),
                else => return StorageError.InvalidFieldType,
            },
            .vec3 => |*values| switch (value) {
                .vec3 => |payload| try values.append(allocator, payload),
                else => return StorageError.InvalidFieldType,
            },
            .string => |*values| switch (value) {
                .string => |payload| {
                    const owned = try allocator.dupe(u8, payload);
                    errdefer allocator.free(owned);
                    try values.append(allocator, owned);
                },
                else => return StorageError.InvalidFieldType,
            },
        }
    }

    pub fn setCopy(self: *ComponentColumnValues, allocator: std.mem.Allocator, row: usize, value: ComponentValue) StorageError!void {
        switch (self.*) {
            .boolean => |*values| switch (value) {
                .boolean => |payload| values.items[row] = payload,
                else => return StorageError.InvalidFieldType,
            },
            .int => |*values| switch (value) {
                .int => |payload| values.items[row] = payload,
                else => return StorageError.InvalidFieldType,
            },
            .float => |*values| switch (value) {
                .float => |payload| values.items[row] = payload,
                else => return StorageError.InvalidFieldType,
            },
            .vec3 => |*values| switch (value) {
                .vec3 => |payload| values.items[row] = payload,
                else => return StorageError.InvalidFieldType,
            },
            .string => |*values| switch (value) {
                .string => |payload| {
                    const owned = try allocator.dupe(u8, payload);
                    allocator.free(values.items[row]);
                    values.items[row] = owned;
                },
                else => return StorageError.InvalidFieldType,
            },
        }
    }

    pub fn popValue(self: *ComponentColumnValues, allocator: std.mem.Allocator) void {
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

    pub fn swapRemove(self: *ComponentColumnValues, allocator: std.mem.Allocator, row: usize) void {
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

    pub fn valueAt(self: ComponentColumnValues, row: usize) ComponentValue {
        return switch (self) {
            .boolean => |values| .{ .boolean = values.items[row] },
            .int => |values| .{ .int = values.items[row] },
            .float => |values| .{ .float = values.items[row] },
            .vec3 => |values| .{ .vec3 = values.items[row] },
            .string => |values| .{ .string = values.items[row] },
        };
    }

    pub fn valueType(self: ComponentColumnValues) FieldType {
        return switch (self) {
            .boolean => .boolean,
            .int => .int,
            .float => .float,
            .vec3 => .vec3,
            .string => .string,
        };
    }
};

pub const ComponentColumn = struct {
    name: []const u8,
    values: ComponentColumnValues,

    pub fn deinit(self: *ComponentColumn, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.values.deinit(allocator);
    }
};

pub const ComponentTable = struct {
    id: []const u8,
    entities: std.ArrayList(EntityHandle) = .empty,
    rows_by_entity: std.ArrayList(?usize) = .empty,
    columns: []ComponentColumn = &.{},

    pub fn deinit(self: *ComponentTable, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        for (self.columns) |*column| {
            column.deinit(allocator);
        }
        allocator.free(self.columns);
        self.rows_by_entity.deinit(allocator);
        self.entities.deinit(allocator);
    }

    pub fn clearRetainingCapacity(self: *ComponentTable, allocator: std.mem.Allocator) void {
        self.entities.clearRetainingCapacity();
        self.rows_by_entity.clearRetainingCapacity();
        for (self.columns) |*column| {
            column.values.clearRetainingCapacity(allocator);
        }
    }
};
