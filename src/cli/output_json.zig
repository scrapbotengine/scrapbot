const std = @import("std");
const Io = std.Io;
const scrapbot = @import("scrapbot");
const cli_expectations = @import("expectations.zig");
const cli_options = @import("options.zig");
const test_manifest = @import("test_manifest.zig");

const BenchResult = cli_options.BenchResult;
const ExpectedFieldValue = test_manifest.ExpectedFieldValue;
const ExpectationEvaluation = test_manifest.ExpectationEvaluation;
const TestCaseStats = test_manifest.TestCaseStats;
const TestExpectation = test_manifest.TestExpectation;
const TestManifest = test_manifest.TestManifest;
const TestSuiteSummary = test_manifest.TestSuiteSummary;
const JsonWriter = std.json.Stringify;

fn jsonWriter(writer: *Io.Writer) JsonWriter {
    return .{ .writer = writer };
}

fn writeField(jw: *JsonWriter, name: []const u8, value: anytype) !void {
    try jw.objectField(name);
    try jw.write(value);
}

fn writeFloatField(jw: *JsonWriter, name: []const u8, value: anytype) !void {
    try jw.objectField(name);
    try jw.print("{d}", .{value});
}

pub fn printTestSummaryJson(writer: *Io.Writer, summary: TestSuiteSummary) !void {
    var jw = jsonWriter(writer);
    try writeTestSummaryJson(&jw, summary);
}

pub fn printTestSuiteStartJson(writer: *Io.Writer) !void {
    try writer.writeAll("{\"tests\":[");
}

pub fn printTestSuiteSeparatorJson(writer: *Io.Writer) !void {
    try writer.writeByte(',');
}

pub fn printTestSuiteEndJson(writer: *Io.Writer, summary: TestSuiteSummary) !void {
    try writer.writeAll("],\"summary\":");
    try printTestSummaryJson(writer, summary);
    try writer.writeAll(",\"ok\":");
    var jw = jsonWriter(writer);
    try jw.write(summary.failed_cases == 0);
    try writer.writeAll("}\n");
}

pub fn printTestCaseLoadFailureJson(
    writer: *Io.Writer,
    name: []const u8,
    project_path: []const u8,
    stage: []const u8,
    err: anyerror,
) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "name", name);
    try writeField(&jw, "path", project_path);
    try writeField(&jw, "ok", false);
    try writeField(&jw, "stage", stage);
    try writeField(&jw, "error", @errorName(err));
    try jw.endObject();
}

pub fn printTestCaseDiagnosticFailureJson(
    writer: *Io.Writer,
    name: []const u8,
    project_path: []const u8,
    diagnostic: scrapbot.ScriptDiagnostic,
) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "name", name);
    try writeField(&jw, "path", project_path);
    try writeField(&jw, "ok", false);
    try jw.objectField("diagnostic");
    try writeScriptDiagnosticObjectJson(&jw, project_path, diagnostic);
    try jw.endObject();
}

pub fn printTestCaseRuntimeFailureJson(
    writer: *Io.Writer,
    name: []const u8,
    project_path: []const u8,
    failure: scrapbot.StepRuntimeError,
) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "name", name);
    try writeField(&jw, "path", project_path);
    try writeField(&jw, "ok", false);
    try jw.objectField("simulation");
    try writeStepSummaryJson(&jw, failure.summary);
    try jw.objectField("diagnostic");
    try writeScriptDiagnosticObjectJson(&jw, project_path, failure.diagnostic);
    try jw.endObject();
}

pub fn printTestCaseOkJson(
    writer: *Io.Writer,
    name: []const u8,
    project_path: []const u8,
    ok: scrapbot.StepOk,
    manifest: TestManifest,
    stats: *TestCaseStats,
) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "name", name);
    try writeField(&jw, "path", project_path);
    try jw.objectField("simulation");
    try writeStepSummaryJson(&jw, ok.summary);
    try jw.objectField("assertions");
    try jw.beginArray();
    for (manifest.expectations) |expectation| {
        const evaluation = cli_expectations.evaluate(ok.scene.world, expectation);
        if (!evaluation.passed) {
            stats.failed_assertions += 1;
        }
        try writeTestExpectationJson(&jw, expectation, evaluation);
    }
    try jw.endArray();
    try writeField(&jw, "failed_assertions", stats.failed_assertions);
    try writeField(&jw, "ok", stats.failed_assertions == 0);
    try jw.endObject();
}

