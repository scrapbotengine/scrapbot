const std = @import("std");
const clap = @import("clap");
const Io = std.Io;
const machina = @import("machina");

pub fn main(init: std.process.Init) !void {
    const arena_allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena_allocator);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const exit_code = if (leakCheckEnabled(init))
        try runLeakChecked(init.io, args, stdout, stderr)
    else
        try run(init.io, arena_allocator, args, stdout, stderr);

    try stdout.flush();
    try stderr.flush();

    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}

fn leakCheckEnabled(init: std.process.Init) bool {
    const value = init.environ_map.get("MACHINA_LEAK_CHECK") orelse return false;
    return std.mem.eql(u8, value, "1");
}

fn runLeakChecked(
    io: Io,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    var debug_allocator: std.heap.DebugAllocator(.{
        .safety = true,
        .stack_trace_frames = if (std.debug.sys_can_stack_trace) 8 else 0,
    }) = .init;
    const allocator = debug_allocator.allocator();
    const exit_code = try run(io, allocator, args, stdout, stderr);
    switch (debug_allocator.deinit()) {
        .ok => return exit_code,
        .leak => {
            try stderr.writeAll("memory leak detected by MACHINA_LEAK_CHECK\n");
            return 1;
        },
    }
}

fn run(
    io: Io,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    const top_level = parseTopLevel(allocator, args[1..]) catch |err| {
        try printArgumentError(stderr, err);
        return 1;
    };

    if (top_level.version) {
        try stdout.print("machina {s}\n", .{machina.version});
        return 0;
    }

    if (top_level.help or top_level.command == null) {
        try printHelp(stdout);
        return 0;
    }

    const command = top_level.command.?;
    if (std.mem.eql(u8, command, "version")) {
        try stdout.print("machina {s}\n", .{machina.version});
        return 0;
    }

    if (std.mem.eql(u8, command, "help")) {
        try printHelp(stdout);
        return 0;
    }

    if (std.mem.eql(u8, command, "init")) {
        const options = parseInitOptions(allocator, args[2..]) catch |err| {
            try printArgumentError(stderr, err);
            return 1;
        };
        const name = projectNameFromPath(options.target_path);
        machina.initProject(io, allocator, options.target_path, name) catch |err| {
            try printProjectError(stderr, options.target_path, err);
            return 1;
        };
        try stdout.print("Initialized Machina project at {s}\n", .{options.target_path});
        return 0;
    }

    if (std.mem.eql(u8, command, "check")) {
        return try checkCommand(io, allocator, args[2..], stdout, stderr);
    }

    if (std.mem.eql(u8, command, "step")) {
        return try stepCommand(io, allocator, args[2..], stdout, stderr);
    }

    if (std.mem.eql(u8, command, "bench")) {
        return try benchCommand(io, allocator, args[2..], stdout, stderr);
    }

    if (std.mem.eql(u8, command, "test")) {
        return try testCommand(io, allocator, args[2..], stdout, stderr);
    }

    if (std.mem.eql(u8, command, "build")) {
        return try buildCommand(io, allocator, args[2..], stdout, stderr);
    }

    if (std.mem.eql(u8, command, "run")) {
        const options = parseRunOptions(allocator, args[2..]) catch |err| {
            try printArgumentError(stderr, err);
            return 1;
        };
        const target_path = options.target_path;
        var window_options = options.window_options;
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
        try stdout.print("Scripts: {d}, schedule batches: {d}\n", .{
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
        const options = parseRenderOptions(allocator, args[2..], "zig-out/machina-cube.bmp") catch |err| {
            try printArgumentError(stderr, err);
            return 1;
        };
        const result = try checkProjectForCommand(io, allocator, options.target_path, stderr) orelse return 1;
        defer machina.freeCheckResult(allocator, result);
        var live_project = machina.LiveProject.init(io, allocator, options.target_path) catch |err| {
            try printProjectError(stderr, options.target_path, err);
            return 1;
        };
        defer live_project.deinit();
        if (!live_project.runStartup()) {
            if (live_project.lastDiagnostic()) |diagnostic| {
                try printScriptDiagnostic(stderr, options.target_path, diagnostic.*);
            }
            return 1;
        }

        if (options.selected_entity_id) |entity_id| {
            if (live_project.scene.world.findEntityById(entity_id) == null) {
                try stderr.print("render selected entity not found: {s}\n", .{entity_id});
                return 1;
            }
        }

        var frame_context = RenderFrameContext{
            .live_project = &live_project,
            .stderr = stderr,
            .target_path = options.target_path,
            .selected_entity_id = options.selected_entity_id,
        };
        machina.renderDemoBmpFrames(io, allocator, options.output_path, live_project.renderScene(), .{
            .frames = options.frames,
            .frame_input = renderCommandFrameInput(&live_project, options),
            .frame_update = if (options.frames > 1) .{
                .context = &frame_context,
                .step = stepRenderLiveProject,
            } else null,
        }) catch |err| {
            try stderr.print("render failed: {s}\n", .{@errorName(err)});
            return 1;
        };
        if (frame_context.failed) {
            return 1;
        }

        try stdout.print("Rendered artifact: {s}\n", .{options.output_path});
        return 0;
    }

    if (std.mem.eql(u8, command, "render-test")) {
        const options = parseRenderOptions(allocator, args[2..], "zig-out/machina-render-test.bmp") catch |err| {
            try printArgumentError(stderr, err);
            return 1;
        };
        const result = try checkProjectForCommand(io, allocator, options.target_path, stderr) orelse return 1;
        defer machina.freeCheckResult(allocator, result);
        var live_project = machina.LiveProject.init(io, allocator, options.target_path) catch |err| {
            try printProjectError(stderr, options.target_path, err);
            return 1;
        };
        defer live_project.deinit();
        if (!live_project.runStartup()) {
            if (live_project.lastDiagnostic()) |diagnostic| {
                try printScriptDiagnostic(stderr, options.target_path, diagnostic.*);
            }
            return 1;
        }
        const scene = live_project.scene;

        if (options.selected_entity_id) |entity_id| {
            if (live_project.scene.world.findEntityById(entity_id) == null) {
                try stderr.print("render-test selected entity not found: {s}\n", .{entity_id});
                return 1;
            }
        }

        var frame_context = RenderFrameContext{
            .live_project = &live_project,
            .stderr = stderr,
            .target_path = options.target_path,
            .selected_entity_id = options.selected_entity_id,
        };
        machina.renderDemoBmpFrames(io, allocator, options.output_path, live_project.renderScene(), .{
            .frames = options.frames,
            .frame_input = renderCommandFrameInput(&live_project, options),
            .frame_update = if (options.frames > 1) .{
                .context = &frame_context,
                .step = stepRenderLiveProject,
            } else null,
        }) catch |err| {
            try stderr.print("render-test render failed: {s}\n", .{@errorName(err)});
            return 1;
        };
        if (frame_context.failed) {
            return 1;
        }

        const verification = machina.verifyRenderBmp(io, allocator, options.output_path, .{
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
        try stdout.print("Rendered artifact: {s}\n", .{options.output_path});
        return 0;
    }

    if (std.mem.eql(u8, command, "visual-test")) {
        const options = parseVisualTestOptions(allocator, args[2..]) catch |err| {
            try printArgumentError(stderr, err);
            return 1;
        };
        const result = try checkProjectForCommand(io, allocator, options.render.target_path, stderr) orelse return 1;
        defer machina.freeCheckResult(allocator, result);
        var live_project = machina.LiveProject.init(io, allocator, options.render.target_path) catch |err| {
            try printProjectError(stderr, options.render.target_path, err);
            return 1;
        };
        defer live_project.deinit();
        if (!live_project.runStartup()) {
            if (live_project.lastDiagnostic()) |diagnostic| {
                try printScriptDiagnostic(stderr, options.render.target_path, diagnostic.*);
            }
            return 1;
        }

        if (options.render.selected_entity_id) |entity_id| {
            if (live_project.scene.world.findEntityById(entity_id) == null) {
                try stderr.print("visual-test selected entity not found: {s}\n", .{entity_id});
                return 1;
            }
        }

        if (!options.update and try sameResolvedPath(allocator, options.expected_path, options.render.output_path)) {
            try stderr.print("visual-test actual output must differ from expected path; use --update to refresh {s}\n", .{options.expected_path});
            return 1;
        }

        const render_output = if (options.update) options.expected_path else options.render.output_path;
        var frame_context = RenderFrameContext{
            .live_project = &live_project,
            .stderr = stderr,
            .target_path = options.render.target_path,
            .selected_entity_id = options.render.selected_entity_id,
        };
        machina.renderDemoImageFrames(io, allocator, render_output, live_project.renderScene(), .{
            .frames = options.render.frames,
            .frame_input = renderCommandFrameInput(&live_project, options.render),
            .frame_update = if (options.render.frames > 1) .{
                .context = &frame_context,
                .step = stepRenderLiveProject,
            } else null,
        }) catch |err| {
            try stderr.print("visual-test render failed: {s}\n", .{@errorName(err)});
            return 1;
        };
        if (frame_context.failed) {
            return 1;
        }

        if (options.update) {
            try stdout.print("Updated golden fixture: {s}\n", .{options.expected_path});
            return 0;
        }

        const comparison_options = machina.RenderComparisonOptions{};
        const comparison = machina.compareRenderImage(io, allocator, options.expected_path, options.render.output_path, comparison_options) catch |err| {
            try stderr.print("visual-test comparison failed: {s}\n", .{@errorName(err)});
            return 1;
        };
        const ok = comparison.passed(comparison_options);
        const changed_percent = comparison.changed_pixel_ratio * 100.0;
        try stdout.print(
            "Visual test {s}: {d}x{d}, max delta: {d}, mean delta: {d:.3}, changed pixels: {d}/{d} ({d:.3}%)\n",
            .{
                if (ok) "OK" else "FAILED",
                comparison.width,
                comparison.height,
                comparison.max_channel_delta,
                comparison.mean_channel_delta,
                comparison.changed_pixels,
                comparison.pixels,
                changed_percent,
            },
        );
        try stdout.print("Expected: {s}\n", .{options.expected_path});
        try stdout.print("Actual: {s}\n", .{options.render.output_path});
        if (!ok) {
            try stderr.print(
                "visual-test exceeded tolerances: max delta <= {d}, mean delta <= {d:.3}, changed pixels <= {d:.3}%\n",
                .{
                    comparison_options.max_channel_delta,
                    comparison_options.max_mean_channel_delta,
                    comparison_options.max_changed_pixel_ratio * 100.0,
                },
            );
            return 1;
        }
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

const TopLevel = struct {
    version: bool = false,
    help: bool = false,
    command: ?[]const u8 = null,
};

const InitCommandOptions = struct {
    target_path: []const u8 = ".",
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

const BenchCommandOptions = struct {
    target_path: []const u8 = ".",
    frames: u32 = 240,
    delta_seconds: f32 = 1.0 / 60.0,
    format: CheckOutputFormat = .text,
};

const BenchResult = struct {
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

    fn nsPerFrame(self: BenchResult) u64 {
        return if (self.frames == 0) 0 else self.update_ns / @as(u64, self.frames);
    }
};

const TestCommandOptions = struct {
    target_path: []const u8 = "tests/projects",
    format: CheckOutputFormat = .text,
};

const BuildCommandOptions = struct {
    target_path: []const u8 = ".",
    output_root: ?[]const u8 = null,
    name: ?[]const u8 = null,
    force: bool = false,
    format: CheckOutputFormat = .text,
};

const RenderCommandOptions = struct {
    target_path: []const u8 = ".",
    output_path: []const u8,
    frames: u32 = 1,
    editor: bool = false,
    selected_entity_id: ?[]const u8 = null,
};

const VisualTestCommandOptions = struct {
    render: RenderCommandOptions,
    expected_path: []const u8,
    update: bool = false,
};

const RunCommandOptions = struct {
    target_path: []const u8 = ".",
    window_options: machina.WindowOptions = .{},
};

fn checkCommand(
    io: Io,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    const options = parseCheckOptions(allocator, args) catch |err| {
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
                    if (ok.project.native) |native_path| {
                        try stdout.print("Native: {s}\n", .{native_path});
                    }
                    if (ok.project.native_artifact) |native_artifact_path| {
                        try stdout.print("Native artifact: {s}\n", .{native_artifact_path});
                    }
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
    const options = parseStepOptions(allocator, args) catch |err| {
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

fn benchCommand(
    io: Io,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    const options = parseBenchOptions(allocator, args) catch |err| {
        try printArgumentError(stderr, err);
        return 1;
    };

    var live_project = machina.LiveProject.init(io, allocator, options.target_path) catch |err| {
        switch (options.format) {
            .text => try printProjectError(stderr, options.target_path, err),
            .json => try printProjectErrorJson(stdout, options.target_path, err),
        }
        return 1;
    };
    defer live_project.deinit();

    const startup_start = Io.Clock.awake.now(io).nanoseconds;
    if (!live_project.runStartup()) {
        if (live_project.lastDiagnostic()) |diagnostic| {
            switch (options.format) {
                .text => try printScriptDiagnostic(stderr, options.target_path, diagnostic.*),
                .json => try printScriptDiagnosticJson(stdout, options.target_path, diagnostic.*),
            }
        }
        return 1;
    }
    const startup_ns: u64 = @intCast(Io.Clock.awake.now(io).nanoseconds - startup_start);

    const update_start = Io.Clock.awake.now(io).nanoseconds;
    var completed_frames: u32 = 0;
    while (completed_frames < options.frames) : (completed_frames += 1) {
        live_project.update(options.delta_seconds);
        if (live_project.lastDiagnostic()) |diagnostic| {
            switch (options.format) {
                .text => try printScriptDiagnostic(stderr, options.target_path, diagnostic.*),
                .json => try printScriptDiagnosticJson(stdout, options.target_path, diagnostic.*),
            }
            return 1;
        }
    }
    const update_ns: u64 = @intCast(Io.Clock.awake.now(io).nanoseconds - update_start);

    const render_stats = machina.renderStats(allocator, live_project.renderScene()) catch |err| {
        switch (options.format) {
            .text => try stderr.print("bench render stats failed: {s}\n", .{@errorName(err)}),
            .json => try printProjectErrorJson(stdout, options.target_path, err),
        }
        return 1;
    };

    const result = BenchResult{
        .project_name = live_project.project.name,
        .scene_name = live_project.scene.name,
        .frames = options.frames,
        .delta_seconds = options.delta_seconds,
        .startup_ns = startup_ns,
        .update_ns = update_ns,
        .entity_count = live_project.scene.entityCount(),
        .component_instance_count = live_project.scene.componentInstanceCount(),
        .renderable_count = render_stats.renderables,
        .render_batch_count = render_stats.render_batches,
        .ui_rect_count = render_stats.ui_rects,
        .ui_text_count = render_stats.ui_texts,
    };

    switch (options.format) {
        .text => try printBenchOkText(stdout, result),
        .json => try printBenchOkJson(stdout, result),
    }
    return 0;
}

fn testCommand(
    io: Io,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    const options = parseTestOptions(allocator, args) catch |err| {
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

fn buildCommand(
    io: Io,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    const options = parseBuildOptions(allocator, args) catch |err| {
        try printArgumentError(stderr, err);
        return 1;
    };

    var check_result = machina.checkProjectDetailed(io, allocator, options.target_path) catch |err| {
        switch (options.format) {
            .text => try printProjectError(stderr, options.target_path, err),
            .json => try printProjectErrorJson(stdout, options.target_path, err),
        }
        return 1;
    };
    switch (check_result) {
        .ok => |ok| machina.freeCheckResult(allocator, ok),
        .invalid => |*diagnostic| {
            defer diagnostic.deinit(allocator);
            switch (options.format) {
                .text => try printScriptDiagnostic(stderr, options.target_path, diagnostic.*),
                .json => try printScriptDiagnosticJson(stdout, options.target_path, diagnostic.*),
            }
            return 1;
        },
    }

    var build_result = machina.buildProjectDetailed(io, allocator, options.target_path, .{
        .output_root = options.output_root,
        .name = options.name,
        .force = options.force,
    }) catch |err| {
        switch (options.format) {
            .text => try printProjectError(stderr, options.target_path, err),
            .json => try printProjectErrorJson(stdout, options.target_path, err),
        }
        return 1;
    };
    const result = switch (build_result) {
        .ok => |ok| ok,
        .invalid => |*diagnostic| {
            defer diagnostic.deinit(allocator);
            switch (options.format) {
                .text => try printScriptDiagnostic(stderr, options.target_path, diagnostic.*),
                .json => try printScriptDiagnosticJson(stdout, options.target_path, diagnostic.*),
            }
            return 1;
        },
    };
    defer result.deinit(allocator);

    switch (options.format) {
        .text => try printBuildOkText(stdout, result),
        .json => try printBuildOkJson(stdout, result),
    }
    return 0;
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

fn sameResolvedPath(allocator: std.mem.Allocator, left: []const u8, right: []const u8) !bool {
    const resolved_left = try std.fs.path.resolve(allocator, &.{left});
    defer allocator.free(resolved_left);
    const resolved_right = try std.fs.path.resolve(allocator, &.{right});
    defer allocator.free(resolved_right);
    return std.mem.eql(u8, resolved_left, resolved_right);
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
        \\  machina bench [path] [--frames N] [--dt seconds] [--format text|json]
        \\  machina test [tests-path|project-path] [--format text|json]
        \\  machina build [path] [--output DIR] [--name NAME] [--force] [--format text|json]
        \\  machina run [path] [--frames N] [--editor]
        \\  machina render [--editor] [--select entity-id] [--frames N] [path] [output.bmp]
        \\  machina render-test [--editor] [--select entity-id] [--frames N] [path] [output.bmp]
        \\  machina visual-test [--editor] [--select entity-id] [--frames N] [--update] <path> <expected.png> [actual.png]
        \\
    );
}

const ArgumentError = error{
    InvalidDelta,
    InvalidFrames,
    InvalidFormat,
    MissingExpected,
    UnknownArgument,
};

const SceneReloadContext = struct {
    live_project: *machina.LiveProject,
    stderr: *Io.Writer,
    target_path: []const u8,
};

const RenderFrameContext = struct {
    live_project: *machina.LiveProject,
    stderr: *Io.Writer,
    target_path: []const u8,
    selected_entity_id: ?[]const u8,
    failed: bool = false,
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
                "Reloaded {s}{s}{s}{s}: {s}, {d} entities, {d} renderable cubes, {d} scripts, {d} schedule batches\n",
                .{
                    if (info.project_reloaded) "project" else "",
                    if (info.scene_reloaded) if (info.project_reloaded) " and scene" else "scene" else "",
                    if (info.scripts_reloaded) if (info.project_reloaded or info.scene_reloaded) " and scripts" else "scripts" else "",
                    if (info.native_reloaded) if (info.project_reloaded or info.scene_reloaded or info.scripts_reloaded) " and native" else "native" else "",
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

fn stepLiveProject(raw_context: *anyopaque, delta_seconds: f32, input: *machina.FrameInput) void {
    const context: *SceneReloadContext = @ptrCast(@alignCast(raw_context));
    context.live_project.updateWithInput(delta_seconds, input.*);
    input.editor = context.live_project.editorFrameState();
    input.system_profiles = context.live_project.systemProfileSnapshots();
    if (context.live_project.lastDiagnostic()) |diagnostic| {
        printScriptDiagnostic(context.stderr, context.target_path, diagnostic.*) catch {};
        context.stderr.flush() catch {};
    }
}

fn stepRenderLiveProject(raw_context: *anyopaque, delta_seconds: f32, input: *machina.FrameInput) void {
    const context: *RenderFrameContext = @ptrCast(@alignCast(raw_context));
    context.live_project.updateWithInput(delta_seconds, input.*);
    input.editor = renderCommandEditorFrame(context.live_project, context.selected_entity_id);
    input.system_profiles = context.live_project.systemProfileSnapshots();
    if (context.live_project.lastDiagnostic()) |diagnostic| {
        context.failed = true;
        printScriptDiagnostic(context.stderr, context.target_path, diagnostic.*) catch {};
        context.stderr.flush() catch {};
    }
}

fn renderCommandFrameInput(live_project: *machina.LiveProject, options: RenderCommandOptions) machina.FrameInput {
    const editor = renderCommandEditorFrame(live_project, options.selected_entity_id);
    if (!options.editor and editor.selected_entity == null) {
        return .{};
    }
    return .{
        .debug_overlay_visible = true,
        .fps = 60.0,
        .editor = editor,
        .system_profiles = live_project.systemProfileSnapshots(),
    };
}

fn renderCommandEditorFrame(live_project: *machina.LiveProject, selected_entity_id: ?[]const u8) machina.EditorFrameState {
    var editor = live_project.editorFrameState();
    editor.selected_entity = if (selected_entity_id) |id| live_project.scene.world.findEntityById(id) else null;
    return editor;
}

const clap_parsers = .{
    .COMMAND = clap.parsers.string,
    .PATH = clap.parsers.string,
    .OUTPUT = clap.parsers.string,
    .NAME = clap.parsers.string,
    .ENTITY = clap.parsers.string,
    .EXTRA = clap.parsers.string,
    .FORMAT = parseCheckOutputFormat,
    .FRAMES = parseFrameCount,
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

fn parseTopLevel(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!TopLevel {
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

fn parseWindowOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!machina.WindowOptions {
    return (try parseRunOptions(allocator, args)).window_options;
}

fn parseRunOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!RunCommandOptions {
    const params = comptime clap.parseParamsComptime(
        \\--frames <FRAMES>
        \\--editor
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
    return options;
}

fn parseInitOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!InitCommandOptions {
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

fn parseRenderOptions(allocator: std.mem.Allocator, args: []const []const u8, default_output_path: []const u8) ArgumentError!RenderCommandOptions {
    const params = comptime clap.parseParamsComptime(
        \\--editor
        \\--select <ENTITY>
        \\--frames <FRAMES>
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
    return options;
}

fn parseVisualTestOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!VisualTestCommandOptions {
    const params = comptime clap.parseParamsComptime(
        \\--editor
        \\--select <ENTITY>
        \\--frames <FRAMES>
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
        .output_path = if (result.positionals[2].len == 1) result.positionals[2][0] else "zig-out/machina-visual-test.png",
    };
    render.editor = result.args.editor != 0;
    if (result.args.select) |entity_id| {
        render.selected_entity_id = entity_id;
        render.editor = true;
    }
    if (result.args.frames) |frames| {
        render.frames = frames;
    }

    return .{
        .render = render,
        .expected_path = expected_path,
        .update = result.args.update != 0,
    };
}

fn parseCheckOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!CheckOptions {
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

fn parseStepOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!StepCommandOptions {
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

fn parseBenchOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!BenchCommandOptions {
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

fn parseTestOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!TestCommandOptions {
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

fn parseBuildOptions(allocator: std.mem.Allocator, args: []const []const u8) ArgumentError!BuildCommandOptions {
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
        ArgumentError.InvalidFormat => ArgumentError.InvalidFormat,
        ArgumentError.MissingExpected => ArgumentError.MissingExpected,
        else => ArgumentError.UnknownArgument,
    };
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
    input_frames: []machina.StepInputFrame = &.{},
    expectations: []TestExpectation = &.{},

    fn deinit(self: *TestManifest, allocator: std.mem.Allocator) void {
        allocator.free(self.input_frames);
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

const TestInputFrameDraft = struct {
    frame: ?u32 = null,
    input: machina.FrameInput = .{},

    fn take(self: *TestInputFrameDraft) TestManifestError!machina.StepInputFrame {
        const frame = self.frame orelse return TestManifestError.InvalidTestManifest;
        self.frame = null;
        return .{
            .frame = frame,
            .input = self.input,
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
    const has_project_manifest = pathExists(io, dir, machina.project_file_name) or pathExists(io, dir, machina.legacy_project_file_name);
    return has_project_manifest and pathExists(io, dir, "test.machina.toml");
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
    var input_frames: std.ArrayList(machina.StepInputFrame) = .empty;
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
    input_frames: *std.ArrayList(machina.StepInputFrame),
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
        .input_frames = manifest.input_frames,
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
        ArgumentError.MissingExpected => "visual-test expects an expected image path",
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
        machina.ProjectError.InvalidBuildOutput => "invalid build output path",
        machina.ProjectError.MissingProjectFile => "missing project.toml",
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

fn printBenchOkText(writer: *Io.Writer, result: BenchResult) !void {
    const startup_ms = @as(f64, @floatFromInt(result.startup_ns)) / 1_000_000.0;
    const update_ms = @as(f64, @floatFromInt(result.update_ns)) / 1_000_000.0;
    const ns_per_frame = result.nsPerFrame();
    const ms_per_frame = @as(f64, @floatFromInt(ns_per_frame)) / 1_000_000.0;

    try writer.print("Benchmark OK: {s}\n", .{result.project_name});
    try writer.print("Scene: {s}\n", .{result.scene_name});
    try writer.print("Frames: {d}, dt: {d}\n", .{ result.frames, result.delta_seconds });
    try writer.print("Startup: {d} ms\n", .{startup_ms});
    try writer.print("Update: {d} ms total, {d} ms/frame\n", .{ update_ms, ms_per_frame });
    try writer.print("Entities: {d}, components: {d}, renderables: {d}, render batches: {d}\n", .{
        result.entity_count,
        result.component_instance_count,
        result.renderable_count,
        result.render_batch_count,
    });
    try writer.print("UI: {d} rects, {d} text runs\n", .{
        result.ui_rect_count,
        result.ui_text_count,
    });
}

fn printBuildOkText(writer: *Io.Writer, result: machina.BuildResult) !void {
    try writer.print("Build OK: {s}\n", .{result.project_name});
    try writer.print("Bundle: {s}\n", .{result.bundle_path});
    try writer.print("Project: {s}\n", .{result.project_path});
    try writer.print("Runtime: {s}\n", .{result.runtime_path});
    try writer.print("Launcher: {s}\n", .{result.launcher_path});
    if (result.native_artifact) |path| {
        try writer.print("Native artifact: {s}\n", .{path});
    }
    if (result.sdl3_warning) |warning| {
        try writer.print("Warning: {s}\n", .{warning});
    }
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

fn printBenchOkJson(writer: *Io.Writer, result: BenchResult) !void {
    try writer.writeAll("{\"ok\":true,\"project\":{\"name\":");
    try writeJsonString(writer, result.project_name);
    try writer.writeAll("},\"scene\":{\"name\":");
    try writeJsonString(writer, result.scene_name);
    try writer.print(",\"entities\":{d},\"component_instances\":{d},\"renderables\":{d},\"render_batches\":{d},\"ui_rects\":{d},\"ui_texts\":{d}", .{
        result.entity_count,
        result.component_instance_count,
        result.renderable_count,
        result.render_batch_count,
        result.ui_rect_count,
        result.ui_text_count,
    });
    try writer.writeAll("},\"benchmark\":{");
    try writer.print("\"frames\":{d},\"dt\":{d},\"startup_ns\":{d},\"update_ns\":{d},\"ns_per_frame\":{d}", .{
        result.frames,
        result.delta_seconds,
        result.startup_ns,
        result.update_ns,
        result.nsPerFrame(),
    });
    try writer.writeAll("}}\n");
}

fn printBuildOkJson(writer: *Io.Writer, result: machina.BuildResult) !void {
    try writer.writeAll("{\"ok\":true,\"project\":");
    try writeJsonString(writer, result.project_name);
    try writer.writeAll(",\"bundle\":");
    try writeJsonString(writer, result.bundle_path);
    try writer.writeAll(",\"project_path\":");
    try writeJsonString(writer, result.project_path);
    try writer.writeAll(",\"runtime\":");
    try writeJsonString(writer, result.runtime_path);
    try writer.writeAll(",\"launcher\":");
    try writeJsonString(writer, result.launcher_path);
    try writer.writeAll(",\"native_artifact\":");
    if (result.native_artifact) |path| {
        try writeJsonString(writer, path);
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"sdl3_bundled\":{}", .{result.sdl3_bundled});
    try writer.writeAll(",\"sdl3_warning\":");
    if (result.sdl3_warning) |warning| {
        try writeJsonString(writer, warning);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll("}\n");
}

fn printProjectSummaryJson(writer: *Io.Writer, project: machina.Project) !void {
    try writer.writeAll("{\"name\":");
    try writeJsonString(writer, project.name);
    try writer.writeAll(",\"default_scene\":");
    try writeJsonString(writer, project.default_scene);
    try writer.print(",\"scripts\":{d}", .{project.scripts.len});
    if (project.native) |native_path| {
        try writer.writeAll(",\"native\":");
        try writeJsonString(writer, native_path);
    }
    if (project.native_artifact) |native_artifact_path| {
        try writer.writeAll(",\"native_artifact\":");
        try writeJsonString(writer, native_artifact_path);
    }
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

test "parseInitOptions defaults to current directory" {
    const options = try parseInitOptions(std.testing.allocator, &.{});
    try std.testing.expectEqualStrings(".", options.target_path);
}

test "parseInitOptions accepts one target path" {
    const args = [_][]const u8{"games/demo"};
    const options = try parseInitOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("games/demo", options.target_path);
}

test "parseInitOptions rejects extra arguments" {
    const args = [_][]const u8{ "games/demo", "extra" };
    try std.testing.expectError(ArgumentError.UnknownArgument, parseInitOptions(std.testing.allocator, &args));
}

test "run init command creates a checkable project" {
    const root_path = ".zig-cache/test-cli-init-project";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    var stdout_buffer: [512]u8 = undefined;
    var stdout = Io.Writer.fixed(&stdout_buffer);
    var stderr_buffer: [512]u8 = undefined;
    var stderr = Io.Writer.fixed(&stderr_buffer);
    const args = [_][]const u8{ "machina", "init", root_path };

    const exit_code = try run(io, std.testing.allocator, &args, &stdout, &stderr);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expectEqualStrings("Initialized Machina project at " ++ root_path ++ "\n", stdout.buffered());
    try std.testing.expectEqualStrings("", stderr.buffered());

    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);
    try std.testing.expect(pathExists(io, root_dir, machina.project_file_name));
    try std.testing.expect(pathExists(io, root_dir, "scenes/main.scene.toml"));
    try std.testing.expect(pathExists(io, root_dir, "assets/.gitkeep"));
    try std.testing.expect(!pathExists(io, root_dir, "native/game.zig"));

    const metadata = try root_dir.readFileAlloc(io, machina.project_file_name, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(metadata);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "\n# native = \"native/game.zig\"\n") != null);

    const result = try machina.checkProject(io, std.testing.allocator, root_path);
    defer machina.freeCheckResult(std.testing.allocator, result);
    try std.testing.expectEqualStrings("test-cli-init-project", result.project.name);
}

test "run init command rejects extra arguments" {
    const root_path = ".zig-cache/test-cli-init-extra";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    var stdout_buffer: [512]u8 = undefined;
    var stdout = Io.Writer.fixed(&stdout_buffer);
    var stderr_buffer: [512]u8 = undefined;
    var stderr = Io.Writer.fixed(&stderr_buffer);
    const args = [_][]const u8{ "machina", "init", root_path, "extra" };

    const exit_code = try run(io, std.testing.allocator, &args, &stdout, &stderr);
    try std.testing.expectEqual(@as(u8, 1), exit_code);
    try std.testing.expectEqualStrings("", stdout.buffered());
    try std.testing.expectEqualStrings("unknown argument\n", stderr.buffered());
    try std.testing.expectError(machina.ProjectError.InvalidProject, machina.checkProject(io, std.testing.allocator, root_path));
}

test "parseWindowOptions accepts frames and editor flag" {
    const args = [_][]const u8{ "--frames", "12", "--editor" };
    const options = try parseWindowOptions(std.testing.allocator, &args);
    try std.testing.expectEqual(@as(u32, 12), options.max_frames.?);
    try std.testing.expect(options.editor);
}

test "parseRenderOptions accepts editor flag before path" {
    const args = [_][]const u8{ "--editor", "examples/spawn_swarm", "zig-out/spawn-editor.bmp" };
    const options = try parseRenderOptions(std.testing.allocator, &args, "zig-out/default.bmp");
    try std.testing.expect(options.editor);
    try std.testing.expectEqualStrings("examples/spawn_swarm", options.target_path);
    try std.testing.expectEqualStrings("zig-out/spawn-editor.bmp", options.output_path);
}

test "parseRenderOptions accepts editor flag after output" {
    const args = [_][]const u8{ "examples/spawn_swarm", "zig-out/spawn-editor.bmp", "--editor" };
    const options = try parseRenderOptions(std.testing.allocator, &args, "zig-out/default.bmp");
    try std.testing.expect(options.editor);
    try std.testing.expectEqualStrings("examples/spawn_swarm", options.target_path);
    try std.testing.expectEqualStrings("zig-out/spawn-editor.bmp", options.output_path);
}

test "parseRenderOptions accepts selected entity" {
    const args = [_][]const u8{ "examples/spawn_swarm", "zig-out/spawn-editor.bmp", "--select", "swarm.0" };
    const options = try parseRenderOptions(std.testing.allocator, &args, "zig-out/default.bmp");
    try std.testing.expect(options.editor);
    try std.testing.expectEqualStrings("examples/spawn_swarm", options.target_path);
    try std.testing.expectEqualStrings("zig-out/spawn-editor.bmp", options.output_path);
    try std.testing.expectEqualStrings("swarm.0", options.selected_entity_id.?);
}

test "parseRenderOptions accepts frame count" {
    const args = [_][]const u8{ "--frames=60", "examples/ui_gallery", "zig-out/ui-gallery.bmp" };
    const options = try parseRenderOptions(std.testing.allocator, &args, "zig-out/default.bmp");
    try std.testing.expectEqual(@as(u32, 60), options.frames);
    try std.testing.expectEqualStrings("examples/ui_gallery", options.target_path);
    try std.testing.expectEqualStrings("zig-out/ui-gallery.bmp", options.output_path);
}

test "parseRenderOptions rejects extra positionals" {
    const args = [_][]const u8{ "examples/minimal", "one.bmp", "two.bmp" };
    try std.testing.expectError(ArgumentError.UnknownArgument, parseRenderOptions(std.testing.allocator, &args, "zig-out/default.bmp"));
}

test "parseVisualTestOptions accepts expected and actual paths" {
    const args = [_][]const u8{ "--frames=4", "tests/golden/postprocess_effects", "tests/golden/postprocess_effects/expected.png", "zig-out/postprocess-actual.png" };
    const options = try parseVisualTestOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("tests/golden/postprocess_effects", options.render.target_path);
    try std.testing.expectEqualStrings("tests/golden/postprocess_effects/expected.png", options.expected_path);
    try std.testing.expectEqualStrings("zig-out/postprocess-actual.png", options.render.output_path);
    try std.testing.expectEqual(@as(u32, 4), options.render.frames);
    try std.testing.expect(!options.update);
}

test "parseVisualTestOptions supports update and selected entity" {
    const args = [_][]const u8{ "--update", "--select", "cube-1", "tests/golden/basic", "tests/golden/basic/expected.png" };
    const options = try parseVisualTestOptions(std.testing.allocator, &args);
    try std.testing.expect(options.update);
    try std.testing.expect(options.render.editor);
    try std.testing.expectEqualStrings("cube-1", options.render.selected_entity_id.?);
    try std.testing.expectEqualStrings("zig-out/machina-visual-test.png", options.render.output_path);
}

test "parseVisualTestOptions requires expected path" {
    const args = [_][]const u8{"tests/golden/basic"};
    try std.testing.expectError(ArgumentError.MissingExpected, parseVisualTestOptions(std.testing.allocator, &args));
}

test "sameResolvedPath detects equivalent relative paths" {
    try std.testing.expect(try sameResolvedPath(std.testing.allocator, "tests/golden/postprocess_effects/expected.png", "./tests/golden/postprocess_effects/expected.png"));
    try std.testing.expect(!try sameResolvedPath(std.testing.allocator, "tests/golden/postprocess_effects/expected.png", "zig-out/postprocess-effects-actual.png"));
}

test "parseCheckOptions accepts path and json format" {
    const args = [_][]const u8{ "examples/minimal", "--format=json" };
    const options = try parseCheckOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("examples/minimal", options.target_path);
    try std.testing.expectEqual(CheckOutputFormat.json, options.format);
}

test "parseCheckOptions accepts format before path" {
    const args = [_][]const u8{ "--format", "json", "examples/minimal" };
    const options = try parseCheckOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("examples/minimal", options.target_path);
    try std.testing.expectEqual(CheckOutputFormat.json, options.format);
}

test "parseCheckOptions rejects unknown format" {
    const args = [_][]const u8{"--format=yaml"};
    try std.testing.expectError(ArgumentError.InvalidFormat, parseCheckOptions(std.testing.allocator, &args));
}

test "parseStepOptions accepts path frames dt and json format" {
    const args = [_][]const u8{ "examples/minimal", "--frames=60", "--dt", "0.016", "--format=json" };
    const options = try parseStepOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("examples/minimal", options.target_path);
    try std.testing.expectEqual(@as(u32, 60), options.frames);
    try std.testing.expectApproxEqAbs(@as(f32, 0.016), options.delta_seconds, 0.000001);
    try std.testing.expectEqual(CheckOutputFormat.json, options.format);
}

test "parseStepOptions rejects invalid dt" {
    const args = [_][]const u8{ "--dt", "inf" };
    try std.testing.expectError(ArgumentError.InvalidDelta, parseStepOptions(std.testing.allocator, &args));
}

test "parseBenchOptions accepts path frames dt and json format" {
    const args = [_][]const u8{ "examples/spawn_swarm", "--frames=120", "--dt", "0.016", "--format=json" };
    const options = try parseBenchOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("examples/spawn_swarm", options.target_path);
    try std.testing.expectEqual(@as(u32, 120), options.frames);
    try std.testing.expectApproxEqAbs(@as(f32, 0.016), options.delta_seconds, 0.000001);
    try std.testing.expectEqual(CheckOutputFormat.json, options.format);
}

test "parseTestOptions defaults to tests/projects" {
    const options = try parseTestOptions(std.testing.allocator, &.{});
    try std.testing.expectEqualStrings("tests/projects", options.target_path);
    try std.testing.expectEqual(CheckOutputFormat.text, options.format);
}

test "parseTestOptions accepts path and json format" {
    const args = [_][]const u8{ "tests/projects/health_tick", "--format=json" };
    const options = try parseTestOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("tests/projects/health_tick", options.target_path);
    try std.testing.expectEqual(CheckOutputFormat.json, options.format);
}

test "parseBuildOptions accepts path output name force and json format" {
    const args = [_][]const u8{ "examples/minimal", "--output=zig-out/packages", "--name", "minimal-demo", "--force", "--format=json" };
    const options = try parseBuildOptions(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("examples/minimal", options.target_path);
    try std.testing.expectEqualStrings("zig-out/packages", options.output_root.?);
    try std.testing.expectEqualStrings("minimal-demo", options.name.?);
    try std.testing.expect(options.force);
    try std.testing.expectEqual(CheckOutputFormat.json, options.format);
}

test "parseBuildOptions defaults output root to project build directory" {
    const options = try parseBuildOptions(std.testing.allocator, &.{});
    try std.testing.expectEqualStrings(".", options.target_path);
    try std.testing.expect(options.output_root == null);
}

test "parseBuildOptions rejects extra positionals" {
    const args = [_][]const u8{ "examples/minimal", "extra" };
    try std.testing.expectError(ArgumentError.UnknownArgument, parseBuildOptions(std.testing.allocator, &args));
}

test "parseTestManifest reads field assertions" {
    var manifest = try parseTestManifest(std.testing.allocator,
        \\frames = 4
        \\dt = 1.0
        \\
        \\[[input.frame]]
        \\frame = 2
        \\debug_overlay_visible = true
        \\viewport = [1280.0, 720.0]
        \\pointer = [36.0, 190.0]
        \\pointer_delta = [3.0, -2.0]
        \\secondary_down = true
        \\wheel_delta = [0.0, -1.0]
        \\move_forward = true
        \\move_up = true
        \\system_profile_count_hint = 9
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
    try std.testing.expectEqual(@as(usize, 1), manifest.input_frames.len);
    try std.testing.expectEqual(@as(u32, 2), manifest.input_frames[0].frame);
    try std.testing.expect(manifest.input_frames[0].input.debug_overlay_visible);
    try std.testing.expectApproxEqAbs(@as(f32, 1280.0), manifest.input_frames[0].input.viewport_width, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 36.0), manifest.input_frames[0].input.pointer.position[0], 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), manifest.input_frames[0].input.pointer.delta[0], 0.000001);
    try std.testing.expect(manifest.input_frames[0].input.pointer.secondary_down);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), manifest.input_frames[0].input.pointer.wheel_delta[1], 0.000001);
    try std.testing.expect(manifest.input_frames[0].input.keyboard.move_forward);
    try std.testing.expect(manifest.input_frames[0].input.keyboard.move_up);
    try std.testing.expectEqual(@as(usize, 9), manifest.input_frames[0].input.system_profile_count_hint);
    try std.testing.expectEqual(@as(usize, 2), manifest.expectations.len);
    try std.testing.expectEqualStrings("door-1", manifest.expectations[0].entity);
    try std.testing.expectEqualStrings("door", manifest.expectations[0].component);
    try std.testing.expectEqualStrings("openness", manifest.expectations[0].field);
    try std.testing.expect(manifest.expectations[0].expected.matches(.{ .float = 1.0 }));
    try std.testing.expect(manifest.expectations[1].expected.matches(.{ .boolean = true }));
}

test "parseTestManifest rejects duplicate input frames" {
    try std.testing.expectError(TestManifestError.InvalidTestManifest, parseTestManifest(std.testing.allocator,
        \\frames = 2
        \\
        \\[[input.frame]]
        \\frame = 1
        \\pointer = [1.0, 2.0]
        \\
        \\[[input.frame]]
        \\frame = 1
        \\pointer = [3.0, 4.0]
        \\
        \\[[expect.field]]
        \\entity = "scroll"
        \\component = "machina.ui.scroll_view"
        \\field = "content_offset"
        \\equals_vec3 = [0.0, 0.0, 0.0]
        \\
    ));
}

test "testCommand runs a gameplay project fixture" {
    var stdout_buffer: [8192]u8 = undefined;
    var stdout = Io.Writer.fixed(&stdout_buffer);
    var stderr_buffer: [2048]u8 = undefined;
    var stderr = Io.Writer.fixed(&stderr_buffer);
    const io = Io.Threaded.global_single_threaded.io();

    const args = [_][]const u8{"tests/projects/health_tick"};
    const exit_code = try testCommand(io, std.testing.allocator, &args, &stdout, &stderr);

    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout.buffered(), "PASS health_tick") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout.buffered(), "Test projects: 1 passed, 0 failed") != null);
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
