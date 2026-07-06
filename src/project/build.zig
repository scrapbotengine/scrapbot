const std = @import("std");
const builtin = @import("builtin");
const native = @import("../native.zig");

const Io = std.Io;

pub const default_output_dir_name = "build";
pub const bundle_marker = ".scrapbot-build-bundle";
pub const project_dir = "project";
pub const bin_dir = "bin";
pub const lib_dir = "lib";
pub const manifest_path = "scrapbot-build.json";
pub const native_artifact_dir = ".scrapbot/build/native";

pub fn defaultBuildBundleName(allocator: std.mem.Allocator, project_name: []const u8) ![]u8 {
    const sanitized = try sanitizeBundleSegment(allocator, project_name);
    defer allocator.free(sanitized);
    return std.fmt.allocPrint(allocator, "{s}-{s}", .{ sanitized, hostTriple() });
}

pub fn buildNativeArtifactProjectPath(allocator: std.mem.Allocator) ![]u8 {
    return std.mem.join(allocator, "/", &.{ native_artifact_dir, native.dynamicLibraryFileName() });
}

fn sanitizeBundleSegment(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var last_dash = false;
    for (value) |byte| {
        const next = if (std.ascii.isAlphanumeric(byte))
            std.ascii.toLower(byte)
        else if (byte == '.' or byte == '_')
            byte
        else
            '-';
        if (next == '-') {
            if (last_dash) {
                continue;
            }
            last_dash = true;
        } else {
            last_dash = false;
        }
        try out.append(allocator, next);
    }

    while (out.items.len > 0 and out.items[out.items.len - 1] == '-') {
        _ = out.pop();
    }
    while (out.items.len > 0 and out.items[0] == '-') {
        _ = out.orderedRemove(0);
    }
    if (out.items.len == 0) {
        try out.appendSlice(allocator, "scrapbot-project");
    }
    return out.toOwnedSlice(allocator);
}

fn hostTriple() []const u8 {
    return switch (builtin.os.tag) {
        .windows => switch (builtin.abi) {
            .msvc => switch (builtin.cpu.arch) {
                .x86_64 => "x86_64-windows-msvc",
                .aarch64 => "aarch64-windows-msvc",
                else => "windows-msvc",
            },
            else => switch (builtin.cpu.arch) {
                .x86_64 => "x86_64-windows-gnu",
                else => "windows",
            },
        },
        else => switch (builtin.cpu.arch) {
            .aarch64 => switch (builtin.os.tag) {
                .macos => "aarch64-macos",
                .linux => "aarch64-linux",
                else => "aarch64",
            },
            .x86_64 => switch (builtin.os.tag) {
                .macos => "x86_64-macos",
                .linux => "x86_64-linux",
                else => "x86_64",
            },
            else => @tagName(builtin.os.tag),
        },
    };
}

pub fn isSafeBundleName(name: []const u8) bool {
    if (name.len == 0 or std.fs.path.isAbsolute(name) or std.mem.indexOfScalar(u8, name, '/') != null or std.mem.indexOfScalar(u8, name, '\\') != null) {
        return false;
    }
    return !std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..");
}

pub fn isScrapbotBuildBundle(io: Io, cwd: Io.Dir, bundle_path: []const u8) bool {
    const marker_path = std.fs.path.join(std.heap.smp_allocator, &.{ bundle_path, bundle_marker }) catch return false;
    defer std.heap.smp_allocator.free(marker_path);
    return fileExists(io, cwd, marker_path);
}

pub fn absoluteCwdPath(allocator: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.path.resolve(allocator, &.{path});
    }
    const cwd_path = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd_path);
    return std.fs.path.resolve(allocator, &.{ cwd_path, path });
}

pub fn outputRootEntryToSkip(
    allocator: std.mem.Allocator,
    io: Io,
    project_root_path: []const u8,
    output_root: []const u8,
    bundle_path: []const u8,
) !?[]u8 {
    const project_abs = try absoluteCwdPath(allocator, io, project_root_path);
    defer allocator.free(project_abs);
    const output_abs = try absoluteCwdPath(allocator, io, output_root);
    defer allocator.free(output_abs);
    const bundle_abs = try absoluteCwdPath(allocator, io, bundle_path);
    defer allocator.free(bundle_abs);

    const project_clean = trimTrailingPathSeparators(project_abs);
    const output_clean = trimTrailingPathSeparators(output_abs);
    const bundle_clean = trimTrailingPathSeparators(bundle_abs);

    if (!pathIsInside(bundle_clean, project_clean)) {
        return null;
    }

    if (pathsEqual(output_clean, project_clean)) {
        const bundle_inside_project = bundle_clean[project_clean.len + 1 ..];
        const first_separator = std.mem.indexOfAny(u8, bundle_inside_project, "/\\") orelse bundle_inside_project.len;
        if (first_separator == 0) {
            return null;
        }
        return try allocator.dupe(u8, bundle_inside_project[0..first_separator]);
    }

    if (!pathIsInside(output_clean, project_clean)) {
        return null;
    }

    const inside_project = output_clean[project_clean.len + 1 ..];
    const first_separator = std.mem.indexOfAny(u8, inside_project, "/\\") orelse inside_project.len;
    if (first_separator == 0) {
        return null;
    }
    if (first_separator != inside_project.len) {
        return error.InvalidBuildOutput;
    }
    return try allocator.dupe(u8, inside_project[0..first_separator]);
}

