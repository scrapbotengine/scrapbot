const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Io = std.Io;
const native_api = @import("native_api.zig");
const runtime = @import("runtime.zig");
const script = @import("script.zig");

const native_build_dir = ".machina/native";
const native_api_cache_path = native_build_dir ++ "/machina_native.zig";
const native_api_source = @embedFile("native_api.zig");

pub const NativeOptimizeMode = enum {
    debug,
    release_fast,

    fn zigName(self: NativeOptimizeMode) []const u8 {
        return switch (self) {
            .debug => "Debug",
            .release_fast => "ReleaseFast",
        };
    }
};

pub const LoadResult = union(enum) {
    extension: LoadedExtension,
    diagnostic: script.Diagnostic,
};

pub const LoadedExtension = struct {
    components: []runtime.ComponentDefinition = &.{},
    systems: []script.NativeSystemRegistration = &.{},
    libraries: []script.NativeLibrary = &.{},

    pub fn nativeExtension(self: LoadedExtension) script.NativeExtension {
        return .{
            .components = self.components,
            .systems = self.systems,
            .libraries = self.libraries,
        };
    }

    pub fn deinit(self: *LoadedExtension, allocator: std.mem.Allocator, libraries_transferred: bool) void {
        for (self.components) |component| {
            allocator.free(component.fields);
        }
        allocator.free(self.components);

        for (self.systems) |system| {
            allocator.free(system.definition.reads);
            allocator.free(system.definition.writes);
            allocator.free(system.definition.before);
            allocator.free(system.definition.after);
        }
        allocator.free(self.systems);

        if (!libraries_transferred) {
            for (self.libraries) |*library| {
                library.deinit(allocator);
            }
        }
        allocator.free(self.libraries);
        self.* = undefined;
    }
};

pub fn loadProjectExtensionDetailed(
    io: Io,
    allocator: std.mem.Allocator,
    project_root_path: []const u8,
    native_source_path: []const u8,
    source_stamp: anytype,
) !LoadResult {
    const cwd = Io.Dir.cwd();
    const root_dir = try cwd.openDir(io, project_root_path, .{});
    defer root_dir.close(io);

    try root_dir.createDirPath(io, native_build_dir);
    try root_dir.writeFile(io, .{
        .sub_path = native_api_cache_path,
        .data = native_api_source,
    });

    const output_path = try dynamicOutputPath(allocator, source_stamp);
    defer allocator.free(output_path);

    if (try buildDynamicLibrary(io, allocator, project_root_path, native_source_path, output_path, .debug)) |build_diagnostic| {
        return .{ .diagnostic = build_diagnostic };
    }

    const library_path = try std.fs.path.join(allocator, &.{ project_root_path, output_path });
    return loadExtensionLibrary(allocator, library_path, native_source_path);
}

pub fn buildProjectDynamicLibraryDetailed(
    io: Io,
    allocator: std.mem.Allocator,
    project_root_path: []const u8,
    native_source_path: []const u8,
    output_path: []const u8,
    optimize: NativeOptimizeMode,
) !?script.Diagnostic {
    const cwd = Io.Dir.cwd();
    const root_dir = try cwd.openDir(io, project_root_path, .{});
    defer root_dir.close(io);

    try root_dir.createDirPath(io, native_build_dir);
    try root_dir.writeFile(io, .{
        .sub_path = native_api_cache_path,
        .data = native_api_source,
    });

    return buildDynamicLibrary(io, allocator, project_root_path, native_source_path, output_path, optimize);
}

pub fn loadProjectArtifactDetailed(
    allocator: std.mem.Allocator,
    project_root_path: []const u8,
    artifact_path: []const u8,
) !LoadResult {
    const library_path = try std.fs.path.join(allocator, &.{ project_root_path, artifact_path });
    return loadExtensionLibrary(allocator, library_path, artifact_path);
}

pub fn dynamicLibraryFileName() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "machina_project.dll",
        .macos, .ios => "libmachina_project.dylib",
        else => "libmachina_project.so",
    };
}

