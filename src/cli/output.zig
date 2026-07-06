const std = @import("std");
const Io = std.Io;
const scrapbot = @import("scrapbot");
const cli_expectations = @import("expectations.zig");
const cli_options = @import("options.zig");
const output_json = @import("output_json.zig");
const test_manifest = @import("test_manifest.zig");

const ArgumentError = cli_options.ArgumentError;
const BenchResult = cli_options.BenchResult;
const ExpectedFieldValue = test_manifest.ExpectedFieldValue;
const ExpectationEvaluation = test_manifest.ExpectationEvaluation;
const TestExpectation = test_manifest.TestExpectation;
const TestSuiteSummary = test_manifest.TestSuiteSummary;

pub const evaluateExpectation = cli_expectations.evaluate;

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

pub const printTestSummaryJson = output_json.printTestSummaryJson;
pub const printTestCaseLoadFailureJson = output_json.printTestCaseLoadFailureJson;
pub const printTestCaseDiagnosticFailureJson = output_json.printTestCaseDiagnosticFailureJson;
pub const printTestCaseRuntimeFailureJson = output_json.printTestCaseRuntimeFailureJson;
pub const printTestCaseOkJson = output_json.printTestCaseOkJson;
pub const printTestExpectationJson = output_json.printTestExpectationJson;
pub const printExpectedFieldValueJson = output_json.printExpectedFieldValueJson;
pub const printComponentValueJson = output_json.printComponentValueJson;
pub const printCheckOkJson = output_json.printCheckOkJson;
pub const printStepOkJson = output_json.printStepOkJson;
pub const printStepFailureJson = output_json.printStepFailureJson;
pub const printBenchOkJson = output_json.printBenchOkJson;
pub const printBuildOkJson = output_json.printBuildOkJson;
pub const printProjectSummaryJson = output_json.printProjectSummaryJson;
pub const printSceneSummaryJson = output_json.printSceneSummaryJson;
pub const printStepSummaryJson = output_json.printStepSummaryJson;
pub const printCheckScheduleJson = output_json.printCheckScheduleJson;
pub const printCheckSystemJson = output_json.printCheckSystemJson;
pub const writeJsonStringList = output_json.writeJsonStringList;
pub const printTestDiscoveryFailureJson = output_json.printTestDiscoveryFailureJson;
pub const printNoTestProjectsJson = output_json.printNoTestProjectsJson;
pub const printTestSuiteStartJson = output_json.printTestSuiteStartJson;
pub const printTestSuiteSeparatorJson = output_json.printTestSuiteSeparatorJson;
pub const printTestSuiteEndJson = output_json.printTestSuiteEndJson;
pub const printScriptDiagnosticJson = output_json.printScriptDiagnosticJson;
pub const printScriptDiagnosticObjectJson = output_json.printScriptDiagnosticObjectJson;
pub const printDiagnosticPositionJson = output_json.printDiagnosticPositionJson;
pub const writeJsonString = output_json.writeJsonString;

pub fn printProjectErrorJson(writer: *Io.Writer, root_path: []const u8, err: anyerror) !void {
    try output_json.printProjectErrorJson(writer, root_path, err, projectErrorMessage(err));
}
