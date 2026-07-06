const main = @import("script/main.zig");

pub const system_profile_window_frames = main.system_profile_window_frames;
pub const ScriptError = main.ScriptError;
pub const DiagnosticStage = main.DiagnosticStage;
pub const Diagnostic = main.Diagnostic;
pub const DiagnosticPosition = main.DiagnosticPosition;
pub const LoadResult = main.LoadResult;
pub const NativeSystemContext = main.NativeSystemContext;
pub const NativeSystemFn = main.NativeSystemFn;
pub const NativeSystemRegistration = main.NativeSystemRegistration;
pub const PlatformDynLib = main.PlatformDynLib;
pub const NativeLibrary = main.NativeLibrary;
pub const NativeExtension = main.NativeExtension;
pub const Program = main.Program;
pub const LoadDetailedResult = main.LoadDetailedResult;
pub const loadProjectProgram = main.loadProjectProgram;
pub const loadProjectProgramDetailed = main.loadProjectProgramDetailed;
pub const loadProjectProgramDetailedWithNative = main.loadProjectProgramDetailedWithNative;
pub const loadSourceProgram = main.loadSourceProgram;
pub const loadSourceProgramWithNative = main.loadSourceProgramWithNative;
pub const buildRuntimeSchedule = main.buildRuntimeSchedule;

test {
    _ = main;
}
