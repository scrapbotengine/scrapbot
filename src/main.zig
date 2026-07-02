const std = @import("std");
const Io = std.Io;
const machina = @import("machina");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const exit_code = try run(init.io, allocator, args, stdout, stderr);

    try stdout.flush();
    try stderr.flush();

    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}

fn run(
    io: Io,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    if (args.len <= 1) {
        try printHelp(stdout);
        return 0;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "version")) {
        try stdout.print("machina {s}\n", .{machina.version});
        return 0;
    }

    if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "help")) {
        try printHelp(stdout);
        return 0;
    }

    if (std.mem.eql(u8, command, "init")) {
        const target_path = if (args.len >= 3) args[2] else ".";
        const name = projectNameFromPath(target_path);
        machina.initProject(io, allocator, target_path, name) catch |err| {
            try printProjectError(stderr, target_path, err);
            return 1;
        };
        try stdout.print("Initialized Machina project at {s}\n", .{target_path});
        return 0;
    }

    if (std.mem.eql(u8, command, "check")) {
        return try checkCommand(io, allocator, args[2..], stdout, stderr);
    }

    if (std.mem.eql(u8, command, "step")) {
        return try stepCommand(io, allocator, args[2..], stdout, stderr);
    }

    if (std.mem.eql(u8, command, "test")) {
        return try testCommand(io, allocator, args[2..], stdout, stderr);
    }

    if (std.mem.eql(u8, command, "run")) {
        const target_path = if (args.len >= 3) args[2] else ".";
        var window_options = parseWindowOptions(args[3..]) catch |err| {
            try printArgumentError(stderr, err);
            return 1;
        };
        const result = try checkProjectForCommand(io, allocator, target_path, stderr) orelse return 1;
        defer machina.freeCheckResult(allocator, result);
        var live_project = machina.LiveProject.init(io, std.heap.smp_allocator, target_path) catch |err| {
            try printProjectError(stderr, target_path, err);
            return 1;
        };
        defer live_project.deinit();

        var reload_context = SceneReloadContext{
            .live_project = &live_project,
            .stderr = stderr,
            .target_path = target_path,
        };
        window_options.scene_reload = .{
            .context = &reload_context,
            .poll = pollSceneReload,
        };
        window_options.frame_update = .{
            .context = &reload_context,
            .step = stepLiveProject,
        };

        try stdout.print("Loaded project {s}\n", .{result.project.name});
        try stdout.print("Selected scene: {s}\n", .{result.project.default_scene});
        try stdout.print("Scene entities: {d}\n", .{live_project.scene.entityCount()});
        try stdout.print("Scripts: {d}, update batches: {d}\n", .{
            live_project.project.scripts.len,
            live_project.scripts.schedule.batchCount(),
        });

        machina.runDemoWindow(allocator, result.project.name, window_options, live_project.renderScene()) catch |err| {
            try stderr.print("run failed: {s}\n", .{@errorName(err)});
            return 1;
        };
        return 0;
    }

    if (std.mem.eql(u8, command, "render")) {
        const target_path = if (args.len >= 3) args[2] else ".";
        const output_path = if (args.len >= 4) args[3] else "zig-out/machina-cube.bmp";
        const result = try checkProjectForCommand(io, allocator, target_path, stderr) orelse return 1;
        defer machina.freeCheckResult(allocator, result);
        const scene = machina.loadDefaultScene(io, allocator, result.project) catch |err| {
            try printProjectError(stderr, target_path, err);
            return 1;
        };
        defer machina.freeScene(allocator, scene);

        machina.renderDemoBmp(io, allocator, output_path, scene.renderScene()) catch |err| {
            try stderr.print("render failed: {s}\n", .{@errorName(err)});
            return 1;
        };

        try stdout.print("Rendered cube: {s}\n", .{output_path});
        return 0;
    }

    if (std.mem.eql(u8, command, "render-test")) {
        const target_path = if (args.len >= 3) args[2] else ".";
        const output_path = if (args.len >= 4) args[3] else "zig-out/machina-render-test.bmp";
        const result = try checkProjectForCommand(io, allocator, target_path, stderr) orelse return 1;
        defer machina.freeCheckResult(allocator, result);
        const scene = machina.loadDefaultScene(io, allocator, result.project) catch |err| {
            try printProjectError(stderr, target_path, err);
            return 1;
        };
        defer machina.freeScene(allocator, scene);

        machina.renderDemoBmp(io, allocator, output_path, scene.renderScene()) catch |err| {
            try stderr.print("render-test render failed: {s}\n", .{@errorName(err)});
            return 1;
        };

        const verification = machina.verifyRenderBmp(io, allocator, output_path, .{
            .min_visible_components = 1,
            .min_color_groups = expectedColorGroups(scene),
        }) catch |err| {
            try stderr.print("render-test verification failed: {s}\n", .{@errorName(err)});
            return 1;
        };

        try stdout.print(
            "Render test OK: {d}x{d}, foreground pixels: {d}, visible components: {d}, color groups: {d}\n",
            .{
                verification.width,
                verification.height,
                verification.foreground_pixels,
                verification.visible_components,
                verification.color_groups,
            },
        );
        try stdout.print("Rendered artifact: {s}\n", .{output_path});
        return 0;
    }

    try stderr.print("Unknown command: {s}\n\n", .{command});
    try printHelp(stderr);
    return 1;
}

const CheckOutputFormat = enum {
    text,
    json,
};

const CheckOptions = struct {
    target_path: []const u8 = ".",
    format: CheckOutputFormat = .text,
};

const StepCommandOptions = struct {
    target_path: []const u8 = ".",
    frames: u32 = 1,
    delta_seconds: f32 = 1.0 / 60.0,
    format: CheckOutputFormat = .text,
};

const TestCommandOptions = struct {
    target_path: []const u8 = "tests/projects",
    format: CheckOutputFormat = .text,
};

fn checkCommand(
    io: Io,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    const options = parseCheckOptions(args) catch |err| {
        try printArgumentError(stderr, err);
        return 1;
    };

    var result = machina.checkProjectDetailed(io, allocator, options.target_path) catch |err| {
        switch (options.format) {
            .text => try printProjectError(stderr, options.target_path, err),
            .json => try printProjectErrorJson(stdout, options.target_path, err),
        }
        return 1;
    };

    switch (result) {
        .ok => |ok| {
            defer machina.freeCheckResult(allocator, ok);
            switch (options.format) {
                .text => {
                    try stdout.print("Project OK: {s}\n", .{ok.project.name});
                    try stdout.print("Default scene: {s}\n", .{ok.project.default_scene});
                    try stdout.print("Scripts: {d}\n", .{ok.project.scripts.len});
                    try stdout.print("Update batches: {d}, systems: {d}\n", .{
                        ok.schedule.batchCount(),
                        ok.schedule.systemCount(),
                    });
                },
                .json => try printCheckOkJson(stdout, ok),
            }
            return 0;
        },
        .invalid => |*diagnostic| {
            defer diagnostic.deinit(allocator);
            switch (options.format) {
                .text => try printScriptDiagnostic(stderr, options.target_path, diagnostic.*),
                .json => try printScriptDiagnosticJson(stdout, options.target_path, diagnostic.*),
            }
            return 1;
        },
    }
}

