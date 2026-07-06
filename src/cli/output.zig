const std = @import("std");
const Io = std.Io;
const scrapbot = @import("scrapbot");
const cli_options = @import("options.zig");
const test_manifest = @import("test_manifest.zig");

const ArgumentError = cli_options.ArgumentError;
const BenchResult = cli_options.BenchResult;
const ExpectedFieldValue = test_manifest.ExpectedFieldValue;
const ExpectationEvaluation = test_manifest.ExpectationEvaluation;
const TestCaseStats = test_manifest.TestCaseStats;
const TestExpectation = test_manifest.TestExpectation;
const TestManifest = test_manifest.TestManifest;
const TestSuiteSummary = test_manifest.TestSuiteSummary;

pub fn evaluateExpectation(world: scrapbot.World, expectation: TestExpectation) ExpectationEvaluation {
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

pub fn printArgumentError(writer: *Io.Writer, err: ArgumentError) !void {
    const message = switch (err) {
        ArgumentError.InvalidDelta => "--dt expects a positive finite number",
        ArgumentError.InvalidFrames => "--frames expects a positive integer",
        ArgumentError.InvalidRenderSize => "--width and --height expect positive integer pixels",
        ArgumentError.InvalidPixelScale => "--pixel-scale expects a positive finite number",
        ArgumentError.InvalidFormat => "--format expects text or json",
        ArgumentError.HiddenRequiresFrames => "--hidden requires --frames",
        ArgumentError.MissingExpected => "visual-test expects an expected image path",
        ArgumentError.UnknownArgument => "unknown argument",
    };
    try writer.print("{s}\n", .{message});
}
pub fn printProjectError(writer: *Io.Writer, root_path: []const u8, err: anyerror) !void {
    try writer.print("{s}: {s}\n", .{ root_path, projectErrorMessage(err) });
}

pub fn projectErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        scrapbot.ProjectError.AlreadyExists => "project already exists",
        scrapbot.ProjectError.InvalidProject => "not a valid Scrapbot project",
        scrapbot.ProjectError.InvalidBuildOutput => "invalid build output path",
        scrapbot.ProjectError.MissingProjectFile => "missing project.toml",
        scrapbot.ProjectError.MissingDefaultScene => "missing default scene",
        scrapbot.ProjectError.UnsupportedProjectVersion => "unsupported project version",
        scrapbot.ProjectError.InvalidProjectName => "invalid project name",
        scrapbot.ProjectError.InvalidDefaultScene => "invalid default scene",
        scrapbot.ProjectError.InvalidSceneEntity => "invalid scene entity",
        scrapbot.ProjectError.DuplicateSceneEntityId => "duplicate scene entity id",
        scrapbot.ProjectError.InvalidSceneNumber => "invalid scene number",
        scrapbot.ProjectError.MissingSceneContent => "missing scene content",
        scrapbot.ProjectError.MissingScript => "missing script",
        scrapbot.ProjectError.InvalidScript => "invalid script",
        else => "unexpected project error",
    };
}