fn loadExtensionLibrary(
    allocator: std.mem.Allocator,
    library_path: []u8,
    diagnostic_path: []const u8,
) !LoadResult {
    errdefer allocator.free(library_path);

    var library = openDynamicLibrary(allocator, library_path) catch |err| {
        allocator.free(library_path);
        return .{ .diagnostic = try makeDiagnostic(allocator, .native_load, diagnostic_path, "failed to open native library: {s}", .{@errorName(err)}) };
    };
    errdefer library.close();

    const register = library.lookup(native_api.RegisterFn, "machina_register") orelse {
        library.close();
        allocator.free(library_path);
        return .{ .diagnostic = try makeDiagnostic(allocator, .native_load, diagnostic_path, "native library does not export machina_register", .{}) };
    };

    var builder = NativeRegistrationBuilder{ .allocator = allocator };
    defer builder.deinit();

    const register_api = native_api.RegisterApi{
        .context = &builder,
        .register_component = registerComponentCallback,
        .register_system = registerSystemCallback,
    };
    if (register(&register_api) == 0) {
        library.close();
        allocator.free(library_path);
        const message = if (builder.error_message) |message| message else "machina_register returned failure";
        return .{ .diagnostic = try makeDiagnostic(allocator, .native_registration, diagnostic_path, "{s}", .{message}) };
    }

    const components = try builder.components.toOwnedSlice(allocator);
    errdefer {
        for (components) |component| {
            allocator.free(component.fields);
        }
        allocator.free(components);
    }
    const systems = try builder.systems.toOwnedSlice(allocator);
    errdefer {
        for (systems) |system| {
            allocator.free(system.definition.reads);
            allocator.free(system.definition.writes);
            allocator.free(system.definition.before);
            allocator.free(system.definition.after);
        }
        allocator.free(systems);
    }
    builder.components = .empty;
    builder.systems = .empty;

    const libraries = try allocator.alloc(script.NativeLibrary, 1);
    libraries[0] = .{
        .path = library_path,
        .handle = library,
    };
    errdefer {
        var owned_library = libraries[0];
        owned_library.deinit(allocator);
        allocator.free(libraries);
    }
    library = undefined;

    return .{ .extension = .{
        .components = components,
        .systems = systems,
        .libraries = libraries,
    } };
}

