const std = @import("std");
const scrapbot = @import("scrapbot");

const Io = std.Io;

pub const TestManifestError = error{
    InvalidTestManifest,
};

pub const ExpectedFieldValue = union(enum) {
    boolean: bool,
    int: i32,
    float: f32,
    vec3: [3]f32,
    string: []const u8,

    pub fn deinit(self: ExpectedFieldValue, allocator: std.mem.Allocator) void {
        switch (self) {
            .string => |value| allocator.free(value),
            else => {},
        }
    }

    pub fn matches(self: ExpectedFieldValue, actual: scrapbot.ComponentValue) bool {
        return switch (self) {
            .boolean => |expected| switch (actual) {
                .boolean => |found| found == expected,
                else => false,
            },
            .int => |expected| switch (actual) {
                .int => |found| found == expected,
                else => false,
            },
            .float => |expected| switch (actual) {
                .float => |found| approxEqual(expected, found),
                else => false,
            },
            .vec3 => |expected| switch (actual) {
                .vec3 => |found| approxVec3(expected, found),
                else => false,
            },
            .string => |expected| switch (actual) {
                .string => |found| std.mem.eql(u8, expected, found),
                else => false,
            },
        };
    }
};

pub const TestExpectation = struct {
    entity: []const u8,
    component: []const u8,
    field: []const u8,
    expected: ExpectedFieldValue,

    pub fn deinit(self: *TestExpectation, allocator: std.mem.Allocator) void {
        allocator.free(self.entity);
        allocator.free(self.component);
        allocator.free(self.field);
        self.expected.deinit(allocator);
    }
};

pub const TestManifest = struct {
    frames: u32 = 1,
    delta_seconds: f32 = 1.0 / 60.0,
    input_frames: []scrapbot.StepInputFrame = &.{},
    expectations: []TestExpectation = &.{},

    pub fn deinit(self: *TestManifest, allocator: std.mem.Allocator) void {
        allocator.free(self.input_frames);
        for (self.expectations) |*expectation| {
            expectation.deinit(allocator);
        }
        allocator.free(self.expectations);
        self.* = .{};
    }
};

pub const TestExpectationDraft = struct {
    entity: ?[]const u8 = null,
    component: ?[]const u8 = null,
    field: ?[]const u8 = null,
    expected: ?ExpectedFieldValue = null,

    pub fn deinit(self: *TestExpectationDraft, allocator: std.mem.Allocator) void {
        if (self.entity) |value| allocator.free(value);
        if (self.component) |value| allocator.free(value);
        if (self.field) |value| allocator.free(value);
        if (self.expected) |value| value.deinit(allocator);
        self.* = .{};
    }

    fn take(self: *TestExpectationDraft) TestManifestError!TestExpectation {
        const entity = self.entity orelse return TestManifestError.InvalidTestManifest;
        const component = self.component orelse return TestManifestError.InvalidTestManifest;
        const field = self.field orelse return TestManifestError.InvalidTestManifest;
        const expected = self.expected orelse return TestManifestError.InvalidTestManifest;
        self.entity = null;
        self.component = null;
        self.field = null;
        self.expected = null;
        return .{
            .entity = entity,
            .component = component,
            .field = field,
            .expected = expected,
        };
    }
};

const TestInputFrameDraft = struct {
    frame: ?u32 = null,
    input: scrapbot.FrameInput = .{},

    fn take(self: *TestInputFrameDraft) TestManifestError!scrapbot.StepInputFrame {
        const frame = self.frame orelse return TestManifestError.InvalidTestManifest;
        self.frame = null;
        return .{
            .frame = frame,
            .input = self.input,
        };
    }
};

pub const TestCaseStats = struct {
    assertions: u32 = 0,
    failed_assertions: u32 = 0,
    failed: bool = false,

    pub fn passed(self: TestCaseStats) bool {
        return !self.failed and self.failed_assertions == 0;
    }
};