pub fn printTestExpectationJson(
    writer: *Io.Writer,
    expectation: TestExpectation,
    evaluation: ExpectationEvaluation,
) !void {
    var jw = jsonWriter(writer);
    try writeTestExpectationJson(&jw, expectation, evaluation);
}

pub fn printExpectedFieldValueJson(writer: *Io.Writer, value: ExpectedFieldValue) !void {
    var jw = jsonWriter(writer);
    try writeExpectedFieldValueJson(&jw, value);
}

pub fn printComponentValueJson(writer: *Io.Writer, value: scrapbot.ComponentValue) !void {
    var jw = jsonWriter(writer);
    try writeComponentValueJson(&jw, value);
}

pub fn printCheckOkJson(writer: *Io.Writer, result: scrapbot.CheckResult) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "ok", true);
    try jw.objectField("project");
    try writeProjectSummaryJson(&jw, result.project);
    try jw.objectField("schedule");
    try writeCheckScheduleJson(&jw, result.schedule);
    try jw.endObject();
    try writer.writeByte('\n');
}

pub fn printStepOkJson(writer: *Io.Writer, ok: scrapbot.StepOk) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "ok", true);
    try jw.objectField("project");
    try writeProjectSummaryJson(&jw, ok.project);
    try jw.objectField("scene");
    try writeSceneSummaryJson(&jw, ok.scene);
    try jw.objectField("simulation");
    try writeStepSummaryJson(&jw, ok.summary);
    try jw.objectField("schedule");
    try writeCheckScheduleJson(&jw, ok.schedule);
    try jw.endObject();
    try writer.writeByte('\n');
}

pub fn printStepFailureJson(writer: *Io.Writer, root_path: []const u8, failure: scrapbot.StepRuntimeError) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "ok", false);
    try jw.objectField("project");
    try writeProjectSummaryJson(&jw, failure.project);
    try jw.objectField("scene");
    try writeSceneSummaryJson(&jw, failure.scene);
    try jw.objectField("simulation");
    try writeStepSummaryJson(&jw, failure.summary);
    try jw.objectField("schedule");
    try writeCheckScheduleJson(&jw, failure.schedule);
    try jw.objectField("diagnostic");
    try writeScriptDiagnosticObjectJson(&jw, root_path, failure.diagnostic);
    try jw.endObject();
    try writer.writeByte('\n');
}

pub fn printBenchOkJson(writer: *Io.Writer, result: BenchResult) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "ok", true);
    try jw.objectField("project");
    try jw.beginObject();
    try writeField(&jw, "name", result.project_name);
    try jw.endObject();
    try jw.objectField("scene");
    try jw.beginObject();
    try writeField(&jw, "name", result.scene_name);
    try writeField(&jw, "entities", result.entity_count);
    try writeField(&jw, "component_instances", result.component_instance_count);
    try writeField(&jw, "renderables", result.renderable_count);
    try writeField(&jw, "render_batches", result.render_batch_count);
    try writeField(&jw, "ui_rects", result.ui_rect_count);
    try writeField(&jw, "ui_texts", result.ui_text_count);
    try jw.endObject();
    try jw.objectField("benchmark");
    try jw.beginObject();
    try writeField(&jw, "frames", result.frames);
    try writeFloatField(&jw, "dt", result.delta_seconds);
    try writeField(&jw, "startup_ns", result.startup_ns);
    try writeField(&jw, "update_ns", result.update_ns);
    try writeField(&jw, "ns_per_frame", result.nsPerFrame());
    try jw.endObject();
    try jw.endObject();
    try writer.writeByte('\n');
}

pub fn printBuildOkJson(writer: *Io.Writer, result: scrapbot.BuildResult) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "ok", true);
    try writeField(&jw, "project", result.project_name);
    try writeField(&jw, "bundle", result.bundle_path);
    try writeField(&jw, "project_path", result.project_path);
    try writeField(&jw, "runtime", result.runtime_path);
    try writeField(&jw, "launcher", result.launcher_path);
    try writeField(&jw, "native_artifact", result.native_artifact);
    try writeField(&jw, "sdl3_bundled", result.sdl3_bundled);
    try writeField(&jw, "sdl3_warning", result.sdl3_warning);
    try jw.endObject();
    try writer.writeByte('\n');
}

pub fn printProjectSummaryJson(writer: *Io.Writer, project: scrapbot.Project) !void {
    var jw = jsonWriter(writer);
    try writeProjectSummaryJson(&jw, project);
}

pub fn printSceneSummaryJson(writer: *Io.Writer, scene: scrapbot.Scene) !void {
    var jw = jsonWriter(writer);
    try writeSceneSummaryJson(&jw, scene);
}

