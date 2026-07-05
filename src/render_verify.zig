const std = @import("std");
const Io = std.Io;
const png = @import("png.zig");

pub const VerificationOptions = struct {
    min_foreground_pixels: usize = 1_000,
    min_visible_components: usize = 1,
    min_color_groups: usize = 1,
};

pub const Verification = struct {
    width: u32,
    height: u32,
    foreground_pixels: usize,
    visible_components: usize,
    color_groups: usize,
    warm_pixels: usize,
    cool_pixels: usize,
};

pub const ComparisonOptions = struct {
    max_channel_delta: u8 = 8,
    max_mean_channel_delta: f32 = 1.5,
    max_changed_pixel_ratio: f32 = 0.02,
    changed_pixel_delta: u8 = 2,
};

pub const Comparison = struct {
    width: u32,
    height: u32,
    pixels: usize,
    max_channel_delta: u8,
    mean_channel_delta: f32,
    changed_pixels: usize,
    changed_pixel_ratio: f32,

    pub fn passed(self: Comparison, options: ComparisonOptions) bool {
        return self.max_channel_delta <= options.max_channel_delta and
            self.mean_channel_delta <= options.max_mean_channel_delta and
            self.changed_pixel_ratio <= options.max_changed_pixel_ratio;
    }
};

pub const VerificationError = error{
    InvalidImage,
    MissingForeground,
    MissingVisibleComponents,
    MissingColorGroups,
};

pub const ComparisonError = VerificationError || error{
    ImageSizeMismatch,
};

pub fn verifyImage(io: Io, allocator: std.mem.Allocator, path: []const u8, options: VerificationOptions) !Verification {
    var image = try loadRgbImage(io, allocator, path);
    defer image.deinit(allocator);

    const pixel_count = image.width * image.height;
    var visited = try allocator.alloc(bool, pixel_count);
    defer allocator.free(visited);
    @memset(visited, false);

    var stack = try allocator.alloc(usize, pixel_count);
    defer allocator.free(stack);

    var foreground_pixels: usize = 0;
    var visible_components: usize = 0;
    var warm_pixels: usize = 0;
    var cool_pixels: usize = 0;

    for (0..pixel_count) |start| {
        if (visited[start]) {
            continue;
        }

        visited[start] = true;
        if (!isForegroundRgb(image.pixel(start))) {
            continue;
        }

        var component_area: usize = 0;
        var stack_len: usize = 1;
        stack[0] = start;

        while (stack_len > 0) {
            stack_len -= 1;
            const index = stack[stack_len];
            const rgb = image.pixel(index);
            component_area += 1;
            if (isWarmRgb(rgb)) {
                warm_pixels += 1;
            }
            if (isCoolRgb(rgb)) {
                cool_pixels += 1;
            }

            const x = index % image.width;
            const y = index / image.width;
            const neighbors = [_]?usize{
                if (x > 0) index - 1 else null,
                if (x + 1 < image.width) index + 1 else null,
                if (y > 0) index - image.width else null,
                if (y + 1 < image.height) index + image.width else null,
            };

            for (neighbors) |maybe_neighbor| {
                const neighbor = maybe_neighbor orelse continue;
                if (visited[neighbor]) {
                    continue;
                }
                visited[neighbor] = true;
                if (!isForegroundRgb(image.pixel(neighbor))) {
                    continue;
                }
                stack[stack_len] = neighbor;
                stack_len += 1;
            }
        }

        foreground_pixels += component_area;
        if (component_area >= 100) {
            visible_components += 1;
        }
    }

    if (foreground_pixels < options.min_foreground_pixels) {
        return VerificationError.MissingForeground;
    }
    if (visible_components < options.min_visible_components) {
        return VerificationError.MissingVisibleComponents;
    }

    const color_groups = @as(usize, @intFromBool(warm_pixels >= 500)) + @as(usize, @intFromBool(cool_pixels >= 500));
    if (color_groups < options.min_color_groups) {
        return VerificationError.MissingColorGroups;
    }

    return .{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .foreground_pixels = foreground_pixels,
        .visible_components = visible_components,
        .color_groups = color_groups,
        .warm_pixels = warm_pixels,
        .cool_pixels = cool_pixels,
    };
}

pub fn compareImage(
    io: Io,
    allocator: std.mem.Allocator,
    expected_path: []const u8,
    actual_path: []const u8,
    options: ComparisonOptions,
) !Comparison {
    var expected = try loadRgbImage(io, allocator, expected_path);
    defer expected.deinit(allocator);
    var actual = try loadRgbImage(io, allocator, actual_path);
    defer actual.deinit(allocator);
    if (expected.width != actual.width or expected.height != actual.height) {
        return ComparisonError.ImageSizeMismatch;
    }

    var max_channel_delta: u8 = 0;
    var total_channel_delta: u64 = 0;
    var changed_pixels: usize = 0;

    const pixel_count = expected.width * expected.height;
    for (0..pixel_count) |index| {
        const expected_rgb = expected.pixel(index);
        const actual_rgb = actual.pixel(index);
        var pixel_changed = false;
        const deltas = [_]u8{
            absDiffU8(expected_rgb[0], actual_rgb[0]),
            absDiffU8(expected_rgb[1], actual_rgb[1]),
            absDiffU8(expected_rgb[2], actual_rgb[2]),
        };
        for (deltas) |delta| {
            max_channel_delta = @max(max_channel_delta, delta);
            total_channel_delta += delta;
            if (delta > options.changed_pixel_delta) {
                pixel_changed = true;
            }
        }
        if (pixel_changed) {
            changed_pixels += 1;
        }
    }

    const channel_count = pixel_count * 3;
    return .{
        .width = @intCast(expected.width),
        .height = @intCast(expected.height),
        .pixels = pixel_count,
        .max_channel_delta = max_channel_delta,
        .mean_channel_delta = @as(f32, @floatFromInt(total_channel_delta)) / @as(f32, @floatFromInt(channel_count)),
        .changed_pixels = changed_pixels,
        .changed_pixel_ratio = @as(f32, @floatFromInt(changed_pixels)) / @as(f32, @floatFromInt(pixel_count)),
    };
}