fn stepCommand(
    io: Io,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    const options = parseStepOptions(args) catch |err| {
        try printArgumentError(stderr, err);
        return 1;
    };

    const result = machina.stepProjectDetailed(io, allocator, options.target_path, .{
        .frames = options.frames,
        .delta_seconds = options.delta_seconds,
    }) catch |err| {
        switch (options.format) {
            .text => try printProjectError(stderr, options.target_path, err),
            .json => try printProjectErrorJson(stdout, options.target_path, err),
        }
        return 1;
    };
    defer machina.freeStepDetailedResult(allocator, result);

    switch (result) {
        .ok => |ok| {
            switch (options.format) {
                .text => try printStepOkText(stdout, ok),
                .json => try printStepOkJson(stdout, ok),
            }
            return 0;
        },
        .runtime_error => |failure| {
            switch (options.format) {
                .text => {
                    try printStepFailureText(stderr, options.target_path, failure);
                    try printScriptDiagnostic(stderr, options.target_path, failure.diagnostic);
                },
                .json => try printStepFailureJson(stdout, options.target_path, failure),
            }
            return 1;
        },
        .invalid => |diagnostic| {
            switch (options.format) {
                .text => try printScriptDiagnostic(stderr, options.target_path, diagnostic),
                .json => try printScriptDiagnosticJson(stdout, options.target_path, diagnostic),
            }
            return 1;
        },
    }
}

fn testCommand(
    io: Io,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    const options = parseTestOptions(args) catch |err| {
        try printArgumentError(stderr, err);
        return 1;
    };

    const project_paths = collectTestProjects(io, allocator, options.target_path) catch |err| {
        switch (options.format) {
            .text => try stderr.print("{s}: test discovery failed: {s}\n", .{ options.target_path, @errorName(err) }),
            .json => {
                try stdout.writeAll("{\"ok\":false,\"error\":");
                try writeJsonString(stdout, @errorName(err));
                try stdout.writeAll(",\"root\":");
                try writeJsonString(stdout, options.target_path);
                try stdout.writeAll("}\n");
            },
        }
        return 1;
    };
    defer freeOwnedStringList(allocator, project_paths);

    if (project_paths.len == 0) {
        switch (options.format) {
            .text => try stderr.print("{s}: no Machina test projects found\n", .{options.target_path}),
            .json => {
                try stdout.writeAll("{\"ok\":false,\"error\":\"NoTestProjects\",\"root\":");
                try writeJsonString(stdout, options.target_path);
                try stdout.writeAll("}\n");
            },
        }
        return 1;
    }

    var summary = TestSuiteSummary{};
    if (options.format == .json) {
        try stdout.writeAll("{\"tests\":[");
    }

    for (project_paths, 0..) |project_path, index| {
        if (options.format == .json and index != 0) {
            try stdout.writeByte(',');
        }

        const stats = try runTestCase(io, allocator, project_path, options.format, stdout, stderr);
        summary.add(stats);
    }

    switch (options.format) {
        .text => try printTestSummaryText(stdout, summary),
        .json => {
            try stdout.writeAll("],\"summary\":");
            try printTestSummaryJson(stdout, summary);
            try stdout.writeAll(",\"ok\":");
            try stdout.writeAll(if (summary.failed_cases == 0) "true" else "false");
            try stdout.writeAll("}\n");
        },
    }

    return if (summary.failed_cases == 0) 0 else 1;
}

fn checkProjectForCommand(
    io: Io,
    allocator: std.mem.Allocator,
    target_path: []const u8,
    stderr: *Io.Writer,
) !?machina.CheckResult {
    var result = machina.checkProjectDetailed(io, allocator, target_path) catch |err| {
        try printProjectError(stderr, target_path, err);
        return null;
    };
    switch (result) {
        .ok => |ok| return ok,
        .invalid => |*diagnostic| {
            defer diagnostic.deinit(allocator);
            try printScriptDiagnostic(stderr, target_path, diagnostic.*);
            return null;
        },
    }
}

fn printHelp(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\machina - agent-native game engine
        \\
        \\Usage:
        \\  machina --version
        \\  machina help
        \\  machina init [path]
        \\  machina check [path] [--format text|json]
        \\  machina step [path] [--frames N] [--dt seconds] [--format text|json]
        \\  machina test [tests-path|project-path] [--format text|json]
        \\  machina run [path] [--frames N]
        \\  machina render [path] [output.bmp]
        \\  machina render-test [path] [output.bmp]
        \\
    );
}

const ArgumentError = error{
    InvalidDelta,
    InvalidFrames,
    InvalidFormat,
    UnknownArgument,
};

const SceneReloadContext = struct {
    live_project: *machina.LiveProject,
    stderr: *Io.Writer,
    target_path: []const u8,
};

fn pollSceneReload(raw_context: *anyopaque) ?machina.RenderScene {
    const context: *SceneReloadContext = @ptrCast(@alignCast(raw_context));
    const result = context.live_project.pollLoadedSources() catch |err| {
        printProjectError(context.stderr, context.target_path, err) catch {};
        if (context.live_project.lastDiagnostic()) |diagnostic| {
            printScriptDiagnostic(context.stderr, context.target_path, diagnostic.*) catch {};
        }
        context.stderr.flush() catch {};
        return null;
    };

    switch (result) {
        .unchanged => return null,
        .reloaded => |info| {
            context.stderr.print(
                "Reloaded {s}{s}{s}: {s}, {d} entities, {d} renderable cubes, {d} scripts, {d} update batches\n",
                .{
                    if (info.project_reloaded) "project" else "",
                    if (info.scene_reloaded) if (info.project_reloaded) " and scene" else "scene" else "",
                    if (info.scripts_reloaded) if (info.project_reloaded or info.scene_reloaded) " and scripts" else "scripts" else "",
                    info.scene_path,
                    info.entity_count,
                    info.renderable_cube_count,
                    info.script_count,
                    info.system_batch_count,
                },
            ) catch {};
            context.stderr.flush() catch {};
            return context.live_project.renderScene();
        },
    }
}