pub fn printStepSummaryJson(writer: *Io.Writer, summary: scrapbot.StepSummary) !void {
    var jw = jsonWriter(writer);
    try writeStepSummaryJson(&jw, summary);
}

pub fn printCheckScheduleJson(writer: *Io.Writer, schedule: scrapbot.CheckSchedule) !void {
    var jw = jsonWriter(writer);
    try writeCheckScheduleJson(&jw, schedule);
}

pub fn printCheckSystemJson(writer: *Io.Writer, system: scrapbot.CheckSystemSummary) !void {
    var jw = jsonWriter(writer);
    try writeCheckSystemJson(&jw, system);
}

pub fn writeJsonStringList(writer: *Io.Writer, values: []const []const u8) !void {
    var jw = jsonWriter(writer);
    try writeStringList(&jw, values);
}

pub fn printProjectErrorJson(writer: *Io.Writer, root_path: []const u8, err: anyerror, message: []const u8) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "ok", false);
    try writeField(&jw, "error", @errorName(err));
    try writeField(&jw, "root", root_path);
    try writeField(&jw, "message", message);
    try jw.endObject();
    try writer.writeByte('\n');
}

pub fn printTestDiscoveryFailureJson(writer: *Io.Writer, root_path: []const u8, err: anyerror) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "ok", false);
    try writeField(&jw, "error", @errorName(err));
    try writeField(&jw, "root", root_path);
    try jw.endObject();
    try writer.writeByte('\n');
}

pub fn printNoTestProjectsJson(writer: *Io.Writer, root_path: []const u8) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "ok", false);
    try writeField(&jw, "error", "NoTestProjects");
    try writeField(&jw, "root", root_path);
    try jw.endObject();
    try writer.writeByte('\n');
}

pub fn printScriptDiagnosticJson(writer: *Io.Writer, root_path: []const u8, diagnostic: scrapbot.ScriptDiagnostic) !void {
    var jw = jsonWriter(writer);
    try jw.beginObject();
    try writeField(&jw, "ok", false);
    try jw.objectField("diagnostic");
    try writeScriptDiagnosticObjectJson(&jw, root_path, diagnostic);
    try jw.endObject();
    try writer.writeByte('\n');
}

pub fn printScriptDiagnosticObjectJson(writer: *Io.Writer, root_path: []const u8, diagnostic: scrapbot.ScriptDiagnostic) !void {
    var jw = jsonWriter(writer);
    try writeScriptDiagnosticObjectJson(&jw, root_path, diagnostic);
}

pub fn printDiagnosticPositionJson(writer: *Io.Writer, position: scrapbot.ScriptDiagnosticPosition) !void {
    var jw = jsonWriter(writer);
    try writeDiagnosticPositionJson(&jw, position);
}

pub fn writeJsonString(writer: *Io.Writer, value: []const u8) !void {
    var jw = jsonWriter(writer);
    try jw.write(value);
}

fn writeTestSummaryJson(jw: *JsonWriter, summary: TestSuiteSummary) !void {
    try jw.beginObject();
    try writeField(jw, "cases", summary.cases);
    try writeField(jw, "passed", summary.passed_cases);
    try writeField(jw, "failed", summary.failed_cases);
    try writeField(jw, "assertions", summary.assertions);
    try writeField(jw, "failed_assertions", summary.failed_assertions);
    try jw.endObject();
}

fn writeTestExpectationJson(jw: *JsonWriter, expectation: TestExpectation, evaluation: ExpectationEvaluation) !void {
    try jw.beginObject();
    try writeField(jw, "entity", expectation.entity);
    try writeField(jw, "component", expectation.component);
    try writeField(jw, "field", expectation.field);
    try jw.objectField("expected");
    try writeExpectedFieldValueJson(jw, expectation.expected);
    try writeField(jw, "ok", evaluation.passed);
    if (evaluation.actual) |actual| {
        try jw.objectField("actual");
        try writeComponentValueJson(jw, actual);
    } else if (evaluation.err) |err| {
        try writeField(jw, "error", @errorName(err));
    }
    try jw.endObject();
}

fn writeExpectedFieldValueJson(jw: *JsonWriter, value: ExpectedFieldValue) !void {
    switch (value) {
        .boolean => |payload| try jw.write(payload),
        .int => |payload| try jw.write(payload),
        .float => |payload| try jw.print("{d}", .{payload}),
        .vec3 => |payload| try writeFloatArray3(jw, payload),
        .string => |payload| try jw.write(payload),
    }
}