pub const TestSuiteSummary = struct {
    cases: u32 = 0,
    passed_cases: u32 = 0,
    failed_cases: u32 = 0,
    assertions: u32 = 0,
    failed_assertions: u32 = 0,

    pub fn add(self: *TestSuiteSummary, stats: TestCaseStats) void {
        self.cases += 1;
        self.assertions += stats.assertions;
        self.failed_assertions += stats.failed_assertions;
        if (stats.passed()) {
            self.passed_cases += 1;
        } else {
            self.failed_cases += 1;
        }
    }
};

pub const ExpectationEvaluation = struct {
    passed: bool,
    actual: ?scrapbot.ComponentValue = null,
    err: ?anyerror = null,
};

pub fn collectTestProjects(
    io: Io,
    allocator: std.mem.Allocator,
    target_path: []const u8,
) ![]const []const u8 {
    const cwd = Io.Dir.cwd();
    const target_dir = try cwd.openDir(io, target_path, .{ .iterate = true });
    defer target_dir.close(io);

    var projects: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (projects.items) |project_path| {
            allocator.free(project_path);
        }
        projects.deinit(allocator);
    }

    if (isTestProject(io, target_dir)) {
        try projects.append(allocator, try allocator.dupe(u8, target_path));
        return try projects.toOwnedSlice(allocator);
    }

    var iterator = target_dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .directory) {
            continue;
        }

        const child_is_project = childIsTestProject(io, target_dir, entry.name);
        if (!child_is_project) {
            continue;
        }

        const project_path = try std.fs.path.join(allocator, &.{ target_path, entry.name });
        errdefer allocator.free(project_path);
        try projects.append(allocator, project_path);
    }

    std.mem.sort([]const u8, projects.items, {}, stringLessThan);
    return try projects.toOwnedSlice(allocator);
}

fn childIsTestProject(io: Io, parent_dir: Io.Dir, child_name: []const u8) bool {
    const child_dir = parent_dir.openDir(io, child_name, .{}) catch return false;
    defer child_dir.close(io);
    return isTestProject(io, child_dir);
}

fn isTestProject(io: Io, dir: Io.Dir) bool {
    const has_project_manifest = pathExists(io, dir, scrapbot.project_file_name) or pathExists(io, dir, scrapbot.legacy_project_file_name);
    return has_project_manifest and pathExists(io, dir, "test.scrapbot.toml");
}

fn pathExists(io: Io, dir: Io.Dir, path: []const u8) bool {
    dir.access(io, path, .{}) catch return false;
    return true;
}

fn stringLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

pub fn freeOwnedStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| {
        allocator.free(value);
    }
    allocator.free(values);
}

pub fn loadTestManifest(
    io: Io,
    allocator: std.mem.Allocator,
    project_path: []const u8,
) !TestManifest {
    const cwd = Io.Dir.cwd();
    const project_dir = try cwd.openDir(io, project_path, .{});
    defer project_dir.close(io);

    const contents = try project_dir.readFileAlloc(io, "test.scrapbot.toml", allocator, .limited(64 * 1024));
    defer allocator.free(contents);

    return parseTestManifest(allocator, contents);
}

pub fn parseTestManifest(allocator: std.mem.Allocator, contents: []const u8) !TestManifest {
    var manifest = TestManifest{};
    var input_frames: std.ArrayList(scrapbot.StepInputFrame) = .empty;
    var expectations: std.ArrayList(TestExpectation) = .empty;
    errdefer {
        input_frames.deinit(allocator);
        for (expectations.items) |*expectation| {
            expectation.deinit(allocator);
        }
        expectations.deinit(allocator);
    }

    var expectation_draft: ?TestExpectationDraft = null;
    errdefer if (expectation_draft) |*active| active.deinit(allocator);
    var input_draft: ?TestInputFrameDraft = null;

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }

        if (std.mem.eql(u8, trimmed, "[[expect.field]]") or std.mem.eql(u8, trimmed, "[[expect]]")) {
            try appendInputFrameDraft(allocator, &input_frames, &input_draft);
            try appendExpectationDraft(allocator, &expectations, &expectation_draft);
            expectation_draft = .{};
            continue;
        }

        if (std.mem.eql(u8, trimmed, "[[input.frame]]")) {
            try appendExpectationDraft(allocator, &expectations, &expectation_draft);
            try appendInputFrameDraft(allocator, &input_frames, &input_draft);
            input_draft = .{};
            continue;
        }

        if (trimmed[0] == '[') {
            return TestManifestError.InvalidTestManifest;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse return TestManifestError.InvalidTestManifest;
        const key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");

        if (expectation_draft) |*active| {
            try readExpectationProperty(allocator, active, key, value);
        } else if (input_draft) |*active| {
            try readInputFrameProperty(active, key, value);
        } else {
            try readTestManifestRootProperty(&manifest, key, value);
        }
    }

    try appendExpectationDraft(allocator, &expectations, &expectation_draft);
    try appendInputFrameDraft(allocator, &input_frames, &input_draft);
    if (expectations.items.len == 0) {
        return TestManifestError.InvalidTestManifest;
    }

    manifest.input_frames = try input_frames.toOwnedSlice(allocator);
    errdefer allocator.free(manifest.input_frames);
    manifest.expectations = try expectations.toOwnedSlice(allocator);
    return manifest;
}