fn stepLiveProject(raw_context: *anyopaque, delta_seconds: f32) void {
    const context: *SceneReloadContext = @ptrCast(@alignCast(raw_context));
    context.live_project.update(delta_seconds);
    if (context.live_project.lastDiagnostic()) |diagnostic| {
        printScriptDiagnostic(context.stderr, context.target_path, diagnostic.*) catch {};
        context.stderr.flush() catch {};
    }
}

fn parseWindowOptions(args: []const []const u8) ArgumentError!machina.WindowOptions {
    var options = machina.WindowOptions{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--frames")) {
            index += 1;
            if (index >= args.len) {
                return ArgumentError.InvalidFrames;
            }
            options.max_frames = std.fmt.parseInt(u32, args[index], 10) catch return ArgumentError.InvalidFrames;
            if (options.max_frames.? == 0) {
                return ArgumentError.InvalidFrames;
            }
            continue;
        }

        return ArgumentError.UnknownArgument;
    }

    return options;
}

fn parseCheckOptions(args: []const []const u8) ArgumentError!CheckOptions {
    var options = CheckOptions{};
    var saw_path = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= args.len) {
                return ArgumentError.InvalidFormat;
            }
            options.format = try parseCheckOutputFormat(args[index]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--format=")) {
            options.format = try parseCheckOutputFormat(arg["--format=".len..]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            return ArgumentError.UnknownArgument;
        }
        if (saw_path) {
            return ArgumentError.UnknownArgument;
        }
        options.target_path = arg;
        saw_path = true;
    }
    return options;
}