fn loadRgbImage(io: Io, allocator: std.mem.Allocator, path: []const u8) !png.RgbImage {
    const extension = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(extension, ".png")) {
        return png.readRgb24(io, allocator, path);
    }
    if (std.ascii.eqlIgnoreCase(extension, ".bmp")) {
        return loadBmpRgb(io, allocator, path);
    }
    return png.Error.UnsupportedPng;
}

fn loadBmpRgb(io: Io, allocator: std.mem.Allocator, path: []const u8) !png.RgbImage {
    const data = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(data);

    const bmp = try BmpView.parse(data);
    const pixels = try allocator.alloc(u8, bmp.pixel_count * 3);
    errdefer allocator.free(pixels);
    for (0..bmp.pixel_count) |index| {
        const rgb = bmp.rgb(index);
        const offset = index * 3;
        pixels[offset] = rgb[0];
        pixels[offset + 1] = rgb[1];
        pixels[offset + 2] = rgb[2];
    }
    return .{
        .width = bmp.width,
        .height = bmp.height,
        .pixels = pixels,
    };
}

const BmpView = struct {
    data: []const u8,
    pixel_offset: usize,
    width: usize,
    height: usize,
    row_stride: usize,
    pixel_count: usize,

    fn parse(data: []const u8) VerificationError!BmpView {
        if (data.len < 54 or data[0] != 'B' or data[1] != 'M') {
            return VerificationError.InvalidImage;
        }

        const pixel_offset = readU32(data, 10) orelse return VerificationError.InvalidImage;
        const dib_header_size = readU32(data, 14) orelse return VerificationError.InvalidImage;
        const width = readU32(data, 18) orelse return VerificationError.InvalidImage;
        const height = readU32(data, 22) orelse return VerificationError.InvalidImage;
        const planes = readU16(data, 26) orelse return VerificationError.InvalidImage;
        const bits_per_pixel = readU16(data, 28) orelse return VerificationError.InvalidImage;
        const compression = readU32(data, 30) orelse return VerificationError.InvalidImage;

        if (dib_header_size < 40 or width == 0 or height == 0 or planes != 1 or bits_per_pixel != 24 or compression != 0) {
            return VerificationError.InvalidImage;
        }

        const width_usize: usize = @intCast(width);
        const height_usize: usize = @intCast(height);
        const row_stride = ((width_usize * 3) + 3) & ~@as(usize, 3);
        const required_len = @as(usize, @intCast(pixel_offset)) + row_stride * height_usize;
        if (required_len > data.len) {
            return VerificationError.InvalidImage;
        }

        return .{
            .data = data,
            .pixel_offset = @intCast(pixel_offset),
            .width = width_usize,
            .height = height_usize,
            .row_stride = row_stride,
            .pixel_count = width_usize * height_usize,
        };
    }

    fn pixelOffset(self: BmpView, index: usize) usize {
        const x = index % self.width;
        const y = index / self.width;
        const file_y = self.height - y - 1;
        return self.pixel_offset + file_y * self.row_stride + x * 3;
    }

    fn rgb(self: BmpView, index: usize) [3]u8 {
        const pixel = self.pixelOffset(index);
        return .{
            self.data[pixel + 2],
            self.data[pixel + 1],
            self.data[pixel],
        };
    }
};

fn isForegroundRgb(pixel: [3]u8) bool {
    return @max(pixel[0], @max(pixel[1], pixel[2])) >= 55;
}

fn isWarmRgb(pixel: [3]u8) bool {
    return pixel[0] >= 55 and pixel[0] > pixel[2] +| 25;
}

fn isCoolRgb(pixel: [3]u8) bool {
    return pixel[2] >= 55 and pixel[2] > pixel[0] +| 25;
}

fn absDiffU8(left: u8, right: u8) u8 {
    return if (left >= right) left - right else right - left;
}

fn readU16(data: []const u8, offset: usize) ?u16 {
    if (offset + 2 > data.len) {
        return null;
    }
    return @as(u16, data[offset]) | (@as(u16, data[offset + 1]) << 8);
}

fn readU32(data: []const u8, offset: usize) ?u32 {
    if (offset + 4 > data.len) {
        return null;
    }
    return @as(u32, data[offset]) |
        (@as(u32, data[offset + 1]) << 8) |
        (@as(u32, data[offset + 2]) << 16) |
        (@as(u32, data[offset + 3]) << 24);
}