fn appendExpectationDraft(
    allocator: std.mem.Allocator,
    expectations: *std.ArrayList(TestExpectation),
    draft: *?TestExpectationDraft,
) !void {
    if (draft.*) |*active| {
        const expectation = try active.take();
        errdefer {
            var owned = expectation;
            owned.deinit(allocator);
        }
        try expectations.append(allocator, expectation);
        active.deinit(allocator);
        draft.* = null;
    }
}

fn appendInputFrameDraft(
    allocator: std.mem.Allocator,
    input_frames: *std.ArrayList(scrapbot.StepInputFrame),
    draft: *?TestInputFrameDraft,
) !void {
    if (draft.*) |*active| {
        const input_frame = try active.take();
        for (input_frames.items) |existing| {
            if (existing.frame == input_frame.frame) {
                return TestManifestError.InvalidTestManifest;
            }
        }
        try input_frames.append(allocator, input_frame);
        draft.* = null;
    }
}

fn readTestManifestRootProperty(manifest: *TestManifest, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "frames")) {
        manifest.frames = parsePositiveFrameValue(value) catch return TestManifestError.InvalidTestManifest;
        return;
    }
    if (std.mem.eql(u8, key, "dt") or std.mem.eql(u8, key, "delta_seconds")) {
        manifest.delta_seconds = parsePositiveDeltaValue(value) catch return TestManifestError.InvalidTestManifest;
        return;
    }
    return TestManifestError.InvalidTestManifest;
}

fn readExpectationProperty(
    allocator: std.mem.Allocator,
    draft: *TestExpectationDraft,
    key: []const u8,
    value: []const u8,
) !void {
    if (std.mem.eql(u8, key, "entity")) {
        if (draft.entity != null) return TestManifestError.InvalidTestManifest;
        draft.entity = try parseTestString(allocator, value);
        return;
    }
    if (std.mem.eql(u8, key, "component")) {
        if (draft.component != null) return TestManifestError.InvalidTestManifest;
        draft.component = try parseTestString(allocator, value);
        return;
    }
    if (std.mem.eql(u8, key, "field")) {
        if (draft.field != null) return TestManifestError.InvalidTestManifest;
        draft.field = try parseTestString(allocator, value);
        return;
    }
    if (std.mem.eql(u8, key, "equals_bool")) {
        try setExpectedValue(allocator, draft, .{ .boolean = try parseTestBool(value) });
        return;
    }
    if (std.mem.eql(u8, key, "equals_int")) {
        try setExpectedValue(allocator, draft, .{ .int = std.fmt.parseInt(i32, value, 10) catch return TestManifestError.InvalidTestManifest });
        return;
    }
    if (std.mem.eql(u8, key, "equals_float")) {
        const expected = std.fmt.parseFloat(f32, value) catch return TestManifestError.InvalidTestManifest;
        if (!std.math.isFinite(expected)) return TestManifestError.InvalidTestManifest;
        try setExpectedValue(allocator, draft, .{ .float = expected });
        return;
    }
    if (std.mem.eql(u8, key, "equals_vec3")) {
        try setExpectedValue(allocator, draft, .{ .vec3 = try parseTestVec3(value) });
        return;
    }
    if (std.mem.eql(u8, key, "equals_string")) {
        try setExpectedValue(allocator, draft, .{ .string = try parseTestString(allocator, value) });
        return;
    }
    return TestManifestError.InvalidTestManifest;
}

