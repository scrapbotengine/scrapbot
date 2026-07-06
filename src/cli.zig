const std = @import("std");
const Io = std.Io;
const scrapbot = @import("scrapbot");
const cli_help = @import("cli/help.zig");
const cli_options = @import("cli/options.zig");
const cli_output = @import("cli/output.zig");
const cli_path = @import("cli/path.zig");
const test_manifest = @import("cli/test_manifest.zig");

const BenchResult = cli_options.BenchResult;
const CheckOutputFormat = cli_options.CheckOutputFormat;
const RenderCommandOptions = cli_options.RenderCommandOptions;
const TestCaseStats = test_manifest.TestCaseStats;
const TestManifest = test_manifest.TestManifest;
const TestSuiteSummary = test_manifest.TestSuiteSummary;
const collectTestProjects = test_manifest.collectTestProjects;
const evaluateExpectation = cli_output.evaluateExpectation;
const freeOwnedStringList = test_manifest.freeOwnedStringList;
const loadTestManifest = test_manifest.loadTestManifest;
const parseBenchOptions = cli_options.parseBenchOptions;
const parseBuildOptions = cli_options.parseBuildOptions;
const parseCheckOptions = cli_options.parseCheckOptions;
const parseInitOptions = cli_options.parseInitOptions;
const parseRenderOptions = cli_options.parseRenderOptions;
const parseRunOptions = cli_options.parseRunOptions;
const parseStepOptions = cli_options.parseStepOptions;
const parseTestOptions = cli_options.parseTestOptions;
const parseTopLevel = cli_options.parseTopLevel;
const parseVisualTestOptions = cli_options.parseVisualTestOptions;
const printHelp = cli_help.printHelp;
const printArgumentError = cli_output.printArgumentError;
const printBenchOkJson = cli_output.printBenchOkJson;
const printBenchOkText = cli_output.printBenchOkText;
const printBuildOkJson = cli_output.printBuildOkJson;
const printBuildOkText = cli_output.printBuildOkText;
const printCheckOkJson = cli_output.printCheckOkJson;
const printExpectationFailureText = cli_output.printExpectationFailureText;
const printProjectError = cli_output.printProjectError;
const printProjectErrorJson = cli_output.printProjectErrorJson;
const printScriptDiagnostic = cli_output.printScriptDiagnostic;
const printScriptDiagnosticJson = cli_output.printScriptDiagnosticJson;
const printStepFailureJson = cli_output.printStepFailureJson;
const printStepFailureText = cli_output.printStepFailureText;
const printStepOkJson = cli_output.printStepOkJson;
const printStepOkText = cli_output.printStepOkText;
const printTestCaseDiagnosticFailureJson = cli_output.printTestCaseDiagnosticFailureJson;
const printTestCaseLoadFailureJson = cli_output.printTestCaseLoadFailureJson;
const printTestCaseOkJson = cli_output.printTestCaseOkJson;
const printTestCaseRuntimeFailureJson = cli_output.printTestCaseRuntimeFailureJson;
const printTestDiscoveryFailureJson = cli_output.printTestDiscoveryFailureJson;
const printNoTestProjectsJson = cli_output.printNoTestProjectsJson;
const printTestSuiteEndJson = cli_output.printTestSuiteEndJson;
const printTestSuiteSeparatorJson = cli_output.printTestSuiteSeparatorJson;
const printTestSuiteStartJson = cli_output.printTestSuiteStartJson;
const printTestSummaryText = cli_output.printTestSummaryText;
const projectNameFromPath = cli_path.projectNameFromPath;
const renderArtifactMetadataPath = cli_path.renderArtifactMetadataPath;
const sameResolvedPath = cli_path.sameResolvedPath;
const trimTrailingSlashes = cli_path.trimTrailingSlashes;

