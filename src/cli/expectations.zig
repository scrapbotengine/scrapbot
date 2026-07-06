const scrapbot = @import("scrapbot");
const test_manifest = @import("test_manifest.zig");

const ExpectationEvaluation = test_manifest.ExpectationEvaluation;
const TestExpectation = test_manifest.TestExpectation;

pub fn evaluate(world: scrapbot.World, expectation: TestExpectation) ExpectationEvaluation {
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