fn readInputFrameProperty(
    draft: *TestInputFrameDraft,
    key: []const u8,
    value: []const u8,
) !void {
    if (std.mem.eql(u8, key, "frame")) {
        if (draft.frame != null) return TestManifestError.InvalidTestManifest;
        draft.frame = parsePositiveFrameValue(value) catch return TestManifestError.InvalidTestManifest;
        return;
    }
    if (std.mem.eql(u8, key, "ui_visible")) {
        draft.input.ui_visible = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "debug_overlay_visible") or std.mem.eql(u8, key, "editor_visible")) {
        draft.input.debug_overlay_visible = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "viewport")) {
        const parsed = try parseTestVec2(value);
        draft.input.viewport_width = parsed[0];
        draft.input.viewport_height = parsed[1];
        return;
    }
    if (std.mem.eql(u8, key, "pixel_scale")) {
        draft.input.pixel_scale = parsePixelScale(value) catch return TestManifestError.InvalidTestManifest;
        return;
    }
    if (std.mem.eql(u8, key, "pointer") or std.mem.eql(u8, key, "pointer_position")) {
        const parsed = try parseTestVec2(value);
        draft.input.pointer.position = parsed;
        draft.input.pointer.has_position = true;
        return;
    }
    if (std.mem.eql(u8, key, "pointer_delta") or std.mem.eql(u8, key, "delta")) {
        draft.input.pointer.delta = try parseTestVec2(value);
        return;
    }
    if (std.mem.eql(u8, key, "pointer_has_position")) {
        draft.input.pointer.has_position = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "wheel") or std.mem.eql(u8, key, "wheel_delta")) {
        draft.input.pointer.wheel_delta = try parseTestVec2(value);
        return;
    }
    if (std.mem.eql(u8, key, "primary_down")) {
        draft.input.pointer.primary_down = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "primary_pressed")) {
        draft.input.pointer.primary_pressed = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "primary_released")) {
        draft.input.pointer.primary_released = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "secondary_down")) {
        draft.input.pointer.secondary_down = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "secondary_pressed")) {
        draft.input.pointer.secondary_pressed = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "secondary_released")) {
        draft.input.pointer.secondary_released = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "ctrl_down")) {
        draft.input.keyboard.ctrl_down = try parseTestBool(value);
        draft.input.keyboard.move_down = draft.input.keyboard.ctrl_down;
        return;
    }
    if (std.mem.eql(u8, key, "move_forward")) {
        draft.input.keyboard.move_forward = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "move_back")) {
        draft.input.keyboard.move_back = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "move_left")) {
        draft.input.keyboard.move_left = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "move_right")) {
        draft.input.keyboard.move_right = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "move_up")) {
        draft.input.keyboard.move_up = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "move_down")) {
        draft.input.keyboard.move_down = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "editor_toggle_pressed")) {
        draft.input.keyboard.editor_toggle_pressed = try parseTestBool(value);
        return;
    }
    if (std.mem.eql(u8, key, "system_profile_count_hint")) {
        draft.input.system_profile_count_hint = std.fmt.parseInt(usize, value, 10) catch return TestManifestError.InvalidTestManifest;
        return;
    }
    return TestManifestError.InvalidTestManifest;
}

fn setExpectedValue(allocator: std.mem.Allocator, draft: *TestExpectationDraft, value: ExpectedFieldValue) !void {
    if (draft.expected != null) {
        value.deinit(allocator);
        return TestManifestError.InvalidTestManifest;
    }
    draft.expected = value;
}

fn parsePositiveFrameValue(value: []const u8) !u32 {
    const frames = std.fmt.parseInt(u32, value, 10) catch return TestManifestError.InvalidTestManifest;
    if (frames == 0) {
        return TestManifestError.InvalidTestManifest;
    }
    return frames;
}