fn parseStepOptions(args: []const []const u8) ArgumentError!StepCommandOptions {
    var options = StepCommandOptions{};
    var saw_path = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--frames")) {
            index += 1;
            if (index >= args.len) {
                return ArgumentError.InvalidFrames;
            }
            options.frames = try parseFrameCount(args[index]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--frames=")) {
            options.frames = try parseFrameCount(arg["--frames=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--dt")) {
            index += 1;
            if (index >= args.len) {
                return ArgumentError.InvalidDelta;
            }
            options.delta_seconds = try parseDeltaSeconds(args[index]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--dt=")) {
            options.delta_seconds = try parseDeltaSeconds(arg["--dt=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= args.len) {
                return ArgumentError.InvalidFormat;
            }
            options.format = try parseCheckOutputFormat(args[index]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--format=")) {
            options.format = try parseCheckOutputFormat(arg["--format=".len..]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            return ArgumentError.UnknownArgument;
        }
        if (saw_path) {
            return ArgumentError.UnknownArgument;
        }
        options.target_path = arg;
        saw_path = true;
    }
    return options;
}

fn parseTestOptions(args: []const []const u8) ArgumentError!TestCommandOptions {
    var options = TestCommandOptions{};
    var saw_path = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= args.len) {
                return ArgumentError.InvalidFormat;
            }
            options.format = try parseCheckOutputFormat(args[index]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--format=")) {
            options.format = try parseCheckOutputFormat(arg["--format=".len..]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            return ArgumentError.UnknownArgument;
        }
        if (saw_path) {
            return ArgumentError.UnknownArgument;
        }
        options.target_path = arg;
        saw_path = true;
    }
    return options;
}

const TestManifestError = error{
    InvalidTestManifest,
};

const ExpectedFieldValue = union(enum) {
    boolean: bool,
    int: i32,
    float: f32,
    vec3: [3]f32,
    string: []const u8,

    fn deinit(self: ExpectedFieldValue, allocator: std.mem.Allocator) void {
        switch (self) {
            .string => |value| allocator.free(value),
            else => {},
        }
    }

    fn matches(self: ExpectedFieldValue, actual: machina.ComponentValue) bool {
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

const TestExpectation = struct {
    entity: []const u8,
    component: []const u8,
    field: []const u8,
    expected: ExpectedFieldValue,

    fn deinit(self: *TestExpectation, allocator: std.mem.Allocator) void {
        allocator.free(self.entity);
        allocator.free(self.component);
        allocator.free(self.field);
        self.expected.deinit(allocator);
    }
};

const TestManifest = struct {
    frames: u32 = 1,
    delta_seconds: f32 = 1.0 / 60.0,
    expectations: []TestExpectation = &.{},

    fn deinit(self: *TestManifest, allocator: std.mem.Allocator) void {
        for (self.expectations) |*expectation| {
            expectation.deinit(allocator);
        }
        allocator.free(self.expectations);
        self.* = .{};
    }
};

const TestExpectationDraft = struct {
    entity: ?[]const u8 = null,
    component: ?[]const u8 = null,
    field: ?[]const u8 = null,
    expected: ?ExpectedFieldValue = null,

    fn deinit(self: *TestExpectationDraft, allocator: std.mem.Allocator) void {
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

const TestCaseStats = struct {
    assertions: u32 = 0,
    failed_assertions: u32 = 0,
    failed: bool = false,

    fn passed(self: TestCaseStats) bool {
        return !self.failed and self.failed_assertions == 0;
    }
};

const TestSuiteSummary = struct {
    cases: u32 = 0,
    passed_cases: u32 = 0,
    failed_cases: u32 = 0,
    assertions: u32 = 0,
    failed_assertions: u32 = 0,

    fn add(self: *TestSuiteSummary, stats: TestCaseStats) void {
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

const ExpectationEvaluation = struct {
    passed: bool,
    actual: ?machina.ComponentValue = null,
    err: ?anyerror = null,
};

fn collectTestProjects(
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
    return pathExists(io, dir, machina.project_file_name) and pathExists(io, dir, "test.machina.toml");
}

fn pathExists(io: Io, dir: Io.Dir, path: []const u8) bool {
    dir.access(io, path, .{}) catch return false;
    return true;
}

fn stringLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn freeOwnedStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| {
        allocator.free(value);
    }
    allocator.free(values);
}

fn loadTestManifest(
    io: Io,
    allocator: std.mem.Allocator,
    project_path: []const u8,
) !TestManifest {
    const cwd = Io.Dir.cwd();
    const project_dir = try cwd.openDir(io, project_path, .{});
    defer project_dir.close(io);

    const contents = try project_dir.readFileAlloc(io, "test.machina.toml", allocator, .limited(64 * 1024));
    defer allocator.free(contents);

    return parseTestManifest(allocator, contents);
}

fn parseTestManifest(allocator: std.mem.Allocator, contents: []const u8) !TestManifest {
    var manifest = TestManifest{};
    var expectations: std.ArrayList(TestExpectation) = .empty;
    errdefer {
        for (expectations.items) |*expectation| {
            expectation.deinit(allocator);
        }
        expectations.deinit(allocator);
    }

    var draft: ?TestExpectationDraft = null;
    errdefer if (draft) |*active| active.deinit(allocator);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }

        if (std.mem.eql(u8, trimmed, "[[expect.field]]") or std.mem.eql(u8, trimmed, "[[expect]]")) {
            try appendExpectationDraft(allocator, &expectations, &draft);
            draft = .{};
            continue;
        }

        if (trimmed[0] == '[') {
            return TestManifestError.InvalidTestManifest;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse return TestManifestError.InvalidTestManifest;
        const key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");

        if (draft) |*active| {
            try readExpectationProperty(allocator, active, key, value);
        } else {
            try readTestManifestRootProperty(&manifest, key, value);
        }
    }

    try appendExpectationDraft(allocator, &expectations, &draft);
    if (expectations.items.len == 0) {
        return TestManifestError.InvalidTestManifest;
    }

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

fn runTestCase(
    io: Io,
    allocator: std.mem.Allocator,
    project_path: []const u8,
    format: CheckOutputFormat,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !TestCaseStats {
    const name = std.fs.path.basename(trimTrailingSlashes(project_path));

    var manifest = loadTestManifest(io, allocator, project_path) catch |err| {
        const stats = TestCaseStats{ .failed = true };
        switch (format) {
            .text => try stdout.print("FAIL {s}: test.machina.toml {s}\n", .{ name, @errorName(err) }),
            .json => try printTestCaseLoadFailureJson(stdout, name, project_path, "manifest", err),
        }
        return stats;
    };
    defer manifest.deinit(allocator);

    var stats = TestCaseStats{ .assertions = @intCast(manifest.expectations.len) };
    const result = machina.stepProjectDetailed(io, allocator, project_path, .{
        .frames = manifest.frames,
        .delta_seconds = manifest.delta_seconds,
    }) catch |err| {
        stats.failed = true;
        switch (format) {
            .text => try stdout.print("FAIL {s}: project load {s}\n", .{ name, @errorName(err) }),
            .json => try printTestCaseLoadFailureJson(stdout, name, project_path, "project", err),
        }
        return stats;
    };
    defer machina.freeStepDetailedResult(allocator, result);

    switch (result) {
        .ok => |ok| {
            try evaluateTestCaseOk(name, project_path, ok, manifest, format, stdout, &stats);
        },
        .runtime_error => |failure| {
            stats.failed = true;
            switch (format) {
                .text => {
                    try stdout.print("FAIL {s}: runtime error after {d}/{d} frames\n", .{
                        name,
                        failure.summary.completed_frames,
                        failure.summary.frames,
                    });
                    try printScriptDiagnostic(stderr, project_path, failure.diagnostic);
                },
                .json => try printTestCaseRuntimeFailureJson(stdout, name, project_path, failure),
            }
        },
        .invalid => |diagnostic| {
            stats.failed = true;
            switch (format) {
                .text => {
                    try stdout.print("FAIL {s}: invalid scripts\n", .{name});
                    try printScriptDiagnostic(stderr, project_path, diagnostic);
                },
                .json => try printTestCaseDiagnosticFailureJson(stdout, name, project_path, diagnostic),
            }
        },
    }

    return stats;
}

fn evaluateTestCaseOk(
    name: []const u8,
    project_path: []const u8,
    ok: machina.StepOk,
    manifest: TestManifest,
    format: CheckOutputFormat,
    stdout: *Io.Writer,
    stats: *TestCaseStats,
) !void {
    switch (format) {
        .text => {
            var printed_failure_header = false;
            for (manifest.expectations) |expectation| {
                const evaluation = evaluateExpectation(ok.scene.world, expectation);
                if (evaluation.passed) {
                    continue;
                }

                stats.failed_assertions += 1;
                if (!printed_failure_header) {
                    try stdout.print("FAIL {s}\n", .{name});
                    printed_failure_header = true;
                }
                try printExpectationFailureText(stdout, expectation, evaluation);
            }

            if (stats.failed_assertions == 0) {
                try stdout.print("PASS {s} ({d} assertions)\n", .{ name, stats.assertions });
            }
        },
        .json => {
            try printTestCaseOkJson(stdout, name, project_path, ok, manifest, stats);
        },
    }
}

fn evaluateExpectation(world: machina.World, expectation: TestExpectation) ExpectationEvaluation {
    const entity = world.findEntityById(expectation.entity) orelse return .{
        .passed = false,
        .err = error.UnknownEntity,
    };
    const actual = world.getComponentFieldValue(entity, expectation.component, expectation.field) catch |err| return .{
        .passed = false,
        .err = err,
    };
    return .{
        .passed = expectation.expected.matches(actual),
        .actual = actual,
    };
}

fn approxEqual(expected: f32, actual: f32) bool {
    return @abs(expected - actual) <= 0.0001;
}

fn approxVec3(expected: [3]f32, actual: [3]f32) bool {
    return approxEqual(expected[0], actual[0]) and
        approxEqual(expected[1], actual[1]) and
        approxEqual(expected[2], actual[2]);
}

fn parseFrameCount(value: []const u8) ArgumentError!u32 {
    const frames = std.fmt.parseInt(u32, value, 10) catch return ArgumentError.InvalidFrames;
    if (frames == 0) {
        return ArgumentError.InvalidFrames;
    }
    return frames;
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

fn printArgumentError(writer: *Io.Writer, err: ArgumentError) !void {
    const message = switch (err) {
        ArgumentError.InvalidDelta => "--dt expects a positive finite number",
        ArgumentError.InvalidFrames => "--frames expects a positive integer",
        ArgumentError.InvalidFormat => "--format expects text or json",
        ArgumentError.UnknownArgument => "unknown argument",
    };
    try writer.print("{s}\n", .{message});
}

fn expectedColorGroups(scene: machina.Scene) usize {
    var has_warm = false;
    var has_cool = false;
    var meshes = scene.world.renderableMeshes();
    while (meshes.next()) |mesh| {
        if (mesh.base_color[0] > mesh.base_color[2] + 0.1) {
            has_warm = true;
        }
        if (mesh.base_color[2] > mesh.base_color[0] + 0.1) {
            has_cool = true;
        }
    }
    var ui_rects = scene.world.uiRects();
    while (ui_rects.next()) |rect| {
        if (rect.color[0] > rect.color[2] + 0.1) {
            has_warm = true;
        }
        if (rect.color[2] > rect.color[0] + 0.1) {
            has_cool = true;
        }
    }
    var ui_texts = scene.world.uiTexts();
    while (ui_texts.next()) |text| {
        if (text.color[0] > text.color[2] + 0.1) {
            has_warm = true;
        }
        if (text.color[2] > text.color[0] + 0.1) {
            has_cool = true;
        }
    }
    const groups = @as(usize, @intFromBool(has_warm)) + @as(usize, @intFromBool(has_cool));
    return @max(groups, 1);
}

fn printProjectError(writer: *Io.Writer, root_path: []const u8, err: anyerror) !void {
    try writer.print("{s}: {s}\n", .{ root_path, projectErrorMessage(err) });
}

fn projectErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        machina.ProjectError.AlreadyExists => "project already exists",
        machina.ProjectError.InvalidProject => "not a valid Machina project",
        machina.ProjectError.MissingProjectFile => "missing project.machina.toml",
        machina.ProjectError.MissingDefaultScene => "missing default scene",
        machina.ProjectError.UnsupportedProjectVersion => "unsupported project version",
        machina.ProjectError.InvalidProjectName => "invalid project name",
        machina.ProjectError.InvalidDefaultScene => "invalid default scene",
        machina.ProjectError.InvalidSceneEntity => "invalid scene entity",
        machina.ProjectError.DuplicateSceneEntityId => "duplicate scene entity id",
        machina.ProjectError.InvalidSceneNumber => "invalid scene number",
        machina.ProjectError.MissingSceneContent => "missing scene content",
        machina.ProjectError.MissingScript => "missing script",
        machina.ProjectError.InvalidScript => "invalid script",
        else => "unexpected project error",
    };
}

fn printScriptDiagnostic(writer: *Io.Writer, root_path: []const u8, diagnostic: machina.ScriptDiagnostic) !void {
    try writer.print("{s}: {s}", .{ root_path, diagnostic.stage.label() });
    if (diagnostic.path) |path| {
        try writer.print(" in {s}", .{path});
    }
    if (diagnostic.system_id) |system_id| {
        try writer.print(" system {s}", .{system_id});
    }
    if (diagnostic.start) |start| {
        try writer.print(":{d}", .{start.line});
        if (start.column) |column| {
            try writer.print(":{d}", .{column});
        }
    }
    try writer.print(": {s}\n", .{diagnostic.message});
}

fn printStepOkText(writer: *Io.Writer, ok: machina.StepOk) !void {
    try writer.print("Step OK: {s}\n", .{ok.project.name});
    try writer.print("Scene: {s}\n", .{ok.scene.name});
    try writer.print("Frames: {d}/{d}, dt: {d}\n", .{
        ok.summary.completed_frames,
        ok.summary.frames,
        ok.summary.delta_seconds,
    });
    try writer.print("Entities: {d}, components: {d}, renderable cubes: {d}\n", .{
        ok.scene.entityCount(),
        ok.scene.componentInstanceCount(),
        ok.scene.renderableCubeCount(),
    });
    try writer.print("Update batches: {d}, systems: {d}\n", .{
        ok.schedule.batchCount(),
        ok.schedule.systemCount(),
    });
}

fn printStepFailureText(writer: *Io.Writer, root_path: []const u8, failure: machina.StepRuntimeError) !void {
    try writer.print("{s}: step failed after {d}/{d} frames, dt: {d}\n", .{
        root_path,
        failure.summary.completed_frames,
        failure.summary.frames,
        failure.summary.delta_seconds,
    });
}

fn printExpectationFailureText(
    writer: *Io.Writer,
    expectation: TestExpectation,
    evaluation: ExpectationEvaluation,
) !void {
    try writer.print("  - {s}.{s}.{s}: expected ", .{
        expectation.entity,
        expectation.component,
        expectation.field,
    });
    try printExpectedFieldValueText(writer, expectation.expected);
    if (evaluation.actual) |actual| {
        try writer.writeAll(", got ");
        try printComponentValueText(writer, actual);
    } else if (evaluation.err) |err| {
        try writer.print(", got {s}", .{@errorName(err)});
    }
    try writer.writeByte('\n');
}

fn printExpectedFieldValueText(writer: *Io.Writer, value: ExpectedFieldValue) !void {
    switch (value) {
        .boolean => |payload| try writer.writeAll(if (payload) "true" else "false"),
        .int => |payload| try writer.print("{d}", .{payload}),
        .float => |payload| try writer.print("{d}", .{payload}),
        .vec3 => |payload| try writer.print("[{d}, {d}, {d}]", .{ payload[0], payload[1], payload[2] }),
        .string => |payload| try writer.print("\"{s}\"", .{payload}),
    }
}

fn printComponentValueText(writer: *Io.Writer, value: machina.ComponentValue) !void {
    switch (value) {
        .boolean => |payload| try writer.writeAll(if (payload) "true" else "false"),
        .int => |payload| try writer.print("{d}", .{payload}),
        .float => |payload| try writer.print("{d}", .{payload}),
        .vec3 => |payload| try writer.print("[{d}, {d}, {d}]", .{ payload[0], payload[1], payload[2] }),
        .string => |payload| try writer.print("\"{s}\"", .{payload}),
    }
}

fn printTestSummaryText(writer: *Io.Writer, summary: TestSuiteSummary) !void {
    try writer.print("Test projects: {d} passed, {d} failed, {d} assertions", .{
        summary.passed_cases,
        summary.failed_cases,
        summary.assertions,
    });
    if (summary.failed_assertions != 0) {
        try writer.print(", {d} failed", .{summary.failed_assertions});
    }
    try writer.writeByte('\n');
}

fn printTestSummaryJson(writer: *Io.Writer, summary: TestSuiteSummary) !void {
    try writer.print(
        "{{\"cases\":{d},\"passed\":{d},\"failed\":{d},\"assertions\":{d},\"failed_assertions\":{d}}}",
        .{
            summary.cases,
            summary.passed_cases,
            summary.failed_cases,
            summary.assertions,
            summary.failed_assertions,
        },
    );
}

fn printTestCaseLoadFailureJson(
    writer: *Io.Writer,
    name: []const u8,
    project_path: []const u8,
    stage: []const u8,
    err: anyerror,
) !void {
    try writer.writeAll("{\"name\":");
    try writeJsonString(writer, name);
    try writer.writeAll(",\"path\":");
    try writeJsonString(writer, project_path);
    try writer.writeAll(",\"ok\":false,\"stage\":");
    try writeJsonString(writer, stage);
    try writer.writeAll(",\"error\":");
    try writeJsonString(writer, @errorName(err));
    try writer.writeAll("}");
}

fn printTestCaseDiagnosticFailureJson(
    writer: *Io.Writer,
    name: []const u8,
    project_path: []const u8,
    diagnostic: machina.ScriptDiagnostic,
) !void {
    try writer.writeAll("{\"name\":");
    try writeJsonString(writer, name);
    try writer.writeAll(",\"path\":");
    try writeJsonString(writer, project_path);
    try writer.writeAll(",\"ok\":false,\"diagnostic\":");
    try printScriptDiagnosticObjectJson(writer, project_path, diagnostic);
    try writer.writeAll("}");
}

fn printTestCaseRuntimeFailureJson(
    writer: *Io.Writer,
    name: []const u8,
    project_path: []const u8,
    failure: machina.StepRuntimeError,
) !void {
    try writer.writeAll("{\"name\":");
    try writeJsonString(writer, name);
    try writer.writeAll(",\"path\":");
    try writeJsonString(writer, project_path);
    try writer.writeAll(",\"ok\":false,\"simulation\":");
    try printStepSummaryJson(writer, failure.summary);
    try writer.writeAll(",\"diagnostic\":");
    try printScriptDiagnosticObjectJson(writer, project_path, failure.diagnostic);
    try writer.writeAll("}");
}

fn printTestCaseOkJson(
    writer: *Io.Writer,
    name: []const u8,
    project_path: []const u8,
    ok: machina.StepOk,
    manifest: TestManifest,
    stats: *TestCaseStats,
) !void {
    try writer.writeAll("{\"name\":");
    try writeJsonString(writer, name);
    try writer.writeAll(",\"path\":");
    try writeJsonString(writer, project_path);
    try writer.writeAll(",\"simulation\":");
    try printStepSummaryJson(writer, ok.summary);
    try writer.writeAll(",\"assertions\":[");
    for (manifest.expectations, 0..) |expectation, index| {
        if (index != 0) {
            try writer.writeByte(',');
        }

        const evaluation = evaluateExpectation(ok.scene.world, expectation);
        if (!evaluation.passed) {
            stats.failed_assertions += 1;
        }
        try printTestExpectationJson(writer, expectation, evaluation);
    }
    try writer.writeAll("],\"failed_assertions\":");
    try writer.print("{d}", .{stats.failed_assertions});
    try writer.writeAll(",\"ok\":");
    try writer.writeAll(if (stats.failed_assertions == 0) "true" else "false");
    try writer.writeAll("}");
}

fn printTestExpectationJson(
    writer: *Io.Writer,
    expectation: TestExpectation,
    evaluation: ExpectationEvaluation,
) !void {
    try writer.writeAll("{\"entity\":");
    try writeJsonString(writer, expectation.entity);
    try writer.writeAll(",\"component\":");
    try writeJsonString(writer, expectation.component);
    try writer.writeAll(",\"field\":");
    try writeJsonString(writer, expectation.field);
    try writer.writeAll(",\"expected\":");
    try printExpectedFieldValueJson(writer, expectation.expected);
    try writer.writeAll(",\"ok\":");
    try writer.writeAll(if (evaluation.passed) "true" else "false");
    if (evaluation.actual) |actual| {
        try writer.writeAll(",\"actual\":");
        try printComponentValueJson(writer, actual);
    } else if (evaluation.err) |err| {
        try writer.writeAll(",\"error\":");
        try writeJsonString(writer, @errorName(err));
    }
    try writer.writeAll("}");
}

fn printExpectedFieldValueJson(writer: *Io.Writer, value: ExpectedFieldValue) !void {
    switch (value) {
        .boolean => |payload| try writer.writeAll(if (payload) "true" else "false"),
        .int => |payload| try writer.print("{d}", .{payload}),
        .float => |payload| try writer.print("{d}", .{payload}),
        .vec3 => |payload| try writer.print("[{d},{d},{d}]", .{ payload[0], payload[1], payload[2] }),
        .string => |payload| try writeJsonString(writer, payload),
    }
}

fn printComponentValueJson(writer: *Io.Writer, value: machina.ComponentValue) !void {
    switch (value) {
        .boolean => |payload| try writer.writeAll(if (payload) "true" else "false"),
        .int => |payload| try writer.print("{d}", .{payload}),
        .float => |payload| try writer.print("{d}", .{payload}),
        .vec3 => |payload| try writer.print("[{d},{d},{d}]", .{ payload[0], payload[1], payload[2] }),
        .string => |payload| try writeJsonString(writer, payload),
    }
}

fn printCheckOkJson(writer: *Io.Writer, result: machina.CheckResult) !void {
    try writer.writeAll("{\"ok\":true,\"project\":");
    try printProjectSummaryJson(writer, result.project);
    try writer.writeAll(",\"schedule\":");
    try printCheckScheduleJson(writer, result.schedule);
    try writer.writeAll("}\n");
}

fn printStepOkJson(writer: *Io.Writer, ok: machina.StepOk) !void {
    try writer.writeAll("{\"ok\":true,\"project\":");
    try printProjectSummaryJson(writer, ok.project);
    try writer.writeAll(",\"scene\":");
    try printSceneSummaryJson(writer, ok.scene);
    try writer.writeAll(",\"simulation\":");
    try printStepSummaryJson(writer, ok.summary);
    try writer.writeAll(",\"schedule\":");
    try printCheckScheduleJson(writer, ok.schedule);
    try writer.writeAll("}\n");
}

fn printStepFailureJson(writer: *Io.Writer, root_path: []const u8, failure: machina.StepRuntimeError) !void {
    try writer.writeAll("{\"ok\":false,\"project\":");
    try printProjectSummaryJson(writer, failure.project);
    try writer.writeAll(",\"scene\":");
    try printSceneSummaryJson(writer, failure.scene);
    try writer.writeAll(",\"simulation\":");
    try printStepSummaryJson(writer, failure.summary);
    try writer.writeAll(",\"schedule\":");
    try printCheckScheduleJson(writer, failure.schedule);
    try writer.writeAll(",\"diagnostic\":");
    try printScriptDiagnosticObjectJson(writer, root_path, failure.diagnostic);
    try writer.writeAll("}\n");
}

fn printProjectSummaryJson(writer: *Io.Writer, project: machina.Project) !void {
    try writer.writeAll("{\"name\":");
    try writeJsonString(writer, project.name);
    try writer.writeAll(",\"default_scene\":");
    try writeJsonString(writer, project.default_scene);
    try writer.print(",\"scripts\":{d}", .{project.scripts.len});
    try writer.writeAll("}");
}

fn printSceneSummaryJson(writer: *Io.Writer, scene: machina.Scene) !void {
    try writer.writeAll("{\"name\":");
    try writeJsonString(writer, scene.name);
    try writer.print(",\"entities\":{d},\"component_instances\":{d},\"renderable_cubes\":{d}}}", .{
        scene.entityCount(),
        scene.componentInstanceCount(),
        scene.renderableCubeCount(),
    });
}

fn printStepSummaryJson(writer: *Io.Writer, summary: machina.StepSummary) !void {
    try writer.print("{{\"frames\":{d},\"completed_frames\":{d},\"dt\":{d}}}", .{
        summary.frames,
        summary.completed_frames,
        summary.delta_seconds,
    });
}

fn printCheckScheduleJson(writer: *Io.Writer, schedule: machina.CheckSchedule) !void {
    try writer.writeAll("{\"batches\":[");
    for (schedule.batches, 0..) |batch, batch_index| {
        if (batch_index != 0) {
            try writer.writeByte(',');
        }
        try writer.writeAll("{\"phase\":");
        try writeJsonString(writer, @tagName(batch.phase));
        try writer.writeAll(",\"systems\":[");
        for (batch.systems, 0..) |system, system_index| {
            if (system_index != 0) {
                try writer.writeByte(',');
            }
            try printCheckSystemJson(writer, system);
        }
        try writer.writeAll("]}");
    }
    try writer.writeAll("]}");
}

fn printCheckSystemJson(writer: *Io.Writer, system: machina.CheckSystemSummary) !void {
    try writer.writeAll("{\"id\":");
    try writeJsonString(writer, system.id);
    try writer.writeAll(",\"phase\":");
    try writeJsonString(writer, @tagName(system.phase));
    try writer.writeAll(",\"runner\":");
    try writeJsonString(writer, @tagName(system.runner));
    try writer.writeAll(",\"reads\":");
    try writeJsonStringList(writer, system.reads);
    try writer.writeAll(",\"writes\":");
    try writeJsonStringList(writer, system.writes);
    try writer.writeAll(",\"before\":");
    try writeJsonStringList(writer, system.before);
    try writer.writeAll(",\"after\":");
    try writeJsonStringList(writer, system.after);
    try writer.writeAll("}");
}

fn writeJsonStringList(writer: *Io.Writer, values: []const []const u8) !void {
    try writer.writeByte('[');
    for (values, 0..) |value, index| {
        if (index != 0) {
            try writer.writeByte(',');
        }
        try writeJsonString(writer, value);
    }
    try writer.writeByte(']');
}

fn printProjectErrorJson(writer: *Io.Writer, root_path: []const u8, err: anyerror) !void {
    try writer.writeAll("{\"ok\":false,\"error\":");
    try writeJsonString(writer, @errorName(err));
    try writer.writeAll(",\"root\":");
    try writeJsonString(writer, root_path);
    try writer.writeAll(",\"message\":");
    try writeJsonString(writer, projectErrorMessage(err));
    try writer.writeAll("}\n");
}

fn printScriptDiagnosticJson(writer: *Io.Writer, root_path: []const u8, diagnostic: machina.ScriptDiagnostic) !void {
    try writer.writeAll("{\"ok\":false,\"diagnostic\":");
    try printScriptDiagnosticObjectJson(writer, root_path, diagnostic);
    try writer.writeAll("}\n");
}

fn printScriptDiagnosticObjectJson(writer: *Io.Writer, root_path: []const u8, diagnostic: machina.ScriptDiagnostic) !void {
    try writer.writeAll("{");
    try writer.writeAll("\"stage\":");
    try writeJsonString(writer, @tagName(diagnostic.stage));
    try writer.writeAll(",\"root\":");
    try writeJsonString(writer, root_path);
    if (diagnostic.path) |path| {
        try writer.writeAll(",\"path\":");
        try writeJsonString(writer, path);
    }
    if (diagnostic.system_id) |system_id| {
        try writer.writeAll(",\"system_id\":");
        try writeJsonString(writer, system_id);
    }
    if (diagnostic.start) |start| {
        try writer.writeAll(",\"start\":");
        try printDiagnosticPositionJson(writer, start);
    }
    if (diagnostic.end) |end| {
        try writer.writeAll(",\"end\":");
        try printDiagnosticPositionJson(writer, end);
    }
    try writer.writeAll(",\"message\":");
    try writeJsonString(writer, diagnostic.message);
    try writer.writeAll("}");
}

fn printDiagnosticPositionJson(writer: *Io.Writer, position: machina.ScriptDiagnosticPosition) !void {
    try writer.print("{{\"line\":{d}", .{position.line});
    if (position.column) |column| {
        try writer.print(",\"column\":{d}", .{column});
    }
    try writer.writeAll("}");
}

fn writeJsonString(writer: *Io.Writer, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (byte < 0x20) {
                    try writer.print("\\u{x:0>4}", .{byte});
                } else {
                    try writer.writeByte(byte);
                }
            },
        }
    }
    try writer.writeByte('"');
}

fn projectNameFromPath(path: []const u8) []const u8 {
    const trimmed = trimTrailingSlashes(path);
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, ".")) {
        return "Machina Project";
    }
    return std.fs.path.basename(trimmed);
}

fn trimTrailingSlashes(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and path[end - 1] == '/') {
        end -= 1;
    }
    return path[0..end];
}

test "projectNameFromPath uses final path segment" {
    try std.testing.expectEqualStrings("demo", projectNameFromPath("games/demo"));
    try std.testing.expectEqualStrings("demo", projectNameFromPath("games/demo/"));
    try std.testing.expectEqualStrings("Machina Project", projectNameFromPath("."));
}

test "parseCheckOptions accepts path and json format" {
    const args = [_][]const u8{ "examples/minimal", "--format=json" };
    const options = try parseCheckOptions(&args);
    try std.testing.expectEqualStrings("examples/minimal", options.target_path);
    try std.testing.expectEqual(CheckOutputFormat.json, options.format);
}

test "parseCheckOptions accepts format before path" {
    const args = [_][]const u8{ "--format", "json", "examples/minimal" };
    const options = try parseCheckOptions(&args);
    try std.testing.expectEqualStrings("examples/minimal", options.target_path);
    try std.testing.expectEqual(CheckOutputFormat.json, options.format);
}

test "parseCheckOptions rejects unknown format" {
    const args = [_][]const u8{"--format=yaml"};
    try std.testing.expectError(ArgumentError.InvalidFormat, parseCheckOptions(&args));
}

test "parseStepOptions accepts path frames dt and json format" {
    const args = [_][]const u8{ "examples/minimal", "--frames=60", "--dt", "0.016", "--format=json" };
    const options = try parseStepOptions(&args);
    try std.testing.expectEqualStrings("examples/minimal", options.target_path);
    try std.testing.expectEqual(@as(u32, 60), options.frames);
    try std.testing.expectApproxEqAbs(@as(f32, 0.016), options.delta_seconds, 0.000001);
    try std.testing.expectEqual(CheckOutputFormat.json, options.format);
}

test "parseStepOptions rejects invalid dt" {
    const args = [_][]const u8{ "--dt", "inf" };
    try std.testing.expectError(ArgumentError.InvalidDelta, parseStepOptions(&args));
}

test "parseTestOptions defaults to tests/projects" {
    const options = try parseTestOptions(&.{});
    try std.testing.expectEqualStrings("tests/projects", options.target_path);
    try std.testing.expectEqual(CheckOutputFormat.text, options.format);
}

test "parseTestOptions accepts path and json format" {
    const args = [_][]const u8{ "tests/projects/health_tick", "--format=json" };
    const options = try parseTestOptions(&args);
    try std.testing.expectEqualStrings("tests/projects/health_tick", options.target_path);
    try std.testing.expectEqual(CheckOutputFormat.json, options.format);
}

test "parseTestManifest reads field assertions" {
    var manifest = try parseTestManifest(std.testing.allocator,
        \\frames = 4
        \\dt = 1.0
        \\
        \\[[expect.field]]
        \\entity = "door-1"
        \\component = "door"
        \\field = "openness"
        \\equals_float = 1.0
        \\
        \\[[expect.field]]
        \\entity = "switch-1"
        \\component = "switch"
        \\field = "active"
        \\equals_bool = true
        \\
    );
    defer manifest.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 4), manifest.frames);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), manifest.delta_seconds, 0.000001);
    try std.testing.expectEqual(@as(usize, 2), manifest.expectations.len);
    try std.testing.expectEqualStrings("door-1", manifest.expectations[0].entity);
    try std.testing.expectEqualStrings("door", manifest.expectations[0].component);
    try std.testing.expectEqualStrings("openness", manifest.expectations[0].field);
    try std.testing.expect(manifest.expectations[0].expected.matches(.{ .float = 1.0 }));
    try std.testing.expect(manifest.expectations[1].expected.matches(.{ .boolean = true }));
}