fn pathsEqual(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn pathIsInside(path: []const u8, parent: []const u8) bool {
    return path.len > parent.len and
        std.mem.startsWith(u8, path, parent) and
        isPathSeparator(path[parent.len]);
}

fn trimTrailingPathSeparators(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 1 and isPathSeparator(path[end - 1])) {
        end -= 1;
    }
    return path[0..end];
}

fn isPathSeparator(byte: u8) bool {
    return byte == '/' or byte == '\\';
}

pub fn copyProjectTree(io: Io, allocator: std.mem.Allocator, source_root_path: []const u8, dest_root_path: []const u8, skip_root_entry: ?[]const u8) !void {
    const cwd = Io.Dir.cwd();
    const source_root = try cwd.openDir(io, source_root_path, .{ .iterate = true });
    defer source_root.close(io);
    try cwd.createDirPath(io, dest_root_path);
    const dest_root = try cwd.openDir(io, dest_root_path, .{});
    defer dest_root.close(io);
    try copyProjectDirContents(io, allocator, source_root, dest_root, skip_root_entry, true);
}

fn copyProjectDirContents(
    io: Io,
    allocator: std.mem.Allocator,
    source_dir: Io.Dir,
    dest_dir: Io.Dir,
    skip_root_entry: ?[]const u8,
    root_level: bool,
) !void {
    var iterator = source_dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (root_level and shouldSkipProjectRootEntry(entry.name, skip_root_entry)) {
            continue;
        }
        switch (entry.kind) {
            .directory => {
                try dest_dir.createDirPath(io, entry.name);
                const child_source = try source_dir.openDir(io, entry.name, .{ .iterate = true });
                defer child_source.close(io);
                const child_dest = try dest_dir.openDir(io, entry.name, .{});
                defer child_dest.close(io);
                try copyProjectDirContents(io, allocator, child_source, child_dest, skip_root_entry, false);
            },
            .file => try source_dir.copyFile(entry.name, dest_dir, entry.name, io, .{ .replace = true }),
            else => {},
        }
    }
}

fn shouldSkipProjectRootEntry(name: []const u8, skip_root_entry: ?[]const u8) bool {
    if (skip_root_entry) |entry| {
        if (std.mem.eql(u8, name, entry)) {
            return true;
        }
    }
    return std.mem.eql(u8, name, ".scrapbot") or
        std.mem.eql(u8, name, ".git") or
        std.mem.eql(u8, name, ".zig-cache") or
        std.mem.eql(u8, name, "zig-cache") or
        std.mem.eql(u8, name, "zig-out");
}

pub fn copyPackagedNativeArtifact(
    io: Io,
    allocator: std.mem.Allocator,
    cwd: Io.Dir,
    project_root_path: []const u8,
    project_bundle_path: []const u8,
    artifact_path: []const u8,
) !void {
    const source_path = try std.fs.path.join(allocator, &.{ project_root_path, artifact_path });
    defer allocator.free(source_path);
    const dest_path = try std.fs.path.join(allocator, &.{ project_bundle_path, artifact_path });
    defer allocator.free(dest_path);

    if (std.fs.path.dirname(dest_path)) |dest_dir_path| {
        try cwd.createDirPath(io, dest_dir_path);
    }
    try cwd.copyFile(source_path, cwd, dest_path, io, .{ .make_path = true, .replace = true });
}

pub fn executableFileName() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "scrapbot.exe",
        else => "scrapbot",
    };
}

pub fn launcherFileName() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "run.cmd",
        else => "run",
    };
}

pub fn writeLauncher(io: Io, bundle_dir: Io.Dir, launcher_name: []const u8) !void {
    const contents = switch (builtin.os.tag) {
        .windows =>
        \\@echo off
        \\set "SCRIPT_DIR=%~dp0"
        \\set "PATH=%SCRIPT_DIR%lib;%SCRIPT_DIR%bin;%PATH%"
        \\"%SCRIPT_DIR%bin\scrapbot.exe" run "%SCRIPT_DIR%project" %*
        \\
        ,
        .macos =>
        \\#!/bin/sh
        \\set -eu
        \\DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        \\export DYLD_LIBRARY_PATH="$DIR/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
        \\exec "$DIR/bin/scrapbot" run "$DIR/project" "$@"
        \\
        ,
        .linux =>
        \\#!/bin/sh
        \\set -eu
        \\DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        \\export LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        \\exec "$DIR/bin/scrapbot" run "$DIR/project" "$@"
        \\
        ,
        else =>
        \\#!/bin/sh
        \\set -eu
        \\DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        \\exec "$DIR/bin/scrapbot" run "$DIR/project" "$@"
        \\
        ,
    };
    const flags: Io.Dir.CreateFileOptions = switch (builtin.os.tag) {
        .windows => .{},
        else => .{ .permissions = .fromMode(0o755) },
    };
    try bundle_dir.writeFile(io, .{
        .sub_path = launcher_name,
        .data = contents,
        .flags = flags,
    });
}