fn parsePositiveDeltaValue(value: []const u8) !f32 {
    const delta_seconds = std.fmt.parseFloat(f32, value) catch return TestManifestError.InvalidTestManifest;
    if (!std.math.isFinite(delta_seconds) or delta_seconds <= 0.0) {
        return TestManifestError.InvalidTestManifest;
    }
    return delta_seconds;
}

fn parseTestString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') {
        return TestManifestError.InvalidTestManifest;
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var index: usize = 1;
    while (index < value.len - 1) : (index += 1) {
        const byte = value[index];
        if (byte != '\\') {
            try out.append(allocator, byte);
            continue;
        }

        index += 1;
        if (index >= value.len - 1) {
            return TestManifestError.InvalidTestManifest;
        }

        switch (value[index]) {
            '\\' => try out.append(allocator, '\\'),
            '"' => try out.append(allocator, '"'),
            'n' => try out.append(allocator, '\n'),
            'r' => try out.append(allocator, '\r'),
            't' => try out.append(allocator, '\t'),
            else => return TestManifestError.InvalidTestManifest,
        }
    }

    return try out.toOwnedSlice(allocator);
}

fn parseTestBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) {
        return true;
    }
    if (std.mem.eql(u8, value, "false")) {
        return false;
    }
    return TestManifestError.InvalidTestManifest;
}

fn parseTestVec2(value: []const u8) ![2]f32 {
    if (value.len < 5 or value[0] != '[' or value[value.len - 1] != ']') {
        return TestManifestError.InvalidTestManifest;
    }

    var result: [2]f32 = undefined;
    var count: usize = 0;
    var parts = std.mem.splitScalar(u8, value[1 .. value.len - 1], ',');
    while (parts.next()) |part| {
        if (count >= result.len) {
            return TestManifestError.InvalidTestManifest;
        }
        const trimmed = std.mem.trim(u8, part, " \t\r");
        if (trimmed.len == 0) {
            return TestManifestError.InvalidTestManifest;
        }
        const parsed = std.fmt.parseFloat(f32, trimmed) catch return TestManifestError.InvalidTestManifest;
        if (!std.math.isFinite(parsed)) {
            return TestManifestError.InvalidTestManifest;
        }
        result[count] = parsed;
        count += 1;
    }

    if (count != result.len) {
        return TestManifestError.InvalidTestManifest;
    }
    return result;
}

fn parseTestVec3(value: []const u8) ![3]f32 {
    if (value.len < 5 or value[0] != '[' or value[value.len - 1] != ']') {
        return TestManifestError.InvalidTestManifest;
    }

    var result: [3]f32 = undefined;
    var count: usize = 0;
    var parts = std.mem.splitScalar(u8, value[1 .. value.len - 1], ',');
    while (parts.next()) |part| {
        if (count >= result.len) {
            return TestManifestError.InvalidTestManifest;
        }
        const trimmed = std.mem.trim(u8, part, " \t\r");
        if (trimmed.len == 0) {
            return TestManifestError.InvalidTestManifest;
        }
        const parsed = std.fmt.parseFloat(f32, trimmed) catch return TestManifestError.InvalidTestManifest;
        if (!std.math.isFinite(parsed)) {
            return TestManifestError.InvalidTestManifest;
        }
        result[count] = parsed;
        count += 1;
    }

    if (count != result.len) {
        return TestManifestError.InvalidTestManifest;
    }
    return result;
}
fn approxEqual(expected: f32, actual: f32) bool {
    return @abs(expected - actual) <= 0.0001;
}

fn approxVec3(expected: [3]f32, actual: [3]f32) bool {
    return approxEqual(expected[0], actual[0]) and
        approxEqual(expected[1], actual[1]) and
        approxEqual(expected[2], actual[2]);
}

fn parsePixelScale(value: []const u8) TestManifestError!f32 {
    const pixel_scale = std.fmt.parseFloat(f32, value) catch return TestManifestError.InvalidTestManifest;
    if (!std.math.isFinite(pixel_scale) or pixel_scale <= 0.0) {
        return TestManifestError.InvalidTestManifest;
    }
    return pixel_scale;
}

test {
    _ = @import("test_manifest_tests.zig");
}
