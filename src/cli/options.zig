const std = @import("std");
const clap = @import("clap");
const scrapbot = @import("scrapbot");

pub const CheckOutputFormat = enum {
    text,
    json,
};

pub const TopLevel = struct {
    version: bool = false,
    help: bool = false,
    command: ?[]const u8 = null,
};

pub const InitCommandOptions = struct {
    target_path: []const u8 = ".",
};

pub const CheckOptions = struct {
    target_path: []const u8 = ".",
    format: CheckOutputFormat = .text,
};

pub const StepCommandOptions = struct {
    target_path: []const u8 = ".",
    frames: u32 = 1,
    delta_seconds: f32 = 1.0 / 60.0,
    format: CheckOutputFormat = .text,
};

pub const BenchCommandOptions = struct {
    target_path: []const u8 = ".",
    frames: u32 = 240,
    delta_seconds: f32 = 1.0 / 60.0,
    format: CheckOutputFormat = .text,
};

pub const BenchResult = struct {
    project_name: []const u8,
    scene_name: []const u8,
    frames: u32,
    delta_seconds: f32,
    startup_ns: u64,
    update_ns: u64,
    entity_count: usize,
    component_instance_count: usize,
    renderable_count: usize,
    render_batch_count: usize,
    ui_rect_count: usize,
    ui_text_count: usize,

    pub fn nsPerFrame(self: BenchResult) u64 {
        return if (self.frames == 0) 0 else self.update_ns / @as(u64, self.frames);
    }
};

pub const TestCommandOptions = struct {
    target_path: []const u8 = "tests/projects",
    format: CheckOutputFormat = .text,
};

pub const BuildCommandOptions = struct {
    target_path: []const u8 = ".",
    output_root: ?[]const u8 = null,
    name: ?[]const u8 = null,
    force: bool = false,
    format: CheckOutputFormat = .text,
};

pub const RenderCommandOptions = struct {
    target_path: []const u8 = ".",
    output_path: []const u8,
    frames: u32 = 1,
    width: u32 = scrapbot.default_output_width,
    height: u32 = scrapbot.default_output_height,
    pixel_scale: f32 = 1.0,
    editor: bool = false,
    selected_entity_id: ?[]const u8 = null,
};

pub const VisualTestCommandOptions = struct {
    render: RenderCommandOptions,
    expected_path: []const u8,
    update: bool = false,
};

pub const RunCommandOptions = struct {
    target_path: []const u8 = ".",
    window_options: scrapbot.WindowOptions = .{},
};
pub const ArgumentError = error{
    InvalidDelta,
    InvalidFrames,
    InvalidRenderSize,
    InvalidPixelScale,
    InvalidFormat,
    HiddenRequiresFrames,
    MissingExpected,
    UnknownArgument,
};
const clap_parsers = .{
    .COMMAND = clap.parsers.string,
    .PATH = clap.parsers.string,
    .OUTPUT = clap.parsers.string,
    .NAME = clap.parsers.string,
    .ENTITY = clap.parsers.string,
    .EXTRA = clap.parsers.string,
    .FORMAT = parseCheckOutputFormat,
    .FRAMES = parseFrameCount,
    .PIXELS = parseRenderDimension,
    .SCALE = parsePixelScale,
    .SECONDS = parseDeltaSeconds,
};

const SliceArgIterator = struct {
    args: []const []const u8,
    index: usize = 0,

    fn init(args: []const []const u8) SliceArgIterator {
        return .{ .args = args };
    }

    pub fn next(self: *SliceArgIterator) ?[]const u8 {
        if (self.index >= self.args.len) {
            return null;
        }
        defer self.index += 1;
        return self.args[self.index];
    }
};