pub fn run(
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
        try stdout.print("scrapbot {s}\n", .{scrapbot.version});
        return 0;
    }

    if (top_level.help or top_level.command == null) {
        try printHelp(stdout);
        return 0;
    }

    const command = top_level.command.?;
    if (std.mem.eql(u8, command, "version")) {
        try stdout.print("scrapbot {s}\n", .{scrapbot.version});
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
        scrapbot.initProject(io, allocator, options.target_path, name) catch |err| {
            try printProjectError(stderr, options.target_path, err);
            return 1;
        };
        try stdout.print("Initialized Scrapbot project at {s}\n", .{options.target_path});
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
        defer scrapbot.freeCheckResult(allocator, result);
        var live_project = scrapbot.LiveProject.init(io, std.heap.smp_allocator, target_path) catch |err| {
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

        scrapbot.runDemoWindow(allocator, result.project.name, window_options, live_project.renderScene()) catch |err| {
            try stderr.print("run failed: {s}\n", .{@errorName(err)});
            return 1;
        };
        return 0;
    }

    if (std.mem.eql(u8, command, "render")) {
        const options = parseRenderOptions(allocator, args[2..], "zig-out/scrapbot-cube.png") catch |err| {
            try printArgumentError(stderr, err);
            return 1;
        };
        const result = try checkProjectForCommand(io, allocator, options.target_path, stderr) orelse return 1;
        defer scrapbot.freeCheckResult(allocator, result);
        var live_project = scrapbot.LiveProject.init(io, allocator, options.target_path) catch |err| {
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
        scrapbot.renderDemoImageFrames(io, allocator, options.output_path, live_project.renderScene(), .{
            .frames = options.frames,
            .width = options.width,
            .height = options.height,
            .pixel_scale = options.pixel_scale,
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

        try writeRenderArtifactMetadata(io, allocator, options.output_path, options);
        try printRenderArtifact(stdout, "Rendered artifact", options.output_path, options);
        return 0;
    }

    if (std.mem.eql(u8, command, "render-test")) {
        const options = parseRenderOptions(allocator, args[2..], "zig-out/scrapbot-render-test.png") catch |err| {
            try printArgumentError(stderr, err);
            return 1;
        };
        const result = try checkProjectForCommand(io, allocator, options.target_path, stderr) orelse return 1;
        defer scrapbot.freeCheckResult(allocator, result);
        var live_project = scrapbot.LiveProject.init(io, allocator, options.target_path) catch |err| {
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
        scrapbot.renderDemoImageFrames(io, allocator, options.output_path, live_project.renderScene(), .{
            .frames = options.frames,
            .width = options.width,
            .height = options.height,
            .pixel_scale = options.pixel_scale,
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

        const verification = scrapbot.verifyRenderImage(io, allocator, options.output_path, .{
            .min_visible_components = 1,
            .min_color_groups = expectedColorGroups(scene),
        }) catch |err| {
            try stderr.print("render-test verification failed: {s}\n", .{@errorName(err)});
            return 1;
        };

        try stdout.print(
            "Render test OK: physical {d}x{d}, logical {d:.1}x{d:.1} @{d:.2}x, foreground pixels: {d}, visible components: {d}, color groups: {d}\n",
            .{
                verification.width,
                verification.height,
                logicalRenderWidth(options),
                logicalRenderHeight(options),
                options.pixel_scale,
                verification.foreground_pixels,
                verification.visible_components,
                verification.color_groups,
            },
        );
        try writeRenderArtifactMetadata(io, allocator, options.output_path, options);
        try printRenderArtifact(stdout, "Rendered artifact", options.output_path, options);
        return 0;
    }

    if (std.mem.eql(u8, command, "visual-test")) {
        const options = parseVisualTestOptions(allocator, args[2..]) catch |err| {
            try printArgumentError(stderr, err);
            return 1;
        };
        const result = try checkProjectForCommand(io, allocator, options.render.target_path, stderr) orelse return 1;
        defer scrapbot.freeCheckResult(allocator, result);
        var live_project = scrapbot.LiveProject.init(io, allocator, options.render.target_path) catch |err| {
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
        scrapbot.renderDemoImageFrames(io, allocator, render_output, live_project.renderScene(), .{
            .frames = options.render.frames,
            .width = options.render.width,
            .height = options.render.height,
            .pixel_scale = options.render.pixel_scale,
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
            try writeRenderArtifactMetadata(io, allocator, render_output, options.render);
            try stdout.print("Updated golden fixture: {s}\n", .{options.expected_path});
            return 0;
        }

        const comparison_options = scrapbot.RenderComparisonOptions{};
        const comparison = scrapbot.compareRenderImage(io, allocator, options.expected_path, options.render.output_path, comparison_options) catch |err| {
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
        try writeRenderArtifactMetadata(io, allocator, options.render.output_path, options.render);
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

    var result = scrapbot.checkProjectDetailed(io, allocator, options.target_path) catch |err| {
        switch (options.format) {
            .text => try printProjectError(stderr, options.target_path, err),
            .json => try printProjectErrorJson(stdout, options.target_path, err),
        }
        return 1;
    };

    switch (result) {
        .ok => |ok| {
            defer scrapbot.freeCheckResult(allocator, ok);
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

    const result = scrapbot.stepProjectDetailed(io, allocator, options.target_path, .{
        .frames = options.frames,
        .delta_seconds = options.delta_seconds,
    }) catch |err| {
        switch (options.format) {
            .text => try printProjectError(stderr, options.target_path, err),
            .json => try printProjectErrorJson(stdout, options.target_path, err),
        }
        return 1;
    };
    defer scrapbot.freeStepDetailedResult(allocator, result);

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

    var live_project = scrapbot.LiveProject.init(io, allocator, options.target_path) catch |err| {
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

    const render_stats = scrapbot.renderStats(allocator, live_project.renderScene()) catch |err| {
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
            .json => try printTestDiscoveryFailureJson(stdout, options.target_path, err),
        }
        return 1;
    };
    defer freeOwnedStringList(allocator, project_paths);

    if (project_paths.len == 0) {
        switch (options.format) {
            .text => try stderr.print("{s}: no Scrapbot test projects found\n", .{options.target_path}),
            .json => try printNoTestProjectsJson(stdout, options.target_path),
        }
        return 1;
    }

    var summary = TestSuiteSummary{};
    if (options.format == .json) {
        try printTestSuiteStartJson(stdout);
    }

    for (project_paths, 0..) |project_path, index| {
        if (options.format == .json and index != 0) {
            try printTestSuiteSeparatorJson(stdout);
        }

        const stats = try runTestCase(io, allocator, project_path, options.format, stdout, stderr);
        summary.add(stats);
    }

    switch (options.format) {
        .text => try printTestSummaryText(stdout, summary),
        .json => try printTestSuiteEndJson(stdout, summary),
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

    var check_result = scrapbot.checkProjectDetailed(io, allocator, options.target_path) catch |err| {
        switch (options.format) {
            .text => try printProjectError(stderr, options.target_path, err),
            .json => try printProjectErrorJson(stdout, options.target_path, err),
        }
        return 1;
    };
    switch (check_result) {
        .ok => |ok| scrapbot.freeCheckResult(allocator, ok),
        .invalid => |*diagnostic| {
            defer diagnostic.deinit(allocator);
            switch (options.format) {
                .text => try printScriptDiagnostic(stderr, options.target_path, diagnostic.*),
                .json => try printScriptDiagnosticJson(stdout, options.target_path, diagnostic.*),
            }
            return 1;
        },
    }

    var build_result = scrapbot.buildProjectDetailed(io, allocator, options.target_path, .{
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
) !?scrapbot.CheckResult {
    var result = scrapbot.checkProjectDetailed(io, allocator, target_path) catch |err| {
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

const SceneReloadContext = struct {
    live_project: *scrapbot.LiveProject,
    stderr: *Io.Writer,
    target_path: []const u8,
};

const RenderFrameContext = struct {
    live_project: *scrapbot.LiveProject,
    stderr: *Io.Writer,
    target_path: []const u8,
    selected_entity_id: ?[]const u8,
    failed: bool = false,
};

fn pollSceneReload(raw_context: *anyopaque) ?scrapbot.RenderScene {
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

fn stepLiveProject(raw_context: *anyopaque, delta_seconds: f32, input: *scrapbot.FrameInput) void {
    const context: *SceneReloadContext = @ptrCast(@alignCast(raw_context));
    context.live_project.updateWithInput(delta_seconds, input.*);
    input.editor = context.live_project.editorFrameState();
    input.system_profiles = context.live_project.systemProfileSnapshots();
    if (context.live_project.lastDiagnostic()) |diagnostic| {
        printScriptDiagnostic(context.stderr, context.target_path, diagnostic.*) catch {};
        context.stderr.flush() catch {};
    }
}

fn stepRenderLiveProject(raw_context: *anyopaque, delta_seconds: f32, input: *scrapbot.FrameInput) void {
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

fn renderCommandFrameInput(live_project: *scrapbot.LiveProject, options: RenderCommandOptions) scrapbot.FrameInput {
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

fn renderCommandEditorFrame(live_project: *scrapbot.LiveProject, selected_entity_id: ?[]const u8) scrapbot.EditorFrameState {
    var editor = live_project.editorFrameState();
    editor.selected_entity = if (selected_entity_id) |id| live_project.scene.world.findEntityById(id) else null;
    return editor;
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
            .text => try stdout.print("FAIL {s}: test.scrapbot.toml {s}\n", .{ name, @errorName(err) }),
            .json => try printTestCaseLoadFailureJson(stdout, name, project_path, "manifest", err),
        }
        return stats;
    };
    defer manifest.deinit(allocator);

    var stats = TestCaseStats{ .assertions = @intCast(manifest.expectations.len) };
    const result = scrapbot.stepProjectDetailed(io, allocator, project_path, .{
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
    defer scrapbot.freeStepDetailedResult(allocator, result);

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
    ok: scrapbot.StepOk,
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

fn logicalRenderWidth(options: RenderCommandOptions) f32 {
    return @as(f32, @floatFromInt(options.width)) / options.pixel_scale;
}

fn logicalRenderHeight(options: RenderCommandOptions) f32 {
    return @as(f32, @floatFromInt(options.height)) / options.pixel_scale;
}

fn printRenderArtifact(writer: *Io.Writer, label: []const u8, path: []const u8, options: RenderCommandOptions) !void {
    try writer.print(
        "{s}: {s} (physical {d}x{d}, logical {d:.1}x{d:.1} @{d:.2}x)\n",
        .{
            label,
            path,
            options.width,
            options.height,
            logicalRenderWidth(options),
            logicalRenderHeight(options),
            options.pixel_scale,
        },
    );
}

fn writeRenderArtifactMetadata(io: Io, allocator: std.mem.Allocator, path: []const u8, options: RenderCommandOptions) !void {
    const metadata_path = try renderArtifactMetadataPath(allocator, path);
    defer allocator.free(metadata_path);
    const metadata = try std.fmt.allocPrint(
        allocator,
        \\{{
        \\  "artifact": "{s}",
        \\  "physical_width": {d},
        \\  "physical_height": {d},
        \\  "logical_width": {d:.3},
        \\  "logical_height": {d:.3},
        \\  "pixel_scale": {d:.3}
        \\}}
        \\
    ,
        .{
            path,
            options.width,
            options.height,
            logicalRenderWidth(options),
            logicalRenderHeight(options),
            options.pixel_scale,
        },
    );
    defer allocator.free(metadata);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = metadata_path, .data = metadata });
}

fn expectedColorGroups(scene: scrapbot.Scene) usize {
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