fn buildDynamicLibrary(
    io: Io,
    allocator: std.mem.Allocator,
    project_root_path: []const u8,
    native_source_path: []const u8,
    output_path: []const u8,
    optimize: NativeOptimizeMode,
) !?script.Diagnostic {
    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{output_path});
    defer allocator.free(emit_arg);
    const root_module_arg = try std.fmt.allocPrint(allocator, "-Mroot={s}", .{native_source_path});
    defer allocator.free(root_module_arg);
    const native_api_module_arg = try std.fmt.allocPrint(allocator, "-Mmachina_native={s}", .{native_api_cache_path});
    defer allocator.free(native_api_module_arg);

    const argv = [_][]const u8{
        build_options.zig_exe,
        "build-lib",
        "-dynamic",
        "-O",
        optimize.zigName(),
        emit_arg,
        "--cache-dir",
        native_build_dir ++ "/zig-cache",
        "--global-cache-dir",
        native_build_dir ++ "/zig-global-cache",
        "--dep",
        "machina_native",
        root_module_arg,
        native_api_module_arg,
    };

    const process_allocator = std.heap.smp_allocator;
    const result = std.process.run(process_allocator, io, .{
        .argv = &argv,
        .cwd = .{ .path = project_root_path },
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch |err| {
        return try makeDiagnostic(allocator, .native_build, native_source_path, "failed to run zig build-lib: {s}", .{@errorName(err)});
    };
    defer process_allocator.free(result.stdout);
    defer process_allocator.free(result.stderr);

    const ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (ok) {
        return null;
    }

    const detail = if (std.mem.trim(u8, result.stderr, " \t\r\n").len > 0)
        result.stderr
    else if (std.mem.trim(u8, result.stdout, " \t\r\n").len > 0)
        result.stdout
    else
        "zig build-lib failed without output";
    return try makeDiagnostic(allocator, .native_build, native_source_path, "{s}", .{detail});
}

fn openDynamicLibrary(allocator: std.mem.Allocator, path: []const u8) !script.PlatformDynLib {
    return switch (builtin.os.tag) {
        .windows => script.PlatformDynLib.open(allocator, path),
        else => std.DynLib.open(path),
    };
}

const NativeRegistrationBuilder = struct {
    allocator: std.mem.Allocator,
    components: std.ArrayList(runtime.ComponentDefinition) = .empty,
    systems: std.ArrayList(script.NativeSystemRegistration) = .empty,
    error_message: ?[]u8 = null,

    fn deinit(self: *NativeRegistrationBuilder) void {
        if (self.error_message) |message| {
            self.allocator.free(message);
            self.error_message = null;
        }
        for (self.components.items) |component| {
            self.allocator.free(component.fields);
        }
        self.components.deinit(self.allocator);
        for (self.systems.items) |system| {
            self.allocator.free(system.definition.reads);
            self.allocator.free(system.definition.writes);
            self.allocator.free(system.definition.before);
            self.allocator.free(system.definition.after);
        }
        self.systems.deinit(self.allocator);
    }

    fn setError(self: *NativeRegistrationBuilder, comptime format: []const u8, args: anytype) void {
        if (self.error_message) |message| {
            self.allocator.free(message);
        }
        self.error_message = std.fmt.allocPrint(self.allocator, format, args) catch null;
    }
};

fn registerComponentCallback(raw_context: ?*anyopaque, definition: *const native_api.ComponentDefinition) callconv(.c) c_int {
    const builder: *NativeRegistrationBuilder = @ptrCast(@alignCast(raw_context orelse return 0));
    const fields = builder.allocator.alloc(runtime.ComponentFieldDefinition, definition.field_count) catch {
        builder.setError("failed to allocate native component fields", .{});
        return 0;
    };

    const raw_fields = if (definition.field_count == 0) null else definition.fields orelse {
        builder.allocator.free(fields);
        builder.setError("native component '{s}' provided a null field list", .{std.mem.span(definition.id)});
        return 0;
    };

    if (raw_fields) |field_ptr| {
        for (field_ptr[0..definition.field_count], 0..) |field, index| {
            fields[index] = .{
                .name = std.mem.span(field.name),
                .value_type = toRuntimeFieldType(field.field_type),
            };
        }
    }

    builder.components.append(builder.allocator, .{
        .id = std.mem.span(definition.id),
        .version = definition.version,
        .fields = fields,
    }) catch {
        builder.allocator.free(fields);
        builder.setError("failed to store native component '{s}'", .{std.mem.span(definition.id)});
        return 0;
    };
    return 1;
}

fn registerSystemCallback(raw_context: ?*anyopaque, definition: *const native_api.SystemDefinition) callconv(.c) c_int {
    const builder: *NativeRegistrationBuilder = @ptrCast(@alignCast(raw_context orelse return 0));

    const reads = cloneStringList(builder.allocator, definition.reads) catch {
        builder.setError("failed to allocate read list for native system '{s}'", .{std.mem.span(definition.id)});
        return 0;
    };
    const writes = cloneStringList(builder.allocator, definition.writes) catch {
        builder.allocator.free(reads);
        builder.setError("failed to allocate write list for native system '{s}'", .{std.mem.span(definition.id)});
        return 0;
    };
    const before = cloneStringList(builder.allocator, definition.before) catch {
        builder.allocator.free(reads);
        builder.allocator.free(writes);
        builder.setError("failed to allocate before list for native system '{s}'", .{std.mem.span(definition.id)});
        return 0;
    };
    const after = cloneStringList(builder.allocator, definition.after) catch {
        builder.allocator.free(reads);
        builder.allocator.free(writes);
        builder.allocator.free(before);
        builder.setError("failed to allocate after list for native system '{s}'", .{std.mem.span(definition.id)});
        return 0;
    };

    builder.systems.append(builder.allocator, .{
        .definition = .{
            .id = std.mem.span(definition.id),
            .phase = toRuntimeSystemPhase(definition.phase),
            .reads = reads,
            .writes = writes,
            .before = before,
            .after = after,
        },
        .run = definition.run,
    }) catch {
        builder.allocator.free(reads);
        builder.allocator.free(writes);
        builder.allocator.free(before);
        builder.allocator.free(after);
        builder.setError("failed to store native system '{s}'", .{std.mem.span(definition.id)});
        return 0;
    };
    return 1;
}

fn cloneStringList(allocator: std.mem.Allocator, list: native_api.StringList) ![]const []const u8 {
    const values = try allocator.alloc([]const u8, list.len);
    errdefer allocator.free(values);
    if (list.len == 0) {
        return values;
    }
    const items = list.items orelse return error.InvalidNativeStringList;
    for (items[0..list.len], 0..) |value, index| {
        values[index] = std.mem.span(value);
    }
    return values;
}

fn toRuntimeFieldType(value: native_api.FieldType) runtime.FieldType {
    return switch (value) {
        .boolean => .boolean,
        .int => .int,
        .float => .float,
        .vec3 => .vec3,
        .string => .string,
    };
}

fn toRuntimeSystemPhase(value: native_api.SystemPhase) runtime.SystemPhase {
    return switch (value) {
        .startup => .startup,
        .update => .update,
        .fixed_update => .fixed_update,
        .render => .render,
    };
}

fn dynamicOutputPath(allocator: std.mem.Allocator, source_stamp: anytype) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        native_build_dir ++ "/{s}machina_project_{d}_{d}{s}",
        .{
            dynamicLibraryPrefix(),
            source_stamp.size,
            source_stamp.mtime.nanoseconds,
            dynamicLibrarySuffix(),
        },
    );
}

fn dynamicLibraryPrefix() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "",
        else => "lib",
    };
}

fn dynamicLibrarySuffix() []const u8 {
    return switch (builtin.os.tag) {
        .windows => ".dll",
        .macos, .ios => ".dylib",
        else => ".so",
    };
}

fn makeDiagnostic(
    allocator: std.mem.Allocator,
    stage: script.DiagnosticStage,
    path: []const u8,
    comptime format: []const u8,
    args: anytype,
) !script.Diagnostic {
    const message = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(message);
    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);
    return .{
        .stage = stage,
        .path = owned_path,
        .message = try allocator.dupe(u8, message),
    };
}