fn writeComponentValueJson(jw: *JsonWriter, value: scrapbot.ComponentValue) !void {
    switch (value) {
        .boolean => |payload| try jw.write(payload),
        .int => |payload| try jw.write(payload),
        .float => |payload| try jw.print("{d}", .{payload}),
        .vec3 => |payload| try writeFloatArray3(jw, payload),
        .string => |payload| try jw.write(payload),
    }
}

fn writeFloatArray3(jw: *JsonWriter, values: [3]f32) !void {
    try jw.beginArray();
    try jw.print("{d}", .{values[0]});
    try jw.print("{d}", .{values[1]});
    try jw.print("{d}", .{values[2]});
    try jw.endArray();
}

fn writeProjectSummaryJson(jw: *JsonWriter, project: scrapbot.Project) !void {
    try jw.beginObject();
    try writeField(jw, "name", project.name);
    try writeField(jw, "default_scene", project.default_scene);
    try writeField(jw, "scripts", project.scripts.len);
    if (project.native) |native_path| {
        try writeField(jw, "native", native_path);
    }
    if (project.native_artifact) |native_artifact_path| {
        try writeField(jw, "native_artifact", native_artifact_path);
    }
    try jw.endObject();
}

fn writeSceneSummaryJson(jw: *JsonWriter, scene: scrapbot.Scene) !void {
    try jw.beginObject();
    try writeField(jw, "name", scene.name);
    try writeField(jw, "entities", scene.entityCount());
    try writeField(jw, "component_instances", scene.componentInstanceCount());
    try writeField(jw, "renderable_cubes", scene.renderableCubeCount());
    try jw.endObject();
}

fn writeStepSummaryJson(jw: *JsonWriter, summary: scrapbot.StepSummary) !void {
    try jw.beginObject();
    try writeField(jw, "frames", summary.frames);
    try writeField(jw, "completed_frames", summary.completed_frames);
    try writeFloatField(jw, "dt", summary.delta_seconds);
    try jw.endObject();
}

fn writeCheckScheduleJson(jw: *JsonWriter, schedule: scrapbot.CheckSchedule) !void {
    try jw.beginObject();
    try jw.objectField("batches");
    try jw.beginArray();
    for (schedule.batches) |batch| {
        try jw.beginObject();
        try writeField(jw, "phase", @tagName(batch.phase));
        try jw.objectField("systems");
        try jw.beginArray();
        for (batch.systems) |system| {
            try writeCheckSystemJson(jw, system);
        }
        try jw.endArray();
        try jw.endObject();
    }
    try jw.endArray();
    try jw.endObject();
}

fn writeCheckSystemJson(jw: *JsonWriter, system: scrapbot.CheckSystemSummary) !void {
    try jw.beginObject();
    try writeField(jw, "id", system.id);
    try writeField(jw, "phase", @tagName(system.phase));
    try writeField(jw, "runner", @tagName(system.runner));
    try jw.objectField("reads");
    try writeStringList(jw, system.reads);
    try jw.objectField("writes");
    try writeStringList(jw, system.writes);
    try jw.objectField("before");
    try writeStringList(jw, system.before);
    try jw.objectField("after");
    try writeStringList(jw, system.after);
    try jw.endObject();
}

fn writeStringList(jw: *JsonWriter, values: []const []const u8) !void {
    try jw.beginArray();
    for (values) |value| {
        try jw.write(value);
    }
    try jw.endArray();
}

fn writeScriptDiagnosticObjectJson(jw: *JsonWriter, root_path: []const u8, diagnostic: scrapbot.ScriptDiagnostic) !void {
    try jw.beginObject();
    try writeField(jw, "stage", @tagName(diagnostic.stage));
    try writeField(jw, "root", root_path);
    if (diagnostic.path) |path| {
        try writeField(jw, "path", path);
    }
    if (diagnostic.system_id) |system_id| {
        try writeField(jw, "system_id", system_id);
    }
    if (diagnostic.start) |start| {
        try jw.objectField("start");
        try writeDiagnosticPositionJson(jw, start);
    }
    if (diagnostic.end) |end| {
        try jw.objectField("end");
        try writeDiagnosticPositionJson(jw, end);
    }
    try writeField(jw, "message", diagnostic.message);
    try jw.endObject();
}

fn writeDiagnosticPositionJson(jw: *JsonWriter, position: scrapbot.ScriptDiagnosticPosition) !void {
    try jw.beginObject();
    try writeField(jw, "line", position.line);
    if (position.column) |column| {
        try writeField(jw, "column", column);
    }
    try jw.endObject();
}
