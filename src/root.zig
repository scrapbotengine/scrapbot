const std = @import("std");
const Io = std.Io;

pub const version = "0.1.0-dev";
pub const project_file_name = "project.machina.toml";
pub const default_scene_path = "scenes/main.scene.toml";

pub const Project = struct {
    root_path: []const u8,
    name: []const u8,
    default_scene: []const u8,
};

pub const Diagnostic = struct {
    path: []const u8,
    message: []const u8,
};

pub const CheckResult = struct {
    project: Project,
};

pub const ProjectError = error{
    AlreadyExists,
    InvalidProject,
    MissingProjectFile,
    MissingDefaultScene,
    UnsupportedProjectVersion,
    InvalidProjectName,
    InvalidDefaultScene,
};

pub fn initProject(io: Io, allocator: std.mem.Allocator, root_path: []const u8, name: []const u8) !void {
    const cwd = Io.Dir.cwd();
    cwd.createDirPath(io, root_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    if (fileExists(io, root_dir, project_file_name)) {
        return ProjectError.AlreadyExists;
    }

    try root_dir.createDirPath(io, "scenes");

    const escaped_name = try encodeTomlBasicString(allocator, name);
    defer allocator.free(escaped_name);

    const project_contents = try std.fmt.allocPrint(
        allocator,
        "name = \"{s}\"\nversion = 1\ndefault_scene = \"{s}\"\n",
        .{ escaped_name, default_scene_path },
    );
    defer allocator.free(project_contents);

    {
        try root_dir.writeFile(io, .{
            .sub_path = project_file_name,
            .data = project_contents,
            .flags = .{ .exclusive = true },
        });
    }

    {
        try root_dir.writeFile(io, .{
            .sub_path = default_scene_path,
            .data =
            \\name = "Main"
            \\version = 1
            \\
            ,
            .flags = .{ .exclusive = true },
        });
    }
}

pub fn checkProject(io: Io, allocator: std.mem.Allocator, root_path: []const u8) !CheckResult {
    const cwd = Io.Dir.cwd();
    const root_dir = cwd.openDir(io, root_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ProjectError.InvalidProject,
        else => return err,
    };
    defer root_dir.close(io);

    const project = try loadProjectFile(io, allocator, root_path, root_dir);
    if (!fileExists(io, root_dir, project.default_scene)) {
        return ProjectError.MissingDefaultScene;
    }

    try validateScene(io, root_dir, project.default_scene);

    return .{ .project = project };
}

pub fn freeProject(allocator: std.mem.Allocator, project: Project) void {
    allocator.free(project.root_path);
    allocator.free(project.name);
    allocator.free(project.default_scene);
}

fn loadProjectFile(io: Io, allocator: std.mem.Allocator, root_path: []const u8, root_dir: Io.Dir) !Project {
    const contents = root_dir.readFileAlloc(io, project_file_name, allocator, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return ProjectError.MissingProjectFile,
        else => return err,
    };
    defer allocator.free(contents);

    const name = try readRequiredString(allocator, contents, "name") orelse return ProjectError.InvalidProjectName;
    errdefer allocator.free(name);

    const default_scene = try readRequiredString(allocator, contents, "default_scene") orelse return ProjectError.InvalidDefaultScene;
    errdefer allocator.free(default_scene);
    if (!isSafeProjectRelativePath(default_scene)) {
        return ProjectError.InvalidDefaultScene;
    }

    const version_value = readRequiredInt(contents, "version") orelse return ProjectError.UnsupportedProjectVersion;
    if (version_value != 1) {
        return ProjectError.UnsupportedProjectVersion;
    }

    return .{
        .root_path = try allocator.dupe(u8, root_path),
        .name = name,
        .default_scene = default_scene,
    };
}

fn validateScene(io: Io, root_dir: Io.Dir, scene_path: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    const contents = root_dir.readFile(io, scene_path, &buffer) catch |err| switch (err) {
        error.FileNotFound => return ProjectError.MissingDefaultScene,
        else => return err,
    };

    if (!hasRequiredString(contents, "name")) {
        return ProjectError.InvalidProject;
    }

    const version_value = readRequiredInt(contents, "version") orelse return ProjectError.UnsupportedProjectVersion;
    if (version_value != 1) {
        return ProjectError.UnsupportedProjectVersion;
    }
}

fn readRequiredString(allocator: std.mem.Allocator, contents: []const u8, key: []const u8) !?[]const u8 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const found_key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, found_key, key)) {
            continue;
        }

        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') {
            return null;
        }
        return try decodeTomlBasicString(allocator, value[1 .. value.len - 1]);
    }

    return null;
}

