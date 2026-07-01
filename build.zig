const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wgpu_dep = b.dependency("wgpu_native_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const machina_mod = b.addModule("machina", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wgpu", .module = wgpu_dep.module("wgpu") },
        },
    });

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
    linkWgpuPlatform(exe, target);

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
    linkWgpuPlatform(mod_tests, target);
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    linkWgpuPlatform(exe_tests, target);
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

fn linkWgpuPlatform(compile: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    if (target.result.os.tag == .macos or target.result.os.tag == .ios) {
        compile.root_module.linkFramework("Foundation", .{});
        compile.root_module.linkFramework("QuartzCore", .{});
        compile.root_module.linkFramework("Metal", .{});
    }
}