test "testCommand runs gameplay project suite" {
    var stdout_buffer: [8192]u8 = undefined;
    var stdout = Io.Writer.fixed(&stdout_buffer);
    var stderr_buffer: [2048]u8 = undefined;
    var stderr = Io.Writer.fixed(&stderr_buffer);
    const io = Io.Threaded.global_single_threaded.io();

    const args = [_][]const u8{"tests/projects"};
    const exit_code = try testCommand(io, std.testing.allocator, &args, &stdout, &stderr);

    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout.buffered(), "PASS auto_door") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout.buffered(), "PASS batching_animation") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout.buffered(), "PASS health_tick") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout.buffered(), "PASS projectile_lifetime") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout.buffered(), "PASS render_camera_light") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout.buffered(), "Test projects: 5 passed, 0 failed") != null);
    try std.testing.expectEqualStrings("", stderr.buffered());
}

test "printCheckOkJson includes schedule summary" {
    var buffer: [1024]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);

    const scripts = [_][]const u8{"scripts/gameplay.luau"};
    const reads = [_][]const u8{"spin"};
    const writes = [_][]const u8{"machina.transform"};
    const system = machina.CheckSystemSummary{
        .id = "autorotate",
        .phase = .update,
        .runner = .luau,
        .reads = &reads,
        .writes = &writes,
    };
    const systems = [_]machina.CheckSystemSummary{system};
    const batch = machina.CheckScheduleBatch{
        .phase = .update,
        .systems = &systems,
    };
    const batches = [_]machina.CheckScheduleBatch{batch};
    const result = machina.CheckResult{
        .project = .{
            .root_path = "examples/minimal",
            .name = "Minimal",
            .default_scene = "scenes/main.scene.toml",
            .scripts = &scripts,
        },
        .schedule = .{ .batches = &batches },
    };

    try printCheckOkJson(&writer, result);

    try std.testing.expectEqualStrings(
        "{\"ok\":true,\"project\":{\"name\":\"Minimal\",\"default_scene\":\"scenes/main.scene.toml\",\"scripts\":1},\"schedule\":{\"batches\":[{\"phase\":\"update\",\"systems\":[{\"id\":\"autorotate\",\"phase\":\"update\",\"runner\":\"luau\",\"reads\":[\"spin\"],\"writes\":[\"machina.transform\"],\"before\":[],\"after\":[]}]}]}}\n",
        writer.buffered(),
    );
}