fn encodeTomlBasicString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

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

    return try out.toOwnedSlice(allocator);
}

fn decodeTomlBasicString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        const byte = value[index];
        if (byte != '\\') {
            try out.append(allocator, byte);
            continue;
        }

        index += 1;
        if (index >= value.len) {
            return ProjectError.InvalidProject;
        }

        switch (value[index]) {
            '\\' => try out.append(allocator, '\\'),
            '"' => try out.append(allocator, '"'),
            'n' => try out.append(allocator, '\n'),
            'r' => try out.append(allocator, '\r'),
            't' => try out.append(allocator, '\t'),
            else => return ProjectError.InvalidProject,
        }
    }

    return try out.toOwnedSlice(allocator);
}

fn hasRequiredString(contents: []const u8, key: []const u8) bool {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const found_key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, found_key, key)) {
            continue;
        }

        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        return value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"';
    }

    return false;
}

fn readRequiredInt(contents: []const u8, key: []const u8) ?u32 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }

        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const found_key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, found_key, key)) {
            continue;
        }

        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        return std.fmt.parseInt(u32, value, 10) catch null;
    }

    return null;
}

fn isSafeProjectRelativePath(path: []const u8) bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, '\\') != null) {
        return false;
    }

    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) {
            return false;
        }
    }

    return true;
}

fn fileExists(io: Io, dir: Io.Dir, path: []const u8) bool {
    dir.access(io, path, .{}) catch return false;
    return true;
}

test "initProject creates project metadata and default scene" {
    const root_path = ".zig-cache/test-init-project";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Demo");

    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try std.testing.expect(fileExists(io, root_dir, project_file_name));
    try std.testing.expect(fileExists(io, root_dir, default_scene_path));
}

test "checkProject validates a project directory" {
    const root_path = ".zig-cache/test-check-project";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Game");

    const result = try checkProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, result.project);

    try std.testing.expectEqualStrings("Game", result.project.name);
    try std.testing.expectEqualStrings(default_scene_path, result.project.default_scene);
}

test "initProject escapes project names in metadata" {
    const root_path = ".zig-cache/test-escaped-project-name";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try initProject(io, std.testing.allocator, root_path, "Agent \"One\"");

    const result = try checkProject(io, std.testing.allocator, root_path);
    defer freeProject(std.testing.allocator, result.project);

    try std.testing.expectEqualStrings("Agent \"One\"", result.project.name);
}

test "checkProject rejects default scenes outside the project" {
    const root_path = ".zig-cache/test-scene-escape";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try cwd.createDirPath(io, root_path);
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Game\"\nversion = 1\ndefault_scene = \"../outside.scene.toml\"\n",
    });

    try std.testing.expectError(
        ProjectError.InvalidDefaultScene,
        checkProject(io, std.testing.allocator, root_path),
    );
}

test "checkProject rejects platform separators in project resource paths" {
    const root_path = ".zig-cache/test-scene-backslash";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try cwd.createDirPath(io, root_path);
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes\\\\main.scene.toml\"\n",
    });

    try std.testing.expectError(
        ProjectError.InvalidDefaultScene,
        checkProject(io, std.testing.allocator, root_path),
    );
}

test "checkProject rejects unsupported metadata version" {
    const root_path = ".zig-cache/test-unsupported-version";
    const io = Io.Threaded.global_single_threaded.io();
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, root_path) catch {};
    defer cwd.deleteTree(io, root_path) catch {};

    try cwd.createDirPath(io, root_path);
    const root_dir = try cwd.openDir(io, root_path, .{});
    defer root_dir.close(io);

    try root_dir.writeFile(io, .{
        .sub_path = project_file_name,
        .data = "name = \"Game\"\nversion = 99\ndefault_scene = \"scenes/main.scene.toml\"\n",
    });

    try std.testing.expectError(
        ProjectError.UnsupportedProjectVersion,
        loadProjectFile(io, std.testing.allocator, ".", root_dir),
    );
}