pub fn copyDiscoverableSdl3(io: Io, cwd: Io.Dir, bundle_dir: Io.Dir) !bool {
    var copied = false;
    for (sdl3CandidatePaths()) |candidate| {
        if (std.fs.path.basename(candidate).len == 0) {
            continue;
        }
        if (!fileExists(io, cwd, candidate)) {
            continue;
        }
        const dest_path = try std.fs.path.join(std.heap.smp_allocator, &.{ lib_dir, std.fs.path.basename(candidate) });
        defer std.heap.smp_allocator.free(dest_path);
        try cwd.copyFile(candidate, bundle_dir, dest_path, io, .{ .make_path = true, .replace = true });
        copied = true;
    }
    return copied;
}

fn sdl3CandidatePaths() []const []const u8 {
    return switch (builtin.os.tag) {
        .macos => &.{
            "/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib",
            "/opt/homebrew/opt/sdl3/lib/libSDL3.dylib",
            "/opt/homebrew/lib/libSDL3.0.dylib",
            "/opt/homebrew/lib/libSDL3.dylib",
            "/usr/local/opt/sdl3/lib/libSDL3.0.dylib",
            "/usr/local/opt/sdl3/lib/libSDL3.dylib",
            "/usr/local/lib/libSDL3.0.dylib",
            "/usr/local/lib/libSDL3.dylib",
        },
        .linux => &.{
            "/usr/lib/libSDL3.so.0",
            "/usr/lib/libSDL3.so",
            "/usr/lib/x86_64-linux-gnu/libSDL3.so.0",
            "/usr/lib/x86_64-linux-gnu/libSDL3.so",
            "/usr/lib/aarch64-linux-gnu/libSDL3.so.0",
            "/usr/lib/aarch64-linux-gnu/libSDL3.so",
        },
        .windows => &.{
            "SDL3.dll",
        },
        else => &.{},
    };
}

pub const BuildManifestInput = struct {
    project_name: []const u8,
    bundle_path: []const u8,
    runtime_path: []const u8,
    project_path: []const u8,
    native_artifact: ?[]const u8,
    sdl3_bundled: bool,
    sdl3_warning: ?[]const u8,
};

pub fn writeBuildManifest(io: Io, allocator: std.mem.Allocator, bundle_dir: Io.Dir, input: BuildManifestInput) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, "{\n");
    try out.appendSlice(allocator, "  \"schema\": \"scrapbot.build.v1\",\n");
    try out.appendSlice(allocator, "  \"project\": ");
    try appendJsonString(allocator, &out, input.project_name);
    try out.appendSlice(allocator, ",\n  \"host\": ");
    try appendJsonString(allocator, &out, hostTriple());
    try out.appendSlice(allocator, ",\n  \"bundle_path\": ");
    try appendJsonString(allocator, &out, input.bundle_path);
    try out.appendSlice(allocator, ",\n  \"runtime_path\": ");
    try appendJsonString(allocator, &out, input.runtime_path);
    try out.appendSlice(allocator, ",\n  \"project_path\": ");
    try appendJsonString(allocator, &out, input.project_path);
    try out.appendSlice(allocator, ",\n  \"native_artifact\": ");
    if (input.native_artifact) |path| {
        try appendJsonString(allocator, &out, path);
    } else {
        try out.appendSlice(allocator, "null");
    }
    try out.print(allocator, ",\n  \"sdl3_bundled\": {},\n  \"sdl3_warning\": ", .{input.sdl3_bundled});
    if (input.sdl3_warning) |message| {
        try appendJsonString(allocator, &out, message);
    } else {
        try out.appendSlice(allocator, "null");
    }
    try out.appendSlice(allocator, "\n}\n");

    try bundle_dir.writeFile(io, .{
        .sub_path = manifest_path,
        .data = out.items,
    });
}

fn fileExists(io: Io, dir: Io.Dir, path: []const u8) bool {
    dir.access(io, path, .{}) catch return false;
    return true;
}

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(allocator, '"');
    for (value) |byte| {
        switch (byte) {
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '"' => try out.appendSlice(allocator, "\\\""),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, byte),
        }
    }
    try out.append(allocator, '"');
}