pub fn parseTopLevel(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!TopLevel {
    const params = comptime clap.parseParamsComptime(
        \\--version
        \\--help
        \\<COMMAND>
        \\
    );
    var iter = SliceArgIterator.init(args);
    var result = clap.parseEx(clap.Help, &params, clap_parsers, &iter, .{
        .allocator = allocator,
        .terminating_positional = 0,
    }) catch |err| return mapClapArgumentError(err);
    defer result.deinit();

    return .{
        .version = result.args.version != 0,
        .help = result.args.help != 0,
        .command = result.positionals[0],
    };
}

pub fn parseWindowOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!scrapbot.WindowOptions {
    return (try parseRunOptions(allocator, args)).window_options;
}

pub fn parseRunOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!RunCommandOptions {
    const params = comptime clap.parseParamsComptime(
        \\--frames <FRAMES>
        \\--editor
        \\--hidden
        \\<PATH>
        \\<EXTRA>...
        \\
    );
    var iter = SliceArgIterator.init(args);
    var result = clap.parseEx(clap.Help, &params, clap_parsers, &iter, .{
        .allocator = allocator,
    }) catch |err| return mapClapArgumentError(err);
    defer result.deinit();

    var options = RunCommandOptions{};
    if (result.positionals[1].len != 0) {
        return ArgumentError.UnknownArgument;
    }
    if (result.positionals[0]) |path| {
        options.target_path = path;
    }
    if (result.args.frames) |frames| {
        options.window_options.max_frames = frames;
    }
    options.window_options.editor = result.args.editor != 0;
    options.window_options.hidden = result.args.hidden != 0;
    if (options.window_options.hidden and options.window_options.max_frames == null) {
        return ArgumentError.HiddenRequiresFrames;
    }
    return options;
}

pub fn parseInitOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!InitCommandOptions {
    const params = comptime clap.parseParamsComptime(
        \\<PATH>
        \\<EXTRA>...
        \\
    );
    var iter = SliceArgIterator.init(args);
    var result = clap.parseEx(clap.Help, &params, clap_parsers, &iter, .{
        .allocator = allocator,
    }) catch |err| return mapClapArgumentError(err);
    defer result.deinit();

    var options = InitCommandOptions{};
    if (result.positionals[1].len != 0) {
        return ArgumentError.UnknownArgument;
    }
    if (result.positionals[0]) |path| {
        options.target_path = path;
    }
    return options;
}

pub fn parseRenderOptions(allocator: std.mem.Allocator, args: []const []const u8, default_output_path: []const u8) ArgumentError!RenderCommandOptions {
    const params = comptime clap.parseParamsComptime(
        \\--editor
        \\--select <ENTITY>
        \\--frames <FRAMES>
        \\--width <PIXELS>
        \\--height <PIXELS>
        \\--pixel-scale <SCALE>
        \\<PATH>
        \\<OUTPUT>
        \\<EXTRA>...
        \\
    );
    var iter = SliceArgIterator.init(args);
    var result = clap.parseEx(clap.Help, &params, clap_parsers, &iter, .{
        .allocator = allocator,
    }) catch |err| return mapClapArgumentError(err);
    defer result.deinit();

    var options = RenderCommandOptions{ .output_path = default_output_path };
    if (result.positionals[2].len != 0) {
        return ArgumentError.UnknownArgument;
    }
    if (result.positionals[0]) |path| {
        options.target_path = path;
    }
    if (result.positionals[1]) |output| {
        options.output_path = output;
    }
    options.editor = result.args.editor != 0;
    if (result.args.select) |entity_id| {
        options.selected_entity_id = entity_id;
        options.editor = true;
    }
    if (result.args.frames) |frames| {
        options.frames = frames;
    }
    if (result.args.width) |width| {
        options.width = width;
    }
    if (result.args.height) |height| {
        options.height = height;
    }
    if (result.args.@"pixel-scale") |pixel_scale| {
        options.pixel_scale = pixel_scale;
    }
    return options;
}

pub fn parseVisualTestOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!VisualTestCommandOptions {
    const params = comptime clap.parseParamsComptime(
        \\--editor
        \\--select <ENTITY>
        \\--frames <FRAMES>
        \\--width <PIXELS>
        \\--height <PIXELS>
        \\--pixel-scale <SCALE>
        \\--update
        \\<PATH>
        \\<OUTPUT>
        \\<EXTRA>...
        \\
    );
    var iter = SliceArgIterator.init(args);
    var result = clap.parseEx(clap.Help, &params, clap_parsers, &iter, .{
        .allocator = allocator,
    }) catch |err| return mapClapArgumentError(err);
    defer result.deinit();

    if (result.positionals[2].len > 1) {
        return ArgumentError.UnknownArgument;
    }
    const target_path = result.positionals[0] orelse return ArgumentError.UnknownArgument;
    const expected_path = result.positionals[1] orelse return ArgumentError.MissingExpected;
    var render = RenderCommandOptions{
        .target_path = target_path,
        .output_path = if (result.positionals[2].len == 1) result.positionals[2][0] else "zig-out/scrapbot-visual-test.png",
    };
    render.editor = result.args.editor != 0;
    if (result.args.select) |entity_id| {
        render.selected_entity_id = entity_id;
        render.editor = true;
    }
    if (result.args.frames) |frames| {
        render.frames = frames;
    }
    if (result.args.width) |width| {
        render.width = width;
    }
    if (result.args.height) |height| {
        render.height = height;
    }
    if (result.args.@"pixel-scale") |pixel_scale| {
        render.pixel_scale = pixel_scale;
    }

    return .{
        .render = render,
        .expected_path = expected_path,
        .update = result.args.update != 0,
    };
}

pub fn parseCheckOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!CheckOptions {
    const params = comptime clap.parseParamsComptime(
        \\--format <FORMAT>
        \\<PATH>
        \\<EXTRA>...
        \\
    );
    var iter = SliceArgIterator.init(args);
    var result = clap.parseEx(clap.Help, &params, clap_parsers, &iter, .{
        .allocator = allocator,
    }) catch |err| return mapClapArgumentError(err);
    defer result.deinit();

    var options = CheckOptions{};
    if (result.positionals[1].len != 0) {
        return ArgumentError.UnknownArgument;
    }
    if (result.positionals[0]) |path| {
        options.target_path = path;
    }
    if (result.args.format) |format| {
        options.format = format;
    }
    return options;
}

pub fn parseStepOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!StepCommandOptions {
    const params = comptime clap.parseParamsComptime(
        \\--frames <FRAMES>
        \\--dt <SECONDS>
        \\--format <FORMAT>
        \\<PATH>
        \\<EXTRA>...
        \\
    );
    var iter = SliceArgIterator.init(args);
    var result = clap.parseEx(clap.Help, &params, clap_parsers, &iter, .{
        .allocator = allocator,
    }) catch |err| return mapClapArgumentError(err);
    defer result.deinit();

    var options = StepCommandOptions{};
    if (result.positionals[1].len != 0) {
        return ArgumentError.UnknownArgument;
    }
    if (result.positionals[0]) |path| {
        options.target_path = path;
    }
    if (result.args.frames) |frames| {
        options.frames = frames;
    }
    if (result.args.dt) |delta_seconds| {
        options.delta_seconds = delta_seconds;
    }
    if (result.args.format) |format| {
        options.format = format;
    }
    return options;
}

pub fn parseBenchOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!BenchCommandOptions {
    const params = comptime clap.parseParamsComptime(
        \\--frames <FRAMES>
        \\--dt <SECONDS>
        \\--format <FORMAT>
        \\<PATH>
        \\<EXTRA>...
        \\
    );
    var iter = SliceArgIterator.init(args);
    var result = clap.parseEx(clap.Help, &params, clap_parsers, &iter, .{
        .allocator = allocator,
    }) catch |err| return mapClapArgumentError(err);
    defer result.deinit();

    var options = BenchCommandOptions{};
    if (result.positionals[1].len != 0) {
        return ArgumentError.UnknownArgument;
    }
    if (result.positionals[0]) |path| {
        options.target_path = path;
    }
    if (result.args.frames) |frames| {
        options.frames = frames;
    }
    if (result.args.dt) |delta_seconds| {
        options.delta_seconds = delta_seconds;
    }
    if (result.args.format) |format| {
        options.format = format;
    }
    return options;
}

pub fn parseTestOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!TestCommandOptions {
    const params = comptime clap.parseParamsComptime(
        \\--format <FORMAT>
        \\<PATH>
        \\<EXTRA>...
        \\
    );
    var iter = SliceArgIterator.init(args);
    var result = clap.parseEx(clap.Help, &params, clap_parsers, &iter, .{
        .allocator = allocator,
    }) catch |err| return mapClapArgumentError(err);
    defer result.deinit();

    var options = TestCommandOptions{};
    if (result.positionals[1].len != 0) {
        return ArgumentError.UnknownArgument;
    }
    if (result.positionals[0]) |path| {
        options.target_path = path;
    }
    if (result.args.format) |format| {
        options.format = format;
    }
    return options;
}

pub fn parseBuildOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!BuildCommandOptions {
    const params = comptime clap.parseParamsComptime(
        \\--output <OUTPUT>
        \\--name <NAME>
        \\--force
        \\--format <FORMAT>
        \\<PATH>
        \\<EXTRA>...
        \\
    );
    var iter = SliceArgIterator.init(args);
    var result = clap.parseEx(clap.Help, &params, clap_parsers, &iter, .{
        .allocator = allocator,
    }) catch |err| return mapClapArgumentError(err);
    defer result.deinit();

    var options = BuildCommandOptions{};
    if (result.positionals[1].len != 0) {
        return ArgumentError.UnknownArgument;
    }
    if (result.positionals[0]) |path| {
        options.target_path = path;
    }
    if (result.args.output) |output| {
        options.output_root = output;
    }
    if (result.args.name) |name| {
        options.name = name;
    }
    options.force = result.args.force != 0;
    if (result.args.format) |format| {
        options.format = format;
    }
    return options;
}

fn mapClapArgumentError(err: anyerror) ArgumentError {
    return switch (err) {
        ArgumentError.InvalidDelta => ArgumentError.InvalidDelta,
        ArgumentError.InvalidFrames => ArgumentError.InvalidFrames,
        ArgumentError.InvalidRenderSize => ArgumentError.InvalidRenderSize,
        ArgumentError.InvalidPixelScale => ArgumentError.InvalidPixelScale,
        ArgumentError.InvalidFormat => ArgumentError.InvalidFormat,
        ArgumentError.MissingExpected => ArgumentError.MissingExpected,
        else => ArgumentError.UnknownArgument,
    };
}

fn parseFrameCount(value: []const u8) ArgumentError!u32 {
    const frames = std.fmt.parseInt(u32, value, 10) catch return ArgumentError.InvalidFrames;
    if (frames == 0) {
        return ArgumentError.InvalidFrames;
    }
    return frames;
}

fn parseRenderDimension(value: []const u8) ArgumentError!u32 {
    const pixels = std.fmt.parseInt(u32, value, 10) catch return ArgumentError.InvalidRenderSize;
    if (pixels == 0) {
        return ArgumentError.InvalidRenderSize;
    }
    return pixels;
}

pub fn parsePixelScale(value: []const u8) ArgumentError!f32 {
    const pixel_scale = std.fmt.parseFloat(f32, value) catch return ArgumentError.InvalidPixelScale;
    if (!std.math.isFinite(pixel_scale) or pixel_scale <= 0.0) {
        return ArgumentError.InvalidPixelScale;
    }
    return pixel_scale;
}

fn parseDeltaSeconds(value: []const u8) ArgumentError!f32 {
    const delta_seconds = std.fmt.parseFloat(f32, value) catch return ArgumentError.InvalidDelta;
    if (!std.math.isFinite(delta_seconds) or delta_seconds <= 0.0) {
        return ArgumentError.InvalidDelta;
    }
    return delta_seconds;
}

fn parseCheckOutputFormat(value: []const u8) ArgumentError!CheckOutputFormat {
    if (std.mem.eql(u8, value, "text")) {
        return .text;
    }
    if (std.mem.eql(u8, value, "json")) {
        return .json;
    }
    return ArgumentError.InvalidFormat;
}

test {
    _ = @import("options_tests.zig");
}