pub fn printScriptDiagnostic(writer: *Io.Writer, root_path: []const u8, diagnostic: scrapbot.ScriptDiagnostic) !void {
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

pub fn printStepOkText(writer: *Io.Writer, ok: scrapbot.StepOk) !void {
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

pub fn printBenchOkText(writer: *Io.Writer, result: BenchResult) !void {
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

pub fn printBuildOkText(writer: *Io.Writer, result: scrapbot.BuildResult) !void {
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

pub fn printStepFailureText(writer: *Io.Writer, root_path: []const u8, failure: scrapbot.StepRuntimeError) !void {
    try writer.print("{s}: step failed after {d}/{d} frames, dt: {d}\n", .{
        root_path,
        failure.summary.completed_frames,
        failure.summary.frames,
        failure.summary.delta_seconds,
    });
}

pub fn printExpectationFailureText(
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

pub fn printExpectedFieldValueText(writer: *Io.Writer, value: ExpectedFieldValue) !void {
    switch (value) {
        .boolean => |payload| try writer.writeAll(if (payload) "true" else "false"),
        .int => |payload| try writer.print("{d}", .{payload}),
        .float => |payload| try writer.print("{d}", .{payload}),
        .vec3 => |payload| try writer.print("[{d}, {d}, {d}]", .{ payload[0], payload[1], payload[2] }),
        .string => |payload| try writer.print("\"{s}\"", .{payload}),
    }
}

pub fn printComponentValueText(writer: *Io.Writer, value: scrapbot.ComponentValue) !void {
    switch (value) {
        .boolean => |payload| try writer.writeAll(if (payload) "true" else "false"),
        .int => |payload| try writer.print("{d}", .{payload}),
        .float => |payload| try writer.print("{d}", .{payload}),
        .vec3 => |payload| try writer.print("[{d}, {d}, {d}]", .{ payload[0], payload[1], payload[2] }),
        .string => |payload| try writer.print("\"{s}\"", .{payload}),
    }
}

pub fn printTestSummaryText(writer: *Io.Writer, summary: TestSuiteSummary) !void {
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

pub fn printTestSummaryJson(writer: *Io.Writer, summary: TestSuiteSummary) !void {
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

pub fn printTestCaseLoadFailureJson(
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

pub fn printTestCaseDiagnosticFailureJson(
    writer: *Io.Writer,
    name: []const u8,
    project_path: []const u8,
    diagnostic: scrapbot.ScriptDiagnostic,
) !void {
    try writer.writeAll("{\"name\":");
    try writeJsonString(writer, name);
    try writer.writeAll(",\"path\":");
    try writeJsonString(writer, project_path);
    try writer.writeAll(",\"ok\":false,\"diagnostic\":");
    try printScriptDiagnosticObjectJson(writer, project_path, diagnostic);
    try writer.writeAll("}");
}

pub fn printTestCaseRuntimeFailureJson(
    writer: *Io.Writer,
    name: []const u8,
    project_path: []const u8,
    failure: scrapbot.StepRuntimeError,
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

pub fn printTestCaseOkJson(
    writer: *Io.Writer,
    name: []const u8,
    project_path: []const u8,
    ok: scrapbot.StepOk,
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

pub fn printTestExpectationJson(
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

pub fn printExpectedFieldValueJson(writer: *Io.Writer, value: ExpectedFieldValue) !void {
    switch (value) {
        .boolean => |payload| try writer.writeAll(if (payload) "true" else "false"),
        .int => |payload| try writer.print("{d}", .{payload}),
        .float => |payload| try writer.print("{d}", .{payload}),
        .vec3 => |payload| try writer.print("[{d},{d},{d}]", .{ payload[0], payload[1], payload[2] }),
        .string => |payload| try writeJsonString(writer, payload),
    }
}

pub fn printComponentValueJson(writer: *Io.Writer, value: scrapbot.ComponentValue) !void {
    switch (value) {
        .boolean => |payload| try writer.writeAll(if (payload) "true" else "false"),
        .int => |payload| try writer.print("{d}", .{payload}),
        .float => |payload| try writer.print("{d}", .{payload}),
        .vec3 => |payload| try writer.print("[{d},{d},{d}]", .{ payload[0], payload[1], payload[2] }),
        .string => |payload| try writeJsonString(writer, payload),
    }
}

pub fn printCheckOkJson(writer: *Io.Writer, result: scrapbot.CheckResult) !void {
    try writer.writeAll("{\"ok\":true,\"project\":");
    try printProjectSummaryJson(writer, result.project);
    try writer.writeAll(",\"schedule\":");
    try printCheckScheduleJson(writer, result.schedule);
    try writer.writeAll("}\n");
}

pub fn printStepOkJson(writer: *Io.Writer, ok: scrapbot.StepOk) !void {
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

pub fn printStepFailureJson(writer: *Io.Writer, root_path: []const u8, failure: scrapbot.StepRuntimeError) !void {
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

pub fn printBenchOkJson(writer: *Io.Writer, result: BenchResult) !void {
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

pub fn printBuildOkJson(writer: *Io.Writer, result: scrapbot.BuildResult) !void {
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

pub fn printProjectSummaryJson(writer: *Io.Writer, project: scrapbot.Project) !void {
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

pub fn printSceneSummaryJson(writer: *Io.Writer, scene: scrapbot.Scene) !void {
    try writer.writeAll("{\"name\":");
    try writeJsonString(writer, scene.name);
    try writer.print(",\"entities\":{d},\"component_instances\":{d},\"renderable_cubes\":{d}}}", .{
        scene.entityCount(),
        scene.componentInstanceCount(),
        scene.renderableCubeCount(),
    });
}

pub fn printStepSummaryJson(writer: *Io.Writer, summary: scrapbot.StepSummary) !void {
    try writer.print("{{\"frames\":{d},\"completed_frames\":{d},\"dt\":{d}}}", .{
        summary.frames,
        summary.completed_frames,
        summary.delta_seconds,
    });
}

pub fn printCheckScheduleJson(writer: *Io.Writer, schedule: scrapbot.CheckSchedule) !void {
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

pub fn printCheckSystemJson(writer: *Io.Writer, system: scrapbot.CheckSystemSummary) !void {
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

pub fn writeJsonStringList(writer: *Io.Writer, values: []const []const u8) !void {
    try writer.writeByte('[');
    for (values, 0..) |value, index| {
        if (index != 0) {
            try writer.writeByte(',');
        }
        try writeJsonString(writer, value);
    }
    try writer.writeByte(']');
}

pub fn printProjectErrorJson(writer: *Io.Writer, root_path: []const u8, err: anyerror) !void {
    try writer.writeAll("{\"ok\":false,\"error\":");
    try writeJsonString(writer, @errorName(err));
    try writer.writeAll(",\"root\":");
    try writeJsonString(writer, root_path);
    try writer.writeAll(",\"message\":");
    try writeJsonString(writer, projectErrorMessage(err));
    try writer.writeAll("}\n");
}

pub fn printScriptDiagnosticJson(writer: *Io.Writer, root_path: []const u8, diagnostic: scrapbot.ScriptDiagnostic) !void {
    try writer.writeAll("{\"ok\":false,\"diagnostic\":");
    try printScriptDiagnosticObjectJson(writer, root_path, diagnostic);
    try writer.writeAll("}\n");
}

pub fn printScriptDiagnosticObjectJson(writer: *Io.Writer, root_path: []const u8, diagnostic: scrapbot.ScriptDiagnostic) !void {
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

pub fn printDiagnosticPositionJson(writer: *Io.Writer, position: scrapbot.ScriptDiagnosticPosition) !void {
    try writer.print("{{\"line\":{d}", .{position.line});
    if (position.column) |column| {
        try writer.print(",\"column\":{d}", .{column});
    }
    try writer.writeAll("}");
}

pub fn writeJsonString(writer: *Io.Writer, value: []const u8) !void {
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
