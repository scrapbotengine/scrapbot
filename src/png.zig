const std = @import("std");
const Io = std.Io;

const signature = [_]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a };
const max_png_bytes = 16 * 1024 * 1024;

pub const Error = error{
    InvalidImageData,
    InvalidPng,
    UnsupportedPng,
};

pub const RgbImage = struct {
    width: usize,
    height: usize,
    pixels: []u8,

    pub fn deinit(self: *RgbImage, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
        self.* = undefined;
    }

    pub fn pixel(self: RgbImage, index: usize) [3]u8 {
        const offset = index * 3;
        return .{
            self.pixels[offset],
            self.pixels[offset + 1],
            self.pixels[offset + 2],
        };
    }
};

pub fn writeRgb24(
    io: Io,
    allocator: std.mem.Allocator,
    output_path: []const u8,
    width: usize,
    height: usize,
    rgb_pixels: []const u8,
) !void {
    if (rgb_pixels.len != width * height * 3) {
        return Error.InvalidImageData;
    }

    var scanlines: std.ArrayList(u8) = .empty;
    defer scanlines.deinit(allocator);
    try scanlines.ensureTotalCapacity(allocator, height * (width * 3 + 1));
    for (0..height) |y| {
        try scanlines.append(allocator, 0);
        const row_offset = y * width * 3;
        try scanlines.appendSlice(allocator, rgb_pixels[row_offset..][0 .. width * 3]);
    }

    const zlib_stream = try compressZlib(allocator, scanlines.items);
    defer allocator.free(zlib_stream);

    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(allocator);
    try bytes.appendSlice(allocator, &signature);

    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], @intCast(width), .big);
    std.mem.writeInt(u32, ihdr[4..8], @intCast(height), .big);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 2; // truecolor RGB
    ihdr[10] = 0; // deflate
    ihdr[11] = 0; // adaptive filtering
    ihdr[12] = 0; // no interlace
    try appendChunk(allocator, &bytes, "IHDR", &ihdr);
    try appendChunk(allocator, &bytes, "IDAT", zlib_stream);
    try appendChunk(allocator, &bytes, "IEND", &.{});

    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = output_path,
        .data = bytes.items,
    });
}

pub fn readRgb24(io: Io, allocator: std.mem.Allocator, path: []const u8) !RgbImage {
    const data = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_png_bytes));
    defer allocator.free(data);

    if (data.len < signature.len or !std.mem.eql(u8, data[0..signature.len], &signature)) {
        return Error.InvalidPng;
    }

    var cursor: usize = signature.len;
    var width: usize = 0;
    var height: usize = 0;
    var idat: std.ArrayList(u8) = .empty;
    defer idat.deinit(allocator);
    var saw_ihdr = false;
    var saw_iend = false;

    while (cursor < data.len) {
        if (cursor + 12 > data.len) {
            return Error.InvalidPng;
        }
        const chunk_len: usize = @intCast(std.mem.readInt(u32, data[cursor..][0..4], .big));
        cursor += 4;
        const chunk_type = data[cursor..][0..4];
        cursor += 4;
        if (cursor + chunk_len + 4 > data.len) {
            return Error.InvalidPng;
        }
        const chunk_data = data[cursor..][0..chunk_len];
        cursor += chunk_len;
        const expected_crc = std.mem.readInt(u32, data[cursor..][0..4], .big);
        cursor += 4;
        if (chunkCrc(chunk_type, chunk_data) != expected_crc) {
            return Error.InvalidPng;
        }

        if (std.mem.eql(u8, chunk_type, "IHDR")) {
            if (saw_ihdr or chunk_data.len != 13) {
                return Error.InvalidPng;
            }
            width = @intCast(std.mem.readInt(u32, chunk_data[0..4], .big));
            height = @intCast(std.mem.readInt(u32, chunk_data[4..8], .big));
            const supported = width > 0 and
                height > 0 and
                chunk_data[8] == 8 and
                chunk_data[9] == 2 and
                chunk_data[10] == 0 and
                chunk_data[11] == 0 and
                chunk_data[12] == 0;
            if (!supported) {
                return Error.UnsupportedPng;
            }
            saw_ihdr = true;
        } else if (std.mem.eql(u8, chunk_type, "IDAT")) {
            if (!saw_ihdr) {
                return Error.InvalidPng;
            }
            try idat.appendSlice(allocator, chunk_data);
        } else if (std.mem.eql(u8, chunk_type, "IEND")) {
            saw_iend = true;
            break;
        }
    }

    if (!saw_ihdr or !saw_iend) {
        return Error.InvalidPng;
    }

    const scanline_len = width * 3 + 1;
    const expected_scanline_bytes = scanline_len * height;
    const scanlines = try allocator.alloc(u8, expected_scanline_bytes);
    defer allocator.free(scanlines);
    try readZlib(idat.items, scanlines);

    const pixels = try allocator.alloc(u8, width * height * 3);
    errdefer allocator.free(pixels);
    for (0..height) |y| {
        const scanline_offset = y * scanline_len;
        if (scanlines[scanline_offset] != 0) {
            return Error.UnsupportedPng;
        }
        const pixel_offset = y * width * 3;
        @memcpy(pixels[pixel_offset..][0 .. width * 3], scanlines[scanline_offset + 1 ..][0 .. width * 3]);
    }

    return .{
        .width = width,
        .height = height,
        .pixels = pixels,
    };
}

fn appendChunk(allocator: std.mem.Allocator, output: *std.ArrayList(u8), chunk_type: []const u8, data: []const u8) !void {
    if (chunk_type.len != 4) {
        return Error.InvalidPng;
    }
    var length_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &length_bytes, @intCast(data.len), .big);
    try output.appendSlice(allocator, &length_bytes);
    try output.appendSlice(allocator, chunk_type);
    try output.appendSlice(allocator, data);
    var crc_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_bytes, chunkCrc(chunk_type, data), .big);
    try output.appendSlice(allocator, &crc_bytes);
}

fn chunkCrc(chunk_type: []const u8, data: []const u8) u32 {
    var crc = std.hash.Crc32.init();
    crc.update(chunk_type);
    crc.update(data);
    return crc.final();
}

fn compressZlib(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var output = try Io.Writer.Allocating.initCapacity(allocator, @min(data.len, 64 * 1024));
    defer output.deinit();

    const compressor_buffer = try allocator.alloc(u8, std.compress.flate.max_window_len);
    defer allocator.free(compressor_buffer);

    var compressor = try std.compress.flate.Compress.init(
        &output.writer,
        compressor_buffer,
        .zlib,
        .fastest,
    );
    try compressor.writer.writeAll(data);
    try compressor.finish();
    return output.toOwnedSlice();
}

fn readZlib(data: []const u8, output: []u8) !void {
    var reader: Io.Reader = .fixed(data);
    var writer: Io.Writer = .fixed(output);
    var decompressor = std.compress.flate.Decompress.init(&reader, .zlib, &.{});
    const decompressed_len = try decompressor.reader.streamRemaining(&writer);
    if (decompressed_len != output.len) {
        return Error.InvalidPng;
    }
    if (writer.buffered().len != output.len) {
        return Error.InvalidPng;
    }
}
