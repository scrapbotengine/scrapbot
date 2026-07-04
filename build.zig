const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const window_platform = WindowPlatformConfig{
        .sdl_include_path = b.option([]const u8, "sdl3_include_path", "Path containing the SDL3 include directory"),
        .sdl_library_path = b.option([]const u8, "sdl3_library_path", "Path containing the SDL3 library"),
    };

    const wgpu_dep = b.dependency("wgpu_native_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "zig_exe", b.graph.zig_exe);

    const machina_mod = b.addModule("machina", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wgpu", .module = wgpu_dep.module("wgpu") },
        },
    });
    machina_mod.addOptions("build_options", build_options);
    linkLuau(b, machina_mod, target);
    addSdlBridge(b, machina_mod, target);

    const exe = b.addExecutable(.{
        .name = "machina",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "machina", .module = machina_mod },
            },
        }),
    });
    configureCompileArtifact(exe, target);
    linkWgpuPlatform(exe, target);
    linkWindowPlatform(exe, target, window_platform);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run machina");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{
        .root_module = machina_mod,
    });
    configureCompileArtifact(mod_tests, target);
    linkWgpuPlatform(mod_tests, target);
    linkWindowPlatform(mod_tests, target, window_platform);
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    configureCompileArtifact(exe_tests, target);
    linkWgpuPlatform(exe_tests, target);
    linkWindowPlatform(exe_tests, target, window_platform);
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

fn configureCompileArtifact(compile: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    if (target.result.os.tag == .windows and target.result.abi == .msvc) {
        compile.bundle_compiler_rt = false;
        compile.bundle_ubsan_rt = false;
    }
}

fn linkLuau(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    module.addIncludePath(b.path("src"));
    module.addIncludePath(b.path("third_party/luau/Common/include"));
    module.addIncludePath(b.path("third_party/luau/Ast/include"));
    module.addIncludePath(b.path("third_party/luau/Bytecode/include"));
    module.addIncludePath(b.path("third_party/luau/Compiler/include"));
    module.addIncludePath(b.path("third_party/luau/VM/include"));
    module.linkSystemLibrary("c", .{});
    if (target.result.os.tag == .windows and target.result.abi == .msvc) {
        module.linkSystemLibrary("msvcprt", .{});
    } else {
        module.linkSystemLibrary("c++", .{});
    }
    module.addCSourceFiles(.{
        .root = b.path(""),
        .language = .cpp,
        .flags = &.{"-std=c++17"},
        .files = &.{
            "src/luau_bridge.cpp",

            "third_party/luau/Common/src/BytecodeWire.cpp",
            "third_party/luau/Common/src/StringUtils.cpp",
            "third_party/luau/Common/src/TimeTrace.cpp",

            "third_party/luau/Ast/src/Allocator.cpp",
            "third_party/luau/Ast/src/Ast.cpp",
            "third_party/luau/Ast/src/Confusables.cpp",
            "third_party/luau/Ast/src/Cst.cpp",
            "third_party/luau/Ast/src/Lexer.cpp",
            "third_party/luau/Ast/src/Location.cpp",
            "third_party/luau/Ast/src/Parser.cpp",
            "third_party/luau/Ast/src/PrettyPrinter.cpp",

            "third_party/luau/Bytecode/src/BytecodeBuilder.cpp",
            "third_party/luau/Bytecode/src/BytecodeGraph.cpp",

            "third_party/luau/Compiler/src/Compiler.cpp",
            "third_party/luau/Compiler/src/Builtins.cpp",
            "third_party/luau/Compiler/src/BuiltinFolding.cpp",
            "third_party/luau/Compiler/src/ConstantFolding.cpp",
            "third_party/luau/Compiler/src/CostModel.cpp",
            "third_party/luau/Compiler/src/TableShape.cpp",
            "third_party/luau/Compiler/src/Types.cpp",
            "third_party/luau/Compiler/src/ValueTracking.cpp",
            "third_party/luau/Compiler/src/lcode.cpp",

            "third_party/luau/VM/src/lapi.cpp",
            "third_party/luau/VM/src/laux.cpp",
            "third_party/luau/VM/src/lbaselib.cpp",
            "third_party/luau/VM/src/lbitlib.cpp",
            "third_party/luau/VM/src/lbuffer.cpp",
            "third_party/luau/VM/src/lbuflib.cpp",
            "third_party/luau/VM/src/lbuiltins.cpp",
            "third_party/luau/VM/src/lcorolib.cpp",
            "third_party/luau/VM/src/ldblib.cpp",
            "third_party/luau/VM/src/ldebug.cpp",
            "third_party/luau/VM/src/ldo.cpp",
            "third_party/luau/VM/src/lfunc.cpp",
            "third_party/luau/VM/src/lgc.cpp",
            "third_party/luau/VM/src/lgcdebug.cpp",
            "third_party/luau/VM/src/linit.cpp",
            "third_party/luau/VM/src/lmathlib.cpp",
            "third_party/luau/VM/src/lmem.cpp",
            "third_party/luau/VM/src/lnumprint.cpp",
            "third_party/luau/VM/src/lobject.cpp",
            "third_party/luau/VM/src/loslib.cpp",
            "third_party/luau/VM/src/lperf.cpp",
            "third_party/luau/VM/src/lstate.cpp",
            "third_party/luau/VM/src/lstring.cpp",
            "third_party/luau/VM/src/lstrlib.cpp",
            "third_party/luau/VM/src/ltable.cpp",
            "third_party/luau/VM/src/ltablib.cpp",
            "third_party/luau/VM/src/ltm.cpp",
            "third_party/luau/VM/src/ludata.cpp",
            "third_party/luau/VM/src/lutf8lib.cpp",
            "third_party/luau/VM/src/lveclib.cpp",
            "third_party/luau/VM/src/lintlib.cpp",
            "third_party/luau/VM/src/lvmexecute.cpp",
            "third_party/luau/VM/src/lclass.cpp",
            "third_party/luau/VM/src/lclasslib.cpp",
            "third_party/luau/VM/src/lvmload.cpp",
            "third_party/luau/VM/src/lvmutils.cpp",
        },
    });
}

fn linkWgpuPlatform(compile: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    if (target.result.os.tag == .macos or target.result.os.tag == .ios) {
        compile.root_module.linkFramework("Foundation", .{});
        compile.root_module.linkFramework("QuartzCore", .{});
        compile.root_module.linkFramework("Metal", .{});
    }
}

fn addSdlBridge(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .macos, .linux, .windows => module.addCSourceFiles(.{
            .root = b.path(""),
            .language = .c,
            .flags = &.{"-std=c11"},
            .files = &.{"src/sdl_bridge.c"},
        }),
        else => {},
    }
}

const WindowPlatformConfig = struct {
    sdl_include_path: ?[]const u8 = null,
    sdl_library_path: ?[]const u8 = null,
};

fn linkWindowPlatform(compile: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, config: WindowPlatformConfig) void {
    if (config.sdl_include_path) |path| {
        compile.root_module.addIncludePath(.{ .cwd_relative = path });
    }
    if (config.sdl_library_path) |path| {
        compile.root_module.addLibraryPath(.{ .cwd_relative = path });
    }

    switch (target.result.os.tag) {
        .macos => {
            if (config.sdl_include_path == null) {
                compile.root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
            }
            if (config.sdl_library_path == null) {
                compile.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
            }
            compile.root_module.linkSystemLibrary("SDL3", .{});
        },
        .linux, .windows => {
            compile.root_module.linkSystemLibrary("SDL3", .{});
        },
        else => {},
    }
}