test "printStepOkJson includes simulation and scene summary" {
    var output_buffer: [1536]u8 = undefined;
    var writer = Io.Writer.fixed(&output_buffer);

    var scene = machina.Scene{
        .name = "Main",
        .world = machina.World.init(std.testing.allocator),
    };
    defer scene.world.deinit();
    const entity = try scene.world.createEntity("entity-1", "Entity");
    try scene.world.setTransform(entity, .{});
    try scene.world.setSpin(entity, .{ .angular_velocity = .{ 1.0, 0.0, 0.0 } });

    const scripts = [_][]const u8{"scripts/gameplay.luau"};
    const reads = [_][]const u8{"spin"};
    const writes = [_][]const u8{"machina.transform"};
    const system = machina.CheckSystemSummary{
        .id = "autorotate",
        .phase = .update,
        .runner = .luau,
        .reads = &reads,
        .writes = &writes,
    };
    const systems = [_]machina.CheckSystemSummary{system};
    const batch = machina.CheckScheduleBatch{
        .phase = .update,
        .systems = &systems,
    };
    const batches = [_]machina.CheckScheduleBatch{batch};
    const ok = machina.StepOk{
        .project = .{
            .root_path = "examples/minimal",
            .name = "Minimal",
            .default_scene = "scenes/main.scene.toml",
            .scripts = &scripts,
        },
        .scene = scene,
        .schedule = .{ .batches = &batches },
        .summary = .{
            .frames = 2,
            .completed_frames = 2,
            .delta_seconds = 0.5,
        },
    };

    try printStepOkJson(&writer, ok);

    try std.testing.expectEqualStrings(
        "{\"ok\":true,\"project\":{\"name\":\"Minimal\",\"default_scene\":\"scenes/main.scene.toml\",\"scripts\":1},\"scene\":{\"name\":\"Main\",\"entities\":1,\"component_instances\":2,\"renderable_cubes\":0},\"simulation\":{\"frames\":2,\"completed_frames\":2,\"dt\":0.5},\"schedule\":{\"batches\":[{\"phase\":\"update\",\"systems\":[{\"id\":\"autorotate\",\"phase\":\"update\",\"runner\":\"luau\",\"reads\":[\"spin\"],\"writes\":[\"machina.transform\"],\"before\":[],\"after\":[]}]}]}}\n",
        writer.buffered(),
    );
}
