const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const native_api = @import("native_api.zig");
const runtime = @import("runtime.zig");

const c = @cImport({
    @cInclude("luau_bridge.h");
});

pub const system_profile_window_frames: usize = 120;

pub const ScriptError = runtime.RegistryError || runtime.ScheduleError || std.mem.Allocator.Error || error{
    InvalidScript,
    UnknownFieldType,
    UnknownSystemPhase,
};

pub const DiagnosticStage = enum {
    load,
    native_build,
    native_load,
    native_registration,
    registration,
    schedule,
    runtime,

    pub fn label(self: DiagnosticStage) []const u8 {
        return switch (self) {
            .load => "script load",
            .native_build => "native build",
            .native_load => "native load",
            .native_registration => "native registration",
            .registration => "script registration",
            .schedule => "script schedule",
            .runtime => "script runtime",
        };
    }
};

pub const Diagnostic = struct {
    stage: DiagnosticStage,
    path: ?[]const u8 = null,
    system_id: ?[]const u8 = null,
    start: ?DiagnosticPosition = null,
    end: ?DiagnosticPosition = null,
    message: []const u8,

    pub fn deinit(self: *Diagnostic, allocator: std.mem.Allocator) void {
        if (self.path) |path| {
            allocator.free(path);
        }
        if (self.system_id) |system_id| {
            allocator.free(system_id);
        }
        allocator.free(self.message);
        self.* = undefined;
    }
};

pub const DiagnosticPosition = struct {
    line: u32,
    column: ?u32 = null,
};

pub const LoadResult = union(enum) {
    program: Program,
    diagnostic: Diagnostic,
};

pub const NativeSystemContext = native_api.SystemContext;
pub const NativeSystemFn = native_api.SystemRunFn;

pub const NativeSystemRegistration = struct {
    definition: runtime.SystemDefinition,
    run: NativeSystemFn,
};

pub const PlatformDynLib = switch (builtin.os.tag) {
    .windows => WindowsDynLib,
    else => std.DynLib,
};

const WindowsDynLib = struct {
    handle: std.os.windows.HMODULE,

    pub const Error = error{
        LoadLibraryFailed,
        InvalidLibraryPath,
    };

    pub fn open(allocator: std.mem.Allocator, path: []const u8) Error!WindowsDynLib {
        const path_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return error.InvalidLibraryPath;
        defer allocator.free(path_w);
        const handle = LoadLibraryW(path_w.ptr) orelse return error.LoadLibraryFailed;
        return .{ .handle = handle };
    }

    pub fn close(self: *WindowsDynLib) void {
        _ = FreeLibrary(self.handle);
    }

    pub fn lookup(self: *WindowsDynLib, comptime T: type, name: [:0]const u8) ?T {
        const symbol = GetProcAddress(self.handle, name.ptr) orelse return null;
        return @ptrCast(symbol);
    }
};

pub const NativeLibrary = struct {
    path: []u8,
    handle: PlatformDynLib,

    pub fn deinit(self: *NativeLibrary, allocator: std.mem.Allocator) void {
        self.handle.close();
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const NativeExtension = struct {
    components: []const runtime.ComponentDefinition = &.{},
    systems: []const NativeSystemRegistration = &.{},
    libraries: []const NativeLibrary = &.{},
};

extern "kernel32" fn LoadLibraryW(lpLibFileName: [*:0]const u16) callconv(.winapi) ?std.os.windows.HMODULE;
extern "kernel32" fn GetProcAddress(hModule: std.os.windows.HMODULE, lpProcName: [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn FreeLibrary(hLibModule: std.os.windows.HMODULE) callconv(.winapi) c_int;

const ScriptOrigin = struct {
    index: usize,
    id: []const u8,
    path: []const u8,
    start: ?DiagnosticPosition = null,
    runner_ref: u32 = 0,

    fn deinit(self: ScriptOrigin, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.path);
    }
};

const NativeSystemEntry = struct {
    id: [:0]u8,
    run: NativeSystemFn,

    fn deinit(self: *NativeSystemEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        self.* = undefined;
    }
};

const SystemProfileState = struct {
    id: []const u8,
    phase: runtime.SystemPhase,
    samples_ns: [system_profile_window_frames]u64 = [_]u64{0} ** system_profile_window_frames,
    sample_count: usize = 0,
    next_sample: usize = 0,
    total_ns: u64 = 0,
    last_ns: u64 = 0,

    fn deinit(self: *SystemProfileState, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        self.* = undefined;
    }

    fn record(self: *SystemProfileState, duration_ns: u64) void {
        if (self.sample_count < system_profile_window_frames) {
            self.samples_ns[self.next_sample] = duration_ns;
            self.sample_count += 1;
            self.total_ns += duration_ns;
        } else {
            self.total_ns -= self.samples_ns[self.next_sample];
            self.samples_ns[self.next_sample] = duration_ns;
            self.total_ns += duration_ns;
        }

        self.next_sample = (self.next_sample + 1) % system_profile_window_frames;
        self.last_ns = duration_ns;
    }

    fn snapshot(self: SystemProfileState) runtime.SystemProfileSnapshot {
        const average_ns = if (self.sample_count == 0) 0 else self.total_ns / self.sample_count;
        return .{
            .id = self.id,
            .phase = self.phase,
            .sample_count = @intCast(self.sample_count),
            .window_size = @intCast(system_profile_window_frames),
            .last_ns = self.last_ns,
            .rolling_average_ns = average_ns,
        };
    }
};

const QueuedComponentFieldValue = struct {
    name: []u8,
    value: runtime.ComponentValue,

    fn deinit(self: *QueuedComponentFieldValue, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        switch (self.value) {
            .string => |payload| allocator.free(payload),
            else => {},
        }
        self.* = undefined;
    }

    fn asRuntime(self: QueuedComponentFieldValue) runtime.ComponentFieldValue {
        return .{
            .name = self.name,
            .value = self.value,
        };
    }
};

const ScriptCommand = union(enum) {
    add_component: QueuedAddComponent,
    remove_component: QueuedRemoveComponent,
    despawn_entity: runtime.EntityHandle,

    fn deinit(self: *ScriptCommand, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .add_component => |*payload| payload.deinit(allocator),
            .remove_component => |*payload| payload.deinit(allocator),
            .despawn_entity => {},
        }
        self.* = undefined;
    }
};

const QueuedAddComponent = struct {
    entity: runtime.EntityHandle,
    component_id: []u8,
    fields: []QueuedComponentFieldValue,

    fn deinit(self: *QueuedAddComponent, allocator: std.mem.Allocator) void {
        allocator.free(self.component_id);
        for (self.fields) |*field| {
            field.deinit(allocator);
        }
        allocator.free(self.fields);
        self.* = undefined;
    }
};

const QueuedRemoveComponent = struct {
    entity: runtime.EntityHandle,
    component_id: []u8,

    fn deinit(self: *QueuedRemoveComponent, allocator: std.mem.Allocator) void {
        allocator.free(self.component_id);
        self.* = undefined;
    }
};

const QueuedComponentSnapshot = struct {
    entity: runtime.EntityHandle,
    component_id: []u8,
    fields: []QueuedComponentFieldValue,

    fn deinit(self: *QueuedComponentSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.component_id);
        for (self.fields) |*field| {
            field.deinit(allocator);
        }
        allocator.free(self.fields);
        self.* = undefined;
    }
};

const AppliedScriptCommand = union(enum) {
    remove_added_component: QueuedRemoveComponent,
    restore_component: QueuedComponentSnapshot,

    fn deinit(self: *AppliedScriptCommand, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .remove_added_component => |*payload| payload.deinit(allocator),
            .restore_component => |*payload| payload.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const Program = struct {
    allocator: std.mem.Allocator,
    registry: runtime.ComponentRegistry,
    schedule: runtime.SystemSchedule,
    vm: *c.machina_luau,
    active_system: ?*const runtime.ScheduledSystem = null,
    component_origins: std.ArrayList(ScriptOrigin) = .empty,
    system_origins: std.ArrayList(ScriptOrigin) = .empty,
    native_libraries: std.ArrayList(NativeLibrary) = .empty,
    native_systems: std.ArrayList(NativeSystemEntry) = .empty,
    system_profiles: std.ArrayList(SystemProfileState) = .empty,
    system_profile_snapshots: std.ArrayList(runtime.SystemProfileSnapshot) = .empty,
    queued_script_commands: std.ArrayList(ScriptCommand) = .empty,
    immediate_script_spawns: std.ArrayList(runtime.EntityHandle) = .empty,
    last_diagnostic: ?Diagnostic = null,
    host_error: ?[:0]u8 = null,

    pub fn deinit(self: *Program) void {
        self.clearHostError();
        self.clearLastDiagnostic();
        self.clearQueuedScriptCommands();
        self.immediate_script_spawns.deinit(self.allocator);
        self.clearSystemProfiles();
        self.system_profile_snapshots.deinit(self.allocator);
        self.queued_script_commands.deinit(self.allocator);
        self.system_profiles.deinit(self.allocator);
        for (self.system_origins.items) |origin| {
            origin.deinit(self.allocator);
        }
        self.system_origins.deinit(self.allocator);
        for (self.native_systems.items) |*native_system| {
            native_system.deinit(self.allocator);
        }
        self.native_systems.deinit(self.allocator);
        for (self.native_libraries.items) |*native_library| {
            native_library.deinit(self.allocator);
        }
        self.native_libraries.deinit(self.allocator);
        for (self.component_origins.items) |origin| {
            origin.deinit(self.allocator);
        }
        self.component_origins.deinit(self.allocator);
        self.schedule.deinit();
        self.registry.deinit();
        c.machina_luau_destroy(self.vm);
        self.* = undefined;
    }

    pub fn startup(self: *Program, world: *runtime.World) bool {
        return self.runPhase(world, .startup, 0.0);
    }

    pub fn update(self: *Program, world: *runtime.World, delta_seconds: f32) bool {
        return self.runPhase(world, .update, delta_seconds);
    }

    pub fn systemProfileSnapshots(self: *Program) []const runtime.SystemProfileSnapshot {
        self.system_profile_snapshots.clearRetainingCapacity();
        for (self.system_profiles.items) |profile| {
            self.system_profile_snapshots.appendAssumeCapacity(profile.snapshot());
        }
        return self.system_profile_snapshots.items;
    }

    fn runPhase(self: *Program, world: *runtime.World, phase: runtime.SystemPhase, delta_seconds: f32) bool {
        self.clearLastDiagnostic();
        self.clearHostError();
        c.machina_luau_set_callback_context(self.vm, self);

        var ok = true;
        for (self.schedule.batches) |batch| {
            if (batch.phase != phase) {
                continue;
            }

            for (batch.systems) |*system| {
                switch (system.runner) {
                    .none => self.recordSystemDuration(system.*, phase, 0),
                    .native => |native_index| {
                        self.clearHostError();
                        self.active_system = system;
                        const started_ns = monotonicTimestampNs();
                        var system_ok = self.callNativeSystem(system.*, native_index, world, delta_seconds);
                        if (system_ok) {
                            system_ok = self.flushQueuedScriptCommands(world);
                        } else {
                            self.discardQueuedScriptCommands(world);
                        }
                        self.recordSystemDuration(system.*, phase, elapsedNanosecondsSince(started_ns));
                        if (!system_ok and self.last_diagnostic == null) {
                            self.setNativeRuntimeDiagnostic(system.*) catch {};
                        }
                        self.active_system = null;
                        self.clearHostError();
                        ok = ok and system_ok;
                    },
                    .luau => |runner_ref| {
                        self.clearHostError();
                        self.active_system = system;
                        const started_ns = monotonicTimestampNs();
                        var system_ok = c.machina_luau_call_system(self.vm, runner_ref, world, delta_seconds) != 0;
                        if (system_ok) {
                            system_ok = self.flushQueuedScriptCommands(world);
                        } else {
                            self.discardQueuedScriptCommands(world);
                        }
                        self.recordSystemDuration(system.*, phase, elapsedNanosecondsSince(started_ns));
                        if (!system_ok and self.last_diagnostic == null) {
                            self.setRuntimeDiagnostic(system.*, runner_ref) catch {};
                        }
                        self.active_system = null;
                        self.clearHostError();
                        ok = ok and system_ok;
                    },
                }
            }
        }
        return ok;
    }

    fn callNativeSystem(
        self: *Program,
        system: runtime.ScheduledSystem,
        native_index: u32,
        world: *runtime.World,
        delta_seconds: f32,
    ) bool {
        if (native_index >= self.native_systems.items.len) {
            self.setHostError("native system '{s}' has invalid runner index {d}", .{ system.id, native_index });
            return false;
        }
        const native_system = self.native_systems.items[native_index];
        var call_context = NativeCallContext{
            .program = self,
            .world = world,
        };
        var context = NativeSystemContext{
            .world = &call_context,
            .api = &native_system_api,
            .delta_seconds = delta_seconds,
            .system_id = native_system.id.ptr,
        };
        if (native_system.run(&context) == 0) {
            if (self.host_error == null) {
                self.setHostError("native system '{s}' failed", .{system.id});
            }
            return false;
        }
        return true;
    }

    fn flushQueuedScriptCommands(self: *Program, world: *runtime.World) bool {
        defer self.clearQueuedScriptCommands();
        defer self.immediate_script_spawns.clearRetainingCapacity();

        if (!self.preflightQueuedScriptCommands(world)) {
            self.rollbackImmediateScriptSpawns(world);
            return false;
        }

        var applied_commands: std.ArrayList(AppliedScriptCommand) = .empty;
        defer self.clearAppliedScriptCommands(&applied_commands);

        for (self.queued_script_commands.items) |*command| {
            switch (command.*) {
                .add_component => |payload| {
                    const previous = self.snapshotComponent(world, payload.entity, payload.component_id) catch {
                        self.setHostError("system '{s}' failed to snapshot component '{s}' on entity {d}", .{
                            self.activeSystemId(),
                            payload.component_id,
                            payload.entity.index,
                        });
                        self.rollbackAppliedScriptCommands(world, &applied_commands);
                        self.rollbackImmediateScriptSpawns(world);
                        return false;
                    };

                    const fields = self.allocator.alloc(runtime.ComponentFieldValue, payload.fields.len) catch {
                        self.setHostError("system '{s}' failed to allocate queued add fields", .{self.activeSystemId()});
                        if (previous) |snapshot| {
                            var cleanup = snapshot;
                            cleanup.deinit(self.allocator);
                        }
                        self.rollbackAppliedScriptCommands(world, &applied_commands);
                        self.rollbackImmediateScriptSpawns(world);
                        return false;
                    };
                    defer self.allocator.free(fields);
                    for (payload.fields, 0..) |field, index| {
                        fields[index] = field.asRuntime();
                    }
                    world.setComponent(payload.entity, payload.component_id, fields) catch |err| {
                        self.setHostError("system '{s}' failed to flush add component '{s}' to entity {d}: {s}", .{
                            self.activeSystemId(),
                            payload.component_id,
                            payload.entity.index,
                            @errorName(err),
                        });
                        if (previous) |snapshot| {
                            var cleanup = snapshot;
                            cleanup.deinit(self.allocator);
                        }
                        self.rollbackAppliedScriptCommands(world, &applied_commands);
                        self.rollbackImmediateScriptSpawns(world);
                        return false;
                    };
                    if (previous) |snapshot| {
                        var rollback_snapshot = snapshot;
                        applied_commands.append(self.allocator, .{ .restore_component = rollback_snapshot }) catch {
                            rollback_snapshot.deinit(self.allocator);
                            self.setHostError("system '{s}' failed to record rollback for component '{s}' on entity {d}: {s}", .{
                                self.activeSystemId(),
                                payload.component_id,
                                payload.entity.index,
                                @errorName(error.OutOfMemory),
                            });
                            self.rollbackAppliedScriptCommands(world, &applied_commands);
                            self.rollbackImmediateScriptSpawns(world);
                            return false;
                        };
                    } else {
                        const owned_component_id = self.allocator.dupe(u8, payload.component_id) catch {
                            self.setHostError("system '{s}' failed to record rollback for component '{s}' on entity {d}: {s}", .{
                                self.activeSystemId(),
                                payload.component_id,
                                payload.entity.index,
                                @errorName(error.OutOfMemory),
                            });
                            self.rollbackAppliedScriptCommands(world, &applied_commands);
                            self.rollbackImmediateScriptSpawns(world);
                            return false;
                        };
                        applied_commands.append(self.allocator, .{ .remove_added_component = .{
                            .entity = payload.entity,
                            .component_id = owned_component_id,
                        } }) catch {
                            self.allocator.free(owned_component_id);
                            self.setHostError("system '{s}' failed to record rollback for component '{s}' on entity {d}: {s}", .{
                                self.activeSystemId(),
                                payload.component_id,
                                payload.entity.index,
                                @errorName(error.OutOfMemory),
                            });
                            self.rollbackAppliedScriptCommands(world, &applied_commands);
                            self.rollbackImmediateScriptSpawns(world);
                            return false;
                        };
                    }
                },
                .remove_component => |payload| {
                    const previous = self.snapshotComponent(world, payload.entity, payload.component_id) catch {
                        self.setHostError("system '{s}' failed to snapshot component '{s}' on entity {d}", .{
                            self.activeSystemId(),
                            payload.component_id,
                            payload.entity.index,
                        });
                        self.rollbackAppliedScriptCommands(world, &applied_commands);
                        self.rollbackImmediateScriptSpawns(world);
                        return false;
                    };

                    const removed = world.removeComponent(payload.entity, payload.component_id) catch |err| {
                        self.setHostError("system '{s}' failed to flush remove component '{s}' from entity {d}: {s}", .{
                            self.activeSystemId(),
                            payload.component_id,
                            payload.entity.index,
                            @errorName(err),
                        });
                        if (previous) |snapshot| {
                            var cleanup = snapshot;
                            cleanup.deinit(self.allocator);
                        }
                        self.rollbackAppliedScriptCommands(world, &applied_commands);
                        self.rollbackImmediateScriptSpawns(world);
                        return false;
                    };
                    if (removed) {
                        if (previous) |snapshot| {
                            var rollback_snapshot = snapshot;
                            applied_commands.append(self.allocator, .{ .restore_component = rollback_snapshot }) catch {
                                rollback_snapshot.deinit(self.allocator);
                                self.setHostError("system '{s}' failed to record rollback for component '{s}' on entity {d}: {s}", .{
                                    self.activeSystemId(),
                                    payload.component_id,
                                    payload.entity.index,
                                    @errorName(error.OutOfMemory),
                                });
                                self.rollbackAppliedScriptCommands(world, &applied_commands);
                                self.rollbackImmediateScriptSpawns(world);
                                return false;
                            };
                        }
                    } else if (previous) |snapshot| {
                        var cleanup = snapshot;
                        cleanup.deinit(self.allocator);
                    }
                },
                .despawn_entity => {},
            }
        }

        for (self.queued_script_commands.items) |command| {
            switch (command) {
                .add_component, .remove_component => {},
                .despawn_entity => |entity| {
                    _ = world.removeEntity(entity) catch |err| {
                        self.setHostError("system '{s}' failed to flush despawn entity {d}: {s}", .{
                            self.activeSystemId(),
                            entity.index,
                            @errorName(err),
                        });
                        self.rollbackAppliedScriptCommands(world, &applied_commands);
                        self.rollbackImmediateScriptSpawns(world);
                        return false;
                    };
                },
            }
        }
        return true;
    }

    fn preflightQueuedScriptCommands(self: *Program, world: *runtime.World) bool {
        var despawned_entities: std.ArrayList(runtime.EntityHandle) = .empty;
        defer despawned_entities.deinit(self.allocator);

        for (self.queued_script_commands.items) |command| {
            switch (command) {
                .add_component => |payload| {
                    if (containsEntityHandle(despawned_entities.items, payload.entity)) {
                        self.setHostError("system '{s}' tried to add component '{s}' to entity {d} after it was queued for despawn", .{
                            self.activeSystemId(),
                            payload.component_id,
                            payload.entity.index,
                        });
                        return false;
                    }
                    _ = world.entity(payload.entity) catch |err| {
                        self.setHostError("system '{s}' failed to flush add component '{s}' to entity {d}: {s}", .{
                            self.activeSystemId(),
                            payload.component_id,
                            payload.entity.index,
                            @errorName(err),
                        });
                        return false;
                    };
                    if (!self.validateQueuedAddComponent(payload)) {
                        return false;
                    }
                },
                .remove_component => |payload| {
                    if (containsEntityHandle(despawned_entities.items, payload.entity)) {
                        self.setHostError("system '{s}' tried to remove component '{s}' from entity {d} after it was queued for despawn", .{
                            self.activeSystemId(),
                            payload.component_id,
                            payload.entity.index,
                        });
                        return false;
                    }
                    _ = world.entity(payload.entity) catch |err| {
                        self.setHostError("system '{s}' failed to flush remove component '{s}' from entity {d}: {s}", .{
                            self.activeSystemId(),
                            payload.component_id,
                            payload.entity.index,
                            @errorName(err),
                        });
                        return false;
                    };
                },
                .despawn_entity => |entity| {
                    if (containsEntityHandle(despawned_entities.items, entity)) {
                        self.setHostError("system '{s}' tried to despawn entity {d} more than once", .{
                            self.activeSystemId(),
                            entity.index,
                        });
                        return false;
                    }
                    _ = world.entity(entity) catch |err| {
                        self.setHostError("system '{s}' failed to flush despawn entity {d}: {s}", .{
                            self.activeSystemId(),
                            entity.index,
                            @errorName(err),
                        });
                        return false;
                    };
                    despawned_entities.append(self.allocator, entity) catch {
                        self.setHostError("system '{s}' failed to preflight despawn entity {d}: {s}", .{
                            self.activeSystemId(),
                            entity.index,
                            @errorName(error.OutOfMemory),
                        });
                        return false;
                    };
                },
            }
        }
        return true;
    }

    fn validateQueuedAddComponent(self: *Program, payload: QueuedAddComponent) bool {
        const definition = self.registry.findComponent(payload.component_id) orelse {
            self.setHostError("system '{s}' tried to add unknown component '{s}'", .{
                self.activeSystemId(),
                payload.component_id,
            });
            return false;
        };
        if (payload.fields.len != definition.fields.len) {
            self.setHostError("system '{s}' tried to add component '{s}' with {d} fields, expected {d}", .{
                self.activeSystemId(),
                payload.component_id,
                payload.fields.len,
                definition.fields.len,
            });
            return false;
        }

        for (definition.fields) |field_definition| {
            var found = false;
            for (payload.fields) |field| {
                if (!std.mem.eql(u8, field.name, field_definition.name)) {
                    continue;
                }
                if (found) {
                    self.setHostError("system '{s}' tried to add duplicate field '{s}.{s}'", .{
                        self.activeSystemId(),
                        payload.component_id,
                        field.name,
                    });
                    return false;
                }
                found = true;
                if (std.meta.activeTag(field.value) != field_definition.value_type) {
                    self.setHostError("system '{s}' tried to add field '{s}.{s}' with the wrong type", .{
                        self.activeSystemId(),
                        payload.component_id,
                        field.name,
                    });
                    return false;
                }
            }
            if (!found) {
                self.setHostError("system '{s}' tried to add component '{s}' without field '{s}'", .{
                    self.activeSystemId(),
                    payload.component_id,
                    field_definition.name,
                });
                return false;
            }
        }
        return true;
    }

    fn snapshotComponent(
        self: *Program,
        world: *runtime.World,
        entity: runtime.EntityHandle,
        component_id: []const u8,
    ) !?QueuedComponentSnapshot {
        if (!(try world.hasComponent(entity, component_id))) {
            return null;
        }

        const field_count = world.componentFieldCount(component_id);
        const fields = try self.allocator.alloc(QueuedComponentFieldValue, field_count);
        var initialized_fields: usize = 0;
        errdefer {
            for (fields[0..initialized_fields]) |*field| {
                field.deinit(self.allocator);
            }
            self.allocator.free(fields);
        }

        for (fields, 0..) |*out_field, index| {
            const field_name = world.componentFieldNameAt(component_id, index) orelse return error.UnknownField;
            const owned_name = try self.allocator.dupe(u8, field_name);
            const owned_value = cloneComponentValue(self.allocator, try world.getComponentFieldValue(entity, component_id, field_name)) catch |err| {
                self.allocator.free(owned_name);
                return err;
            };
            out_field.* = .{
                .name = owned_name,
                .value = owned_value,
            };
            initialized_fields += 1;
        }

        return .{
            .entity = entity,
            .component_id = try self.allocator.dupe(u8, component_id),
            .fields = fields,
        };
    }

    fn rollbackAppliedScriptCommands(self: *Program, world: *runtime.World, applied_commands: *std.ArrayList(AppliedScriptCommand)) void {
        var index = applied_commands.items.len;
        while (index > 0) {
            index -= 1;
            switch (applied_commands.items[index]) {
                .remove_added_component => |payload| {
                    _ = world.removeComponent(payload.entity, payload.component_id) catch {};
                },
                .restore_component => |snapshot| {
                    const fields = self.allocator.alloc(runtime.ComponentFieldValue, snapshot.fields.len) catch continue;
                    defer self.allocator.free(fields);
                    for (snapshot.fields, 0..) |field, field_index| {
                        fields[field_index] = field.asRuntime();
                    }
                    world.setComponent(snapshot.entity, snapshot.component_id, fields) catch {};
                },
            }
        }
    }

    fn clearAppliedScriptCommands(self: *Program, applied_commands: *std.ArrayList(AppliedScriptCommand)) void {
        for (applied_commands.items) |*command| {
            command.deinit(self.allocator);
        }
        applied_commands.deinit(self.allocator);
    }

    fn rollbackImmediateScriptSpawns(self: *Program, world: *runtime.World) void {
        var index = self.immediate_script_spawns.items.len;
        while (index > 0) {
            index -= 1;
            _ = world.removeEntity(self.immediate_script_spawns.items[index]) catch {};
        }
    }

    fn discardQueuedScriptCommands(self: *Program, world: *runtime.World) void {
        self.clearQueuedScriptCommands();
        self.rollbackImmediateScriptSpawns(world);
        self.immediate_script_spawns.clearRetainingCapacity();
    }

    fn clearQueuedScriptCommands(self: *Program) void {
        for (self.queued_script_commands.items) |*command| {
            command.deinit(self.allocator);
        }
        self.queued_script_commands.clearRetainingCapacity();
    }

    fn initializeSystemProfiles(self: *Program) !void {
        self.clearSystemProfiles();
        self.system_profile_snapshots.clearRetainingCapacity();

        const system_count = self.schedule.systemCount();
        try self.system_profiles.ensureTotalCapacity(self.allocator, system_count);
        try self.system_profile_snapshots.ensureTotalCapacity(self.allocator, system_count);

        for (self.schedule.batches) |batch| {
            for (batch.systems) |system| {
                const owned_id = try self.allocator.dupe(u8, system.id);
                self.system_profiles.appendAssumeCapacity(.{
                    .id = owned_id,
                    .phase = batch.phase,
                });
            }
        }
    }

    fn clearSystemProfiles(self: *Program) void {
        for (self.system_profiles.items) |*profile| {
            profile.deinit(self.allocator);
        }
        self.system_profiles.clearRetainingCapacity();
    }

    fn adoptNativeLibraries(self: *Program, libraries: []const NativeLibrary) !void {
        try self.native_libraries.ensureUnusedCapacity(self.allocator, libraries.len);
        for (libraries) |library| {
            self.native_libraries.appendAssumeCapacity(.{
                .path = library.path,
                .handle = library.handle,
            });
        }
    }

    fn recordSystemDuration(self: *Program, system: runtime.ScheduledSystem, phase: runtime.SystemPhase, duration_ns: u64) void {
        for (self.system_profiles.items) |*profile| {
            if (profile.phase == phase and std.mem.eql(u8, profile.id, system.id)) {
                profile.record(duration_ns);
                return;
            }
        }
    }

    fn activeSystemAllowsRead(self: Program, component_id: []const u8) bool {
        const active_system = self.active_system orelse return false;
        if (active_system.registry_index >= self.registry.systems.items.len) {
            return false;
        }

        const definition = self.registry.systems.items[active_system.registry_index];
        return containsString(definition.reads, component_id) or containsString(definition.writes, component_id);
    }

    fn activeSystemAllowsWrite(self: Program, component_id: []const u8) bool {
        const active_system = self.active_system orelse return false;
        if (active_system.registry_index >= self.registry.systems.items.len) {
            return false;
        }

        const definition = self.registry.systems.items[active_system.registry_index];
        return containsString(definition.writes, component_id);
    }

    fn activeSystemId(self: Program) []const u8 {
        const active_system = self.active_system orelse return "unknown";
        return active_system.id;
    }

    fn clearHostError(self: *Program) void {
        if (self.host_error) |message| {
            self.allocator.free(message);
            self.host_error = null;
        }
    }

    fn setHostError(self: *Program, comptime format: []const u8, args: anytype) void {
        self.clearHostError();
        const message = std.fmt.allocPrint(self.allocator, format, args) catch return;
        defer self.allocator.free(message);
        self.host_error = self.allocator.dupeZ(u8, message) catch null;
    }

    pub fn clearLastDiagnostic(self: *Program) void {
        if (self.last_diagnostic) |*diagnostic| {
            diagnostic.deinit(self.allocator);
            self.last_diagnostic = null;
        }
    }

    fn setRuntimeDiagnostic(self: *Program, system: runtime.ScheduledSystem, runner_ref: u32) !void {
        const origin = self.findSystemOrigin(system.id, runner_ref);
        const message = if (self.host_error) |message| message else lastLuauError(self.vm);
        const location = parseLuauDiagnosticPosition(message) orelse if (origin) |found| found.start else null;
        self.last_diagnostic = try makeDiagnostic(self.allocator, .{
            .stage = .runtime,
            .path = if (origin) |found| found.path else null,
            .system_id = system.id,
            .start = location,
            .message = message,
        });
    }

    fn setNativeRuntimeDiagnostic(self: *Program, system: runtime.ScheduledSystem) !void {
        self.last_diagnostic = try makeDiagnostic(self.allocator, .{
            .stage = .runtime,
            .system_id = system.id,
            .message = if (self.host_error) |message| message else "native system failed",
        });
    }

    fn findSystemOrigin(self: Program, system_id: []const u8, runner_ref: u32) ?ScriptOrigin {
        for (self.system_origins.items) |origin| {
            if (origin.runner_ref == runner_ref or std.mem.eql(u8, origin.id, system_id)) {
                return origin;
            }
        }
        return null;
    }
};

fn elapsedNanosecondsSince(started_ns: i128) u64 {
    const elapsed_ns = monotonicTimestampNs() - started_ns;
    if (elapsed_ns <= 0) {
        return 0;
    }
    return @intCast(@min(elapsed_ns, std.math.maxInt(u64)));
}

fn monotonicTimestampNs() i128 {
    const io = Io.Threaded.global_single_threaded.io();
    return Io.Timestamp.now(io, .awake).nanoseconds;
}

pub fn loadProjectProgram(
    io: Io,
    allocator: std.mem.Allocator,
    root_dir: Io.Dir,
    script_paths: []const []const u8,
) !Program {
    var result = try loadProjectProgramDetailedWithNative(io, allocator, root_dir, script_paths, .{});
    switch (result) {
        .program => |program| return program,
        .diagnostic => |*diagnostic| {
            diagnostic.deinit(allocator);
            return ScriptError.InvalidScript;
        },
    }
}

pub fn loadProjectProgramDetailed(
    io: Io,
    allocator: std.mem.Allocator,
    root_dir: Io.Dir,
    script_paths: []const []const u8,
) !LoadResult {
    return loadProjectProgramDetailedWithNative(io, allocator, root_dir, script_paths, .{});
}

pub fn loadProjectProgramDetailedWithNative(
    io: Io,
    allocator: std.mem.Allocator,
    root_dir: Io.Dir,
    script_paths: []const []const u8,
    native_extension: NativeExtension,
) !LoadResult {
    var program = try initProgram(allocator);
    errdefer program.deinit();
    try program.adoptNativeLibraries(native_extension.libraries);

    registerNativeComponents(&program, native_extension) catch |err| {
        const diagnostic = try nativeRegistrationDiagnostic(allocator, null, err);
        program.deinit();
        return .{ .diagnostic = diagnostic };
    };

    for (script_paths) |script_path| {
        const contents = try root_dir.readFileAlloc(io, script_path, allocator, .limited(256 * 1024));
        defer allocator.free(contents);
        if (try loadChunk(&program, script_path, contents)) |diagnostic| {
            program.deinit();
            return .{ .diagnostic = diagnostic };
        }
    }

    registerDeclaredComponents(&program) catch |err| {
        const diagnostic = try registrationDiagnostic(&program, err);
        program.deinit();
        return .{ .diagnostic = diagnostic };
    };
    registerNativeSystems(&program, native_extension) catch |err| {
        const diagnostic = try nativeRegistrationDiagnostic(allocator, failedNativeSystemId(native_extension, program.native_systems.items.len), err);
        program.deinit();
        return .{ .diagnostic = diagnostic };
    };
    registerDeclaredSystems(&program) catch |err| {
        const diagnostic = try registrationDiagnostic(&program, err);
        program.deinit();
        return .{ .diagnostic = diagnostic };
    };
    program.schedule = buildRuntimeSchedule(allocator, program.registry) catch |err| {
        const diagnostic = try makeDiagnostic(allocator, .{
            .stage = .schedule,
            .message = @errorName(err),
        });
        program.deinit();
        return .{ .diagnostic = diagnostic };
    };
    try program.initializeSystemProfiles();
    return .{ .program = program };
}

pub fn loadSourceProgram(
    allocator: std.mem.Allocator,
    chunk_name: []const u8,
    source: []const u8,
) !Program {
    return loadSourceProgramWithNative(allocator, chunk_name, source, .{});
}

pub fn loadSourceProgramWithNative(
    allocator: std.mem.Allocator,
    chunk_name: []const u8,
    source: []const u8,
    native_extension: NativeExtension,
) !Program {
    var program = try initProgram(allocator);
    errdefer program.deinit();
    try program.adoptNativeLibraries(native_extension.libraries);
    try registerNativeComponents(&program, native_extension);
    if (try loadChunk(&program, chunk_name, source)) |diagnostic| {
        var owned_diagnostic = diagnostic;
        owned_diagnostic.deinit(allocator);
        return ScriptError.InvalidScript;
    }
    try registerDeclaredComponents(&program);
    try registerNativeSystems(&program, native_extension);
    try registerDeclaredSystems(&program);
    program.schedule = try buildRuntimeSchedule(allocator, program.registry);
    try program.initializeSystemProfiles();
    return program;
}

pub fn buildRuntimeSchedule(
    allocator: std.mem.Allocator,
    registry: runtime.ComponentRegistry,
) !runtime.SystemSchedule {
    const script_phases = [_]runtime.SystemPhase{ .startup, .update };
    var batches: std.ArrayList(runtime.SystemBatch) = .empty;
    errdefer {
        for (batches.items) |batch| {
            for (batch.systems) |system| {
                allocator.free(system.id);
            }
            allocator.free(batch.systems);
        }
        batches.deinit(allocator);
    }

    for (script_phases) |phase| {
        const phase_schedule = try registry.buildSchedule(allocator, phase);
        var transferred: usize = 0;
        errdefer {
            for (phase_schedule.batches[transferred..]) |batch| {
                for (batch.systems) |system| {
                    allocator.free(system.id);
                }
                allocator.free(batch.systems);
            }
            allocator.free(phase_schedule.batches);
        }

        for (phase_schedule.batches) |batch| {
            try batches.append(allocator, batch);
            transferred += 1;
        }
        allocator.free(phase_schedule.batches);
    }

    return .{
        .allocator = allocator,
        .batches = try batches.toOwnedSlice(allocator),
    };
}

fn initProgram(allocator: std.mem.Allocator) !Program {
    const callbacks = c.machina_luau_callbacks{
        .query_next = queryNextCallback,
        .prepare_query = prepareQueryCallback,
        .query_next_prepared = queryNextPreparedCallback,
        .query_plan_generation = queryPlanGenerationCallback,
        .read_f32_view = readF32ViewCallback,
        .write_f32_view = writeF32ViewCallback,
        .read_vec3_view = readVec3ViewCallback,
        .write_vec3_view = writeVec3ViewCallback,
        .get_vec3 = getVec3Callback,
        .set_vec3 = setVec3Callback,
        .get_field = getFieldCallback,
        .get_field_resolved = getFieldResolvedCallback,
        .set_field = setFieldCallback,
        .set_field_resolved = setFieldResolvedCallback,
        .spawn_entity = spawnEntityCallback,
        .despawn_entity = despawnEntityCallback,
        .add_component = addComponentCallback,
        .remove_component = removeComponentCallback,
        .host_error = hostErrorCallback,
    };
    const vm = c.machina_luau_create(callbacks) orelse return ScriptError.InvalidScript;

    var registry = runtime.ComponentRegistry.init(allocator);
    errdefer {
        registry.deinit();
        c.machina_luau_destroy(vm);
    }
    try runtime.registerEngineComponents(&registry);

    return .{
        .allocator = allocator,
        .registry = registry,
        .schedule = .{ .allocator = allocator, .batches = &.{} },
        .vm = vm,
    };
}

fn registerNativeComponents(program: *Program, native_extension: NativeExtension) !void {
    for (native_extension.components) |definition| {
        try program.registry.registerProjectComponent(definition);
    }
}

fn registerNativeSystems(program: *Program, native_extension: NativeExtension) !void {
    for (native_extension.systems) |registration| {
        try registerNativeSystem(program, registration);
    }
}

fn registerNativeSystem(program: *Program, registration: NativeSystemRegistration) !void {
    if (program.registry.findSystem(registration.definition.id) != null) {
        return runtime.RegistryError.DuplicateSystemType;
    }

    const native_index = std.math.cast(u32, program.native_systems.items.len) orelse return ScriptError.InvalidScript;
    const owned_id = try program.allocator.dupeZ(u8, registration.definition.id);
    errdefer program.allocator.free(owned_id);

    try program.native_systems.append(program.allocator, .{
        .id = owned_id,
        .run = registration.run,
    });
    errdefer {
        var removed = program.native_systems.pop().?;
        removed.deinit(program.allocator);
    }

    var definition = registration.definition;
    definition.runner = .{ .native = native_index };
    try program.registry.registerProjectSystem(definition);
}

fn failedNativeSystemId(native_extension: NativeExtension, registered_native_systems: usize) ?[]const u8 {
    if (registered_native_systems < native_extension.systems.len) {
        return native_extension.systems[registered_native_systems].definition.id;
    }
    return null;
}

fn loadChunk(program: *Program, chunk_name: []const u8, source: []const u8) !?Diagnostic {
    const component_start = c.machina_luau_component_count(program.vm);
    const system_start = c.machina_luau_system_count(program.vm);
    const chunk_name_z = try program.allocator.dupeZ(u8, chunk_name);
    defer program.allocator.free(chunk_name_z);

    if (c.machina_luau_load(program.vm, chunk_name_z.ptr, source.ptr, source.len) == 0) {
        const message = lastLuauError(program.vm);
        return try makeDiagnostic(program.allocator, .{
            .stage = .load,
            .path = chunk_name,
            .start = parseLuauDiagnosticPosition(message),
            .message = message,
        });
    }

    try recordOrigins(program, chunk_name, component_start, system_start);
    return null;
}

fn registerDeclaredComponents(program: *Program) ScriptError!void {
    const component_count = c.machina_luau_component_count(program.vm);
    for (0..component_count) |component_index| {
        var fields: std.ArrayList(runtime.ComponentFieldDefinition) = .empty;
        defer fields.deinit(program.allocator);

        const field_count = c.machina_luau_component_field_count(program.vm, component_index);
        for (0..field_count) |field_index| {
            try fields.append(program.allocator, .{
                .name = try spanC(c.machina_luau_component_field_name(program.vm, component_index, field_index)),
                .value_type = try parseFieldType(try spanC(c.machina_luau_component_field_type(program.vm, component_index, field_index))),
            });
        }

        try program.registry.registerProjectComponent(.{
            .id = try spanC(c.machina_luau_component_id(program.vm, component_index)),
            .version = c.machina_luau_component_version(program.vm, component_index),
            .fields = fields.items,
        });
    }
}

fn registerDeclaredSystems(program: *Program) ScriptError!void {
    const system_count = c.machina_luau_system_count(program.vm);
    for (0..system_count) |system_index| {
        var reads = try readSystemReads(program.allocator, program.vm, system_index);
        defer reads.deinit(program.allocator);
        var writes = try readSystemWrites(program.allocator, program.vm, system_index);
        defer writes.deinit(program.allocator);
        var before = try readSystemBefore(program.allocator, program.vm, system_index);
        defer before.deinit(program.allocator);
        var after = try readSystemAfter(program.allocator, program.vm, system_index);
        defer after.deinit(program.allocator);

        const runner_ref = c.machina_luau_system_runner_ref(program.vm, system_index);
        try program.registry.registerProjectSystem(.{
            .id = try spanC(c.machina_luau_system_id(program.vm, system_index)),
            .phase = try parseSystemPhase(try spanC(c.machina_luau_system_phase(program.vm, system_index))),
            .reads = reads.items,
            .writes = writes.items,
            .before = before.items,
            .after = after.items,
            .runner = if (runner_ref == 0) .none else .{ .luau = runner_ref },
        });
    }
}

fn recordOrigins(program: *Program, path: []const u8, component_start: usize, system_start: usize) !void {
    const component_count = c.machina_luau_component_count(program.vm);
    for (component_start..component_count) |component_index| {
        {
            const id = try spanC(c.machina_luau_component_id(program.vm, component_index));
            const owned_id = try program.allocator.dupe(u8, id);
            errdefer program.allocator.free(owned_id);
            const owned_path = try program.allocator.dupe(u8, path);
            errdefer program.allocator.free(owned_path);
            const line = c.machina_luau_component_line(program.vm, component_index);
            try program.component_origins.append(program.allocator, .{
                .index = component_index,
                .id = owned_id,
                .path = owned_path,
                .start = diagnosticPositionFromLine(line),
            });
        }
    }

    const system_count = c.machina_luau_system_count(program.vm);
    for (system_start..system_count) |system_index| {
        {
            const id = try spanC(c.machina_luau_system_id(program.vm, system_index));
            const owned_id = try program.allocator.dupe(u8, id);
            errdefer program.allocator.free(owned_id);
            const owned_path = try program.allocator.dupe(u8, path);
            errdefer program.allocator.free(owned_path);
            const line = c.machina_luau_system_line(program.vm, system_index);
            try program.system_origins.append(program.allocator, .{
                .index = system_index,
                .id = owned_id,
                .path = owned_path,
                .start = diagnosticPositionFromLine(line),
                .runner_ref = c.machina_luau_system_runner_ref(program.vm, system_index),
            });
        }
    }
}

fn registrationDiagnostic(program: *Program, err: anyerror) !Diagnostic {
    const message = @errorName(err);
    if (program.system_origins.items.len > 0) {
        const origin = program.system_origins.items[program.system_origins.items.len - 1];
        return makeDiagnostic(program.allocator, .{
            .stage = .registration,
            .path = origin.path,
            .system_id = origin.id,
            .start = origin.start,
            .message = message,
        });
    }
    if (program.component_origins.items.len > 0) {
        const origin = program.component_origins.items[program.component_origins.items.len - 1];
        return makeDiagnostic(program.allocator, .{
            .stage = .registration,
            .path = origin.path,
            .start = origin.start,
            .message = message,
        });
    }
    return makeDiagnostic(program.allocator, .{
        .stage = .registration,
        .message = message,
    });
}

fn nativeRegistrationDiagnostic(allocator: std.mem.Allocator, system_id: ?[]const u8, err: anyerror) !Diagnostic {
    return makeDiagnostic(allocator, .{
        .stage = .native_registration,
        .path = "native",
        .system_id = system_id,
        .message = @errorName(err),
    });
}

const DiagnosticDraft = struct {
    stage: DiagnosticStage,
    path: ?[]const u8 = null,
    system_id: ?[]const u8 = null,
    start: ?DiagnosticPosition = null,
    end: ?DiagnosticPosition = null,
    message: []const u8,
};

fn makeDiagnostic(allocator: std.mem.Allocator, draft: DiagnosticDraft) !Diagnostic {
    const path = if (draft.path) |path_value| try allocator.dupe(u8, path_value) else null;
    errdefer if (path) |path_value| allocator.free(path_value);
    const system_id = if (draft.system_id) |system_id_value| try allocator.dupe(u8, system_id_value) else null;
    errdefer if (system_id) |system_id_value| allocator.free(system_id_value);
    return .{
        .stage = draft.stage,
        .path = path,
        .system_id = system_id,
        .start = draft.start,
        .end = draft.end,
        .message = try allocator.dupe(u8, draft.message),
    };
}

fn lastLuauError(vm: *c.machina_luau) []const u8 {
    return std.mem.span(c.machina_luau_last_error(vm));
}

fn diagnosticPositionFromLine(line: c_int) ?DiagnosticPosition {
    if (line <= 0) {
        return null;
    }
    return .{ .line = @intCast(line) };
}

fn parseLuauDiagnosticPosition(message: []const u8) ?DiagnosticPosition {
    var index = std.mem.indexOfScalar(u8, message, ':') orelse return null;
    while (index + 1 < message.len) {
        const number_start = index + 1;
        if (!std.ascii.isDigit(message[number_start])) {
            index = std.mem.indexOfScalarPos(u8, message, index + 1, ':') orelse return null;
            continue;
        }

        var number_end = number_start;
        while (number_end < message.len and std.ascii.isDigit(message[number_end])) {
            number_end += 1;
        }
        if (number_end >= message.len or message[number_end] != ':') {
            index = std.mem.indexOfScalarPos(u8, message, number_end, ':') orelse return null;
            continue;
        }

        const line = std.fmt.parseInt(u32, message[number_start..number_end], 10) catch return null;
        if (line == 0) {
            return null;
        }
        return .{ .line = line };
    }
    return null;
}

fn readSystemReads(allocator: std.mem.Allocator, vm: *c.machina_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.machina_luau_system_reads_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.machina_luau_system_reads_item(vm, system_index, item_index)));
    }
    return values;
}

fn readSystemWrites(allocator: std.mem.Allocator, vm: *c.machina_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.machina_luau_system_writes_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.machina_luau_system_writes_item(vm, system_index, item_index)));
    }
    return values;
}

fn readSystemBefore(allocator: std.mem.Allocator, vm: *c.machina_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.machina_luau_system_before_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.machina_luau_system_before_item(vm, system_index, item_index)));
    }
    return values;
}

fn readSystemAfter(allocator: std.mem.Allocator, vm: *c.machina_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.machina_luau_system_after_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.machina_luau_system_after_item(vm, system_index, item_index)));
    }
    return values;
}

fn spanC(value: ?[*:0]const u8) ScriptError![]const u8 {
    return std.mem.span(value orelse return ScriptError.InvalidScript);
}

fn hostErrorCallback(raw_context: ?*anyopaque) callconv(.c) [*c]const u8 {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return null));
    if (program.host_error) |message| {
        return message.ptr;
    }
    return null;
}

const NativeCallContext = struct {
    program: *Program,
    world: *runtime.World,
};

const native_system_api = native_api.SystemApi{
    .query_next = nativeQueryNext,
    .get_vec3 = nativeGetVec3,
    .set_vec3 = nativeSetVec3,
    .get_f32 = nativeGetF32,
    .set_f32 = nativeSetF32,
    .get_bool = nativeGetBool,
    .set_bool = nativeSetBool,
    .get_i32 = nativeGetI32,
    .set_i32 = nativeSetI32,
    .get_string = nativeGetString,
    .set_string = nativeSetString,
    .spawn_entity = nativeSpawnEntity,
    .despawn_entity = nativeDespawnEntity,
    .add_component = nativeAddComponent,
    .remove_component = nativeRemoveComponent,
    .host_error = nativeHostError,
};

fn nativeCallContext(raw_context: ?*anyopaque) ?*NativeCallContext {
    return @ptrCast(@alignCast(raw_context orelse return null));
}

fn nativeHostError(raw_context: ?*anyopaque) callconv(.c) ?[*:0]const u8 {
    const context = nativeCallContext(raw_context) orelse return null;
    if (context.program.host_error) |message| {
        return message.ptr;
    }
    return null;
}

fn nativeQueryNext(
    raw_context: ?*anyopaque,
    raw_component_ids: ?[*]const [*:0]const u8,
    component_count: usize,
    raw_cursor: *usize,
    out_entity: *native_api.Entity,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return -1;
    const program = context.program;
    const component_id_ptr = raw_component_ids orelse return -1;

    var component_ids_buffer: [16][]const u8 = undefined;
    if (component_count == 0 or component_count > component_ids_buffer.len) {
        program.setHostError("native system '{s}' tried to query {d} components; the host bridge supports at most {d}", .{
            program.activeSystemId(),
            component_count,
            component_ids_buffer.len,
        });
        return -1;
    }

    for (0..component_count) |index| {
        const component_id = std.mem.span(component_id_ptr[index]);
        if (!program.activeSystemAllowsRead(component_id)) {
            program.setHostError("native system '{s}' tried to query component '{s}' without declaring it in reads or writes", .{
                program.activeSystemId(),
                component_id,
            });
            return -1;
        }
        component_ids_buffer[index] = component_id;
    }

    const entity = context.world.queryNext(component_ids_buffer[0..component_count], raw_cursor) orelse return 0;
    out_entity.* = .{
        .index = entity.index,
        .generation = entity.generation,
    };
    return 1;
}

fn nativeGetVec3(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    out_value: *native_api.Vec3,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("native system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    const value = context.world.getVec3(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name) catch |err| {
        program.setHostError("native system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    out_value.* = .{ .x = value[0], .y = value[1], .z = value[2] };
    return 1;
}

fn nativeSetVec3(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    value: native_api.Vec3,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (!std.math.isFinite(value.x) or !std.math.isFinite(value.y) or !std.math.isFinite(value.z)) {
        program.setHostError("native system '{s}' tried to write non-finite vec3 value to '{s}.{s}'", .{
            program.activeSystemId(),
            component_id,
            field_name,
        });
        return 0;
    }
    context.world.setVec3(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name, .{
        value.x,
        value.y,
        value.z,
    }) catch |err| {
        program.setHostError("native system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeGetF32(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    out_value: *f32,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("native system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    out_value.* = context.world.getFloat(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name) catch |err| {
        program.setHostError("native system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeSetF32(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    value: f32,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (!std.math.isFinite(value)) {
        program.setHostError("native system '{s}' tried to write non-finite f32 value to '{s}.{s}'", .{
            program.activeSystemId(),
            component_id,
            field_name,
        });
        return 0;
    }
    context.world.setComponentFieldValue(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name, .{ .float = value }) catch |err| {
        program.setHostError("native system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeGetBool(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    out_value: *u8,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("native system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    const value = context.world.getBoolean(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name) catch |err| {
        program.setHostError("native system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    out_value.* = if (value) 1 else 0;
    return 1;
}

fn nativeSetBool(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    value: u8,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    context.world.setComponentFieldValue(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name, .{ .boolean = value != 0 }) catch |err| {
        program.setHostError("native system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeGetI32(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    out_value: *i32,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("native system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    out_value.* = context.world.getInt(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name) catch |err| {
        program.setHostError("native system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeSetI32(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    value: i32,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    context.world.setComponentFieldValue(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name, .{ .int = value }) catch |err| {
        program.setHostError("native system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeGetString(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    out_value: *native_api.StringView,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("native system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    const value = context.world.getString(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name) catch |err| {
        program.setHostError("native system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    out_value.* = native_api.StringView.fromSlice(value);
    return 1;
}

fn nativeSetString(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_field_name: [*:0]const u8,
    raw_value: native_api.StringView,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    const field_name = std.mem.span(raw_field_name);
    const value = raw_value.asSlice() orelse {
        program.setHostError("native system '{s}' tried to write invalid string value to '{s}.{s}'", .{
            program.activeSystemId(),
            component_id,
            field_name,
        });
        return 0;
    };
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    context.world.setComponentFieldValue(.{ .index = entity.index, .generation = entity.generation }, component_id, field_name, .{ .string = value }) catch |err| {
        program.setHostError("native system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn nativeSpawnEntity(
    raw_context: ?*anyopaque,
    raw_id: native_api.StringView,
    raw_name: native_api.StringView,
    out_entity: *native_api.Entity,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const id = raw_id.asSlice() orelse {
        program.setHostError("native system '{s}' tried to spawn an entity with an invalid id", .{program.activeSystemId()});
        return 0;
    };
    const name = raw_name.asSlice() orelse {
        program.setHostError("native system '{s}' tried to spawn entity '{s}' with an invalid name", .{ program.activeSystemId(), id });
        return 0;
    };

    const entity = context.world.createEntity(id, name) catch |err| {
        program.setHostError("native system '{s}' failed to spawn entity '{s}': {s}", .{
            program.activeSystemId(),
            id,
            @errorName(err),
        });
        return 0;
    };
    out_entity.* = .{ .index = entity.index, .generation = entity.generation };
    program.immediate_script_spawns.append(program.allocator, entity) catch {
        _ = context.world.removeEntity(entity) catch {};
        program.setHostError("native system '{s}' failed to record spawned entity '{s}': {s}", .{
            program.activeSystemId(),
            id,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    return 1;
}

fn nativeDespawnEntity(raw_context: ?*anyopaque, entity: native_api.Entity) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    return queueDespawnEntity(context.program, context.world, .{ .index = entity.index, .generation = entity.generation });
}

fn nativeAddComponent(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
    raw_fields: ?[*]const native_api.FieldValue,
    field_count: usize,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    const program = context.program;
    const component_id = std.mem.span(raw_component_id);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("native system '{s}' tried to add component '{s}' without declaring it in writes", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    }

    const definition = program.registry.findComponent(component_id) orelse {
        program.setHostError("native system '{s}' tried to add unknown component '{s}'", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    };
    const runtime_entity = runtime.EntityHandle{ .index = entity.index, .generation = entity.generation };
    _ = context.world.entity(runtime_entity) catch |err| {
        program.setHostError("native system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(err),
        });
        return 0;
    };
    const raw_slice = if (field_count == 0) &[_]native_api.FieldValue{} else (raw_fields orelse return 0)[0..field_count];
    const fields = program.allocator.alloc(QueuedComponentFieldValue, field_count) catch {
        program.setHostError("native system '{s}' failed to allocate component fields for '{s}'", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    };
    var initialized_fields: usize = 0;
    var fields_owned = true;
    defer {
        if (fields_owned) {
            for (fields[0..initialized_fields]) |*field| {
                field.deinit(program.allocator);
            }
            program.allocator.free(fields);
        }
    }

    for (raw_slice, 0..) |raw_field, index| {
        const field_name = std.mem.span(raw_field.name);
        const field_definition = findComponentField(definition.*, field_name) orelse {
            program.setHostError("native system '{s}' tried to add unknown field '{s}.{s}'", .{
                program.activeSystemId(),
                component_id,
                field_name,
            });
            return 0;
        };
        const component_value = componentValueFromNativeType(field_definition.value_type, raw_field) catch |err| {
            program.setHostError("native system '{s}' failed to convert value for '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
        const owned_field_name = program.allocator.dupe(u8, field_name) catch {
            program.setHostError("native system '{s}' failed to queue field name for '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(error.OutOfMemory),
            });
            return 0;
        };
        fields[index] = .{
            .name = owned_field_name,
            .value = cloneComponentValue(program.allocator, component_value) catch |err| {
                program.allocator.free(owned_field_name);
                program.setHostError("native system '{s}' failed to queue value for '{s}.{s}': {s}", .{
                    program.activeSystemId(),
                    component_id,
                    field_name,
                    @errorName(err),
                });
                return 0;
            },
        };
        initialized_fields += 1;
    }

    const owned_component_id = program.allocator.dupe(u8, component_id) catch {
        program.setHostError("native system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    var component_id_owned = true;
    defer {
        if (component_id_owned) {
            program.allocator.free(owned_component_id);
        }
    }

    program.queued_script_commands.append(program.allocator, .{ .add_component = .{
        .entity = runtime_entity,
        .component_id = owned_component_id,
        .fields = fields,
    } }) catch {
        program.setHostError("native system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    fields_owned = false;
    component_id_owned = false;
    return 1;
}

fn nativeRemoveComponent(
    raw_context: ?*anyopaque,
    entity: native_api.Entity,
    raw_component_id: [*:0]const u8,
) callconv(.c) c_int {
    const context = nativeCallContext(raw_context) orelse return 0;
    return queueRemoveComponent(context.program, context.world, .{ .index = entity.index, .generation = entity.generation }, std.mem.span(raw_component_id));
}

fn queryNextCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_ids: ?[*]const ?[*:0]const u8,
    component_count: usize,
    raw_cursor: ?*u32,
    raw_out_entity: ?*u32,
    raw_out_entity_generation: ?*u32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return -1));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return -1));
    const component_id_ptr = raw_component_ids orelse return -1;
    const cursor = raw_cursor orelse return -1;
    const out_entity = raw_out_entity orelse return -1;
    const out_entity_generation = raw_out_entity_generation orelse return -1;

    var component_ids_buffer: [16][]const u8 = undefined;
    if (component_count == 0 or component_count > component_ids_buffer.len) {
        program.setHostError("system '{s}' tried to query {d} components; the host bridge supports at most {d}", .{
            program.activeSystemId(),
            component_count,
            component_ids_buffer.len,
        });
        return -1;
    }

    for (0..component_count) |index| {
        const component_id = std.mem.span(component_id_ptr[index] orelse return -1);
        if (!program.activeSystemAllowsRead(component_id)) {
            program.setHostError("system '{s}' tried to query component '{s}' without declaring it in reads or writes", .{
                program.activeSystemId(),
                component_id,
            });
            return -1;
        }
        component_ids_buffer[index] = component_id;
    }

    var cursor_value: usize = cursor.*;
    const entity = world.queryNext(component_ids_buffer[0..component_count], &cursor_value) orelse return 0;
    cursor.* = @intCast(cursor_value);
    out_entity.* = entity.index;
    out_entity_generation.* = entity.generation;
    return 1;
}

fn prepareQueryCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_ids: ?[*]const ?[*:0]const u8,
    component_count: usize,
    raw_out_component_table_indices: ?[*]u32,
    raw_out_driver_table_index: ?*u32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return -1));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return -1));
    const component_id_ptr = raw_component_ids orelse return -1;
    const out_component_table_indices = raw_out_component_table_indices orelse return -1;
    const out_driver_table_index = raw_out_driver_table_index orelse return -1;

    var component_table_indices_buffer: [16]u32 = undefined;
    if (component_count == 0 or component_count > component_table_indices_buffer.len) {
        program.setHostError("system '{s}' tried to query {d} components; the host bridge supports at most {d}", .{
            program.activeSystemId(),
            component_count,
            component_table_indices_buffer.len,
        });
        return -1;
    }

    for (0..component_count) |index| {
        const component_id = std.mem.span(component_id_ptr[index] orelse return -1);
        if (!program.activeSystemAllowsRead(component_id)) {
            program.setHostError("system '{s}' tried to query component '{s}' without declaring it in reads or writes", .{
                program.activeSystemId(),
                component_id,
            });
            return -1;
        }

        const table_index = world.resolveComponentTableIndex(component_id) orelse return 0;
        component_table_indices_buffer[index] = table_index;
        out_component_table_indices[index] = table_index;
    }

    const driver_table_index = (world.queryDriverTableIndex(component_table_indices_buffer[0..component_count]) catch |err| {
        program.setHostError("system '{s}' failed to prepare query: {s}", .{
            program.activeSystemId(),
            @errorName(err),
        });
        return -1;
    }) orelse return 0;
    out_driver_table_index.* = driver_table_index;
    return 1;
}

fn queryNextPreparedCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_table_indices: ?[*]const u32,
    component_count: usize,
    driver_table_index: u32,
    raw_cursor: ?*u32,
    raw_out_entity: ?*u32,
    raw_out_entity_generation: ?*u32,
    raw_out_component_rows: ?[*]u32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return -1));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return -1));
    const component_table_indices_ptr = raw_component_table_indices orelse return -1;
    const cursor = raw_cursor orelse return -1;
    const out_entity = raw_out_entity orelse return -1;
    const out_entity_generation = raw_out_entity_generation orelse return -1;
    const out_component_rows_ptr = raw_out_component_rows orelse return -1;

    if (component_count == 0 or component_count > 16) {
        program.setHostError("system '{s}' tried to run prepared query with unsupported component count {d}", .{
            program.activeSystemId(),
            component_count,
        });
        return -1;
    }

    const component_table_indices = component_table_indices_ptr[0..component_count];
    const out_component_rows = out_component_rows_ptr[0..component_count];
    var cursor_value: usize = cursor.*;
    const entity = (world.queryNextResolved(component_table_indices, driver_table_index, &cursor_value, out_component_rows) catch |err| {
        program.setHostError("system '{s}' failed to run prepared query: {s}", .{
            program.activeSystemId(),
            @errorName(err),
        });
        return -1;
    }) orelse return 0;

    cursor.* = @intCast(cursor_value);
    out_entity.* = entity.index;
    out_entity_generation.* = entity.generation;
    return 1;
}

fn queryPlanGenerationCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
) callconv(.c) u64 {
    _ = raw_context;
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    return world.queryPlanGeneration();
}

fn readF32ViewCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    raw_entities: ?[*]const u32,
    raw_entity_generations: ?[*]const u32,
    raw_component_rows: ?[*]const u32,
    entity_count: usize,
    raw_field_name: ?[*:0]const u8,
    raw_out_values: ?[*]f32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("system '{s}' tried to bulk-read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (entity_count == 0) {
        return 1;
    }

    const entities = (raw_entities orelse return 0)[0..entity_count];
    const entity_generations = (raw_entity_generations orelse return 0)[0..entity_count];
    const component_rows = (raw_component_rows orelse return 0)[0..entity_count];
    const out_values = (raw_out_values orelse return 0)[0..entity_count];
    for (entities, entity_generations, component_rows, out_values) |entity_index, entity_generation, component_row_index, *out_value| {
        const value = world.getComponentFieldValueResolved(.{ .index = entity_index, .generation = entity_generation }, .{
            .table_index = component_table_index,
            .row_index = component_row_index,
        }, field_name) catch |err| {
            program.setHostError("system '{s}' failed to bulk-read '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
        out_value.* = switch (value) {
            .float => |payload| payload,
            else => {
                program.setHostError("system '{s}' tried to bulk-read non-f32 field '{s}.{s}' as f32", .{
                    program.activeSystemId(),
                    component_id,
                    field_name,
                });
                return 0;
            },
        };
    }
    return 1;
}

fn writeF32ViewCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    raw_entities: ?[*]const u32,
    raw_entity_generations: ?[*]const u32,
    raw_component_rows: ?[*]const u32,
    entity_count: usize,
    raw_field_name: ?[*:0]const u8,
    raw_values: ?[*]const f32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to bulk-write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (entity_count == 0) {
        return 1;
    }

    const entities = (raw_entities orelse return 0)[0..entity_count];
    const entity_generations = (raw_entity_generations orelse return 0)[0..entity_count];
    const component_rows = (raw_component_rows orelse return 0)[0..entity_count];
    const values = (raw_values orelse return 0)[0..entity_count];
    for (entities, entity_generations, component_rows, values) |entity_index, entity_generation, component_row_index, value| {
        if (!std.math.isFinite(value)) {
            program.setHostError("system '{s}' tried to bulk-write non-finite f32 value to '{s}.{s}'", .{
                program.activeSystemId(),
                component_id,
                field_name,
            });
            return 0;
        }
        world.setComponentFieldValueResolved(.{ .index = entity_index, .generation = entity_generation }, .{
            .table_index = component_table_index,
            .row_index = component_row_index,
        }, field_name, .{ .float = value }) catch |err| {
            program.setHostError("system '{s}' failed to bulk-write '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
    }
    return 1;
}

fn readVec3ViewCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    raw_entities: ?[*]const u32,
    raw_entity_generations: ?[*]const u32,
    raw_component_rows: ?[*]const u32,
    entity_count: usize,
    raw_field_name: ?[*:0]const u8,
    raw_out_values: ?[*]f32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("system '{s}' tried to bulk-read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (entity_count == 0) {
        return 1;
    }

    const entities = (raw_entities orelse return 0)[0..entity_count];
    const entity_generations = (raw_entity_generations orelse return 0)[0..entity_count];
    const component_rows = (raw_component_rows orelse return 0)[0..entity_count];
    const out_values = (raw_out_values orelse return 0)[0 .. entity_count * 3];
    for (entities, entity_generations, component_rows, 0..) |entity_index, entity_generation, component_row_index, entity_offset| {
        const value = world.getComponentFieldValueResolved(.{ .index = entity_index, .generation = entity_generation }, .{
            .table_index = component_table_index,
            .row_index = component_row_index,
        }, field_name) catch |err| {
            program.setHostError("system '{s}' failed to bulk-read '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
        const vec3 = switch (value) {
            .vec3 => |payload| payload,
            else => {
                program.setHostError("system '{s}' tried to bulk-read non-vec3 field '{s}.{s}' as vec3", .{
                    program.activeSystemId(),
                    component_id,
                    field_name,
                });
                return 0;
            },
        };
        const value_offset = entity_offset * 3;
        out_values[value_offset + 0] = vec3[0];
        out_values[value_offset + 1] = vec3[1];
        out_values[value_offset + 2] = vec3[2];
    }
    return 1;
}

fn writeVec3ViewCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    raw_entities: ?[*]const u32,
    raw_entity_generations: ?[*]const u32,
    raw_component_rows: ?[*]const u32,
    entity_count: usize,
    raw_field_name: ?[*:0]const u8,
    raw_values: ?[*]const f32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to bulk-write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    if (entity_count == 0) {
        return 1;
    }

    const entities = (raw_entities orelse return 0)[0..entity_count];
    const entity_generations = (raw_entity_generations orelse return 0)[0..entity_count];
    const component_rows = (raw_component_rows orelse return 0)[0..entity_count];
    const values = (raw_values orelse return 0)[0 .. entity_count * 3];
    for (entities, entity_generations, component_rows, 0..) |entity_index, entity_generation, component_row_index, entity_offset| {
        const value_offset = entity_offset * 3;
        const value = [3]f32{
            values[value_offset + 0],
            values[value_offset + 1],
            values[value_offset + 2],
        };
        if (!std.math.isFinite(value[0]) or !std.math.isFinite(value[1]) or !std.math.isFinite(value[2])) {
            program.setHostError("system '{s}' tried to bulk-write non-finite vec3 value to '{s}.{s}'", .{
                program.activeSystemId(),
                component_id,
                field_name,
            });
            return 0;
        }
        world.setComponentFieldValueResolved(.{ .index = entity_index, .generation = entity_generation }, .{
            .table_index = component_table_index,
            .row_index = component_row_index,
        }, field_name, .{ .vec3 = value }) catch |err| {
            program.setHostError("system '{s}' failed to bulk-write '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
    }
    return 1;
}

fn getVec3Callback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_out_value: ?[*]f32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    const out_value = raw_out_value orelse return 0;
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    const value = world.getVec3(.{ .index = entity_index, .generation = entity_generation }, component_id, field_name) catch |err| {
        program.setHostError("system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    out_value[0] = value[0];
    out_value[1] = value[1];
    out_value[2] = value[2];
    return 1;
}

fn setVec3Callback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_value: ?[*]const f32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    const value = raw_value orelse return 0;
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }
    world.setVec3(.{ .index = entity_index, .generation = entity_generation }, component_id, field_name, .{
        value[0],
        value[1],
        value[2],
    }) catch |err| {
        program.setHostError("system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn writeLuauFieldValue(out_value: *c.machina_luau_field_value, value: runtime.ComponentValue) void {
    out_value.* = .{
        .tag = 0,
        .boolean_value = 0,
        .int_value = 0,
        .number_value = 0,
        .string_data = null,
        .string_len = 0,
        .vec3_value = .{ 0.0, 0.0, 0.0 },
    };

    switch (value) {
        .boolean => |payload| {
            out_value.tag = c.MACHINA_LUAU_FIELD_BOOLEAN;
            out_value.boolean_value = if (payload) 1 else 0;
        },
        .int => |payload| {
            out_value.tag = c.MACHINA_LUAU_FIELD_INT;
            out_value.int_value = payload;
        },
        .float => |payload| {
            out_value.tag = c.MACHINA_LUAU_FIELD_FLOAT;
            out_value.number_value = payload;
        },
        .vec3 => |payload| {
            out_value.tag = c.MACHINA_LUAU_FIELD_VEC3;
            out_value.vec3_value = payload;
        },
        .string => |payload| {
            out_value.tag = c.MACHINA_LUAU_FIELD_STRING;
            out_value.string_data = payload.ptr;
            out_value.string_len = payload.len;
        },
    }
}

fn getFieldCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_out_value: ?*c.machina_luau_field_value,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    const out_value = raw_out_value orelse return 0;
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }

    const value = world.getComponentFieldValue(.{ .index = entity_index, .generation = entity_generation }, component_id, field_name) catch |err| {
        program.setHostError("system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    writeLuauFieldValue(out_value, value);
    return 1;
}

fn getFieldResolvedCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    component_row_index: u32,
    raw_field_name: ?[*:0]const u8,
    raw_out_value: ?*c.machina_luau_field_value,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    const out_value = raw_out_value orelse return 0;
    if (!program.activeSystemAllowsRead(component_id)) {
        program.setHostError("system '{s}' tried to read '{s}.{s}' without declaring '{s}' in reads or writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }

    const value = world.getComponentFieldValueResolved(.{ .index = entity_index, .generation = entity_generation }, .{
        .table_index = component_table_index,
        .row_index = component_row_index,
    }, field_name) catch |err| {
        program.setHostError("system '{s}' failed to read '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    writeLuauFieldValue(out_value, value);
    return 1;
}

fn setFieldCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    raw_field_name: ?[*:0]const u8,
    raw_value: ?*const c.machina_luau_field_value,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    const value = raw_value orelse return 0;
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }

    const component_value = componentValueFromLuau(world, .{ .index = entity_index, .generation = entity_generation }, component_id, field_name, value) catch |err| {
        program.setHostError("system '{s}' failed to convert value for '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    world.setComponentFieldValue(.{ .index = entity_index, .generation = entity_generation }, component_id, field_name, component_value) catch |err| {
        program.setHostError("system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn setFieldResolvedCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    component_table_index: u32,
    component_row_index: u32,
    raw_field_name: ?[*:0]const u8,
    raw_value: ?*const c.machina_luau_field_value,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    const field_name = std.mem.span(raw_field_name orelse return 0);
    const value = raw_value orelse return 0;
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to write '{s}.{s}' without declaring '{s}' in writes", .{
            program.activeSystemId(),
            component_id,
            field_name,
            component_id,
        });
        return 0;
    }

    const resolved = runtime.ResolvedComponentRow{
        .table_index = component_table_index,
        .row_index = component_row_index,
    };
    const entity = runtime.EntityHandle{ .index = entity_index, .generation = entity_generation };
    const component_value = componentValueFromLuauResolved(world, entity, resolved, field_name, value) catch |err| {
        program.setHostError("system '{s}' failed to convert value for '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    world.setComponentFieldValueResolved(entity, resolved, field_name, component_value) catch |err| {
        program.setHostError("system '{s}' failed to write '{s}.{s}': {s}", .{
            program.activeSystemId(),
            component_id,
            field_name,
            @errorName(err),
        });
        return 0;
    };
    return 1;
}

fn spawnEntityCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    raw_id: ?[*:0]const u8,
    raw_name: ?[*:0]const u8,
    raw_out_entity: ?*u32,
    raw_out_entity_generation: ?*u32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const id = std.mem.span(raw_id orelse return 0);
    const name = std.mem.span(raw_name orelse return 0);
    const out_entity = raw_out_entity orelse return 0;
    const out_entity_generation = raw_out_entity_generation orelse return 0;

    const entity = world.createEntity(id, name) catch |err| {
        program.setHostError("system '{s}' failed to spawn entity '{s}': {s}", .{
            program.activeSystemId(),
            id,
            @errorName(err),
        });
        return 0;
    };
    out_entity.* = entity.index;
    out_entity_generation.* = entity.generation;
    program.immediate_script_spawns.append(program.allocator, entity) catch {
        _ = world.removeEntity(entity) catch {};
        program.setHostError("system '{s}' failed to record spawned entity '{s}': {s}", .{
            program.activeSystemId(),
            id,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    return 1;
}

fn despawnEntityCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const entity = runtime.EntityHandle{ .index = entity_index, .generation = entity_generation };
    _ = world.entity(entity) catch |err| {
        program.setHostError("system '{s}' failed to despawn entity {d}: {s}", .{
            program.activeSystemId(),
            entity_index,
            @errorName(err),
        });
        return 0;
    };

    var components = world.entityComponents(entity) catch |err| {
        program.setHostError("system '{s}' failed to inspect entity {d}: {s}", .{
            program.activeSystemId(),
            entity_index,
            @errorName(err),
        });
        return 0;
    };
    while (components.next()) |component_id| {
        if (!program.activeSystemAllowsWrite(component_id)) {
            program.setHostError("system '{s}' tried to despawn entity {d} without declaring write access to '{s}'", .{
                program.activeSystemId(),
                entity_index,
                component_id,
            });
            return 0;
        }
    }

    program.queued_script_commands.append(program.allocator, .{ .despawn_entity = entity }) catch {
        program.setHostError("system '{s}' failed to queue despawn entity {d}: {s}", .{
            program.activeSystemId(),
            entity_index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    return 1;
}

fn addComponentCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
    raw_fields: ?[*]const c.machina_luau_component_field_value,
    field_count: usize,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to add component '{s}' without declaring it in writes", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    }

    const definition = program.registry.findComponent(component_id) orelse {
        program.setHostError("system '{s}' tried to add unknown component '{s}'", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    };
    const entity = runtime.EntityHandle{ .index = entity_index, .generation = entity_generation };
    _ = world.entity(entity) catch |err| {
        program.setHostError("system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(err),
        });
        return 0;
    };
    const raw_slice = if (field_count == 0) &[_]c.machina_luau_component_field_value{} else (raw_fields orelse return 0)[0..field_count];
    const fields = program.allocator.alloc(QueuedComponentFieldValue, field_count) catch {
        program.setHostError("system '{s}' failed to allocate component fields for '{s}'", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    };
    var initialized_fields: usize = 0;
    var fields_owned = true;
    defer {
        if (fields_owned) {
            for (fields[0..initialized_fields]) |*field| {
                field.deinit(program.allocator);
            }
            program.allocator.free(fields);
        }
    }

    for (raw_slice, 0..) |raw_field, index| {
        const field_name = raw_field.name[0..raw_field.name_len];
        const field_definition = findComponentField(definition.*, field_name) orelse {
            program.setHostError("system '{s}' tried to add unknown field '{s}.{s}'", .{
                program.activeSystemId(),
                component_id,
                field_name,
            });
            return 0;
        };
        const component_value = componentValueFromLuauType(field_definition.value_type, &raw_field.value) catch |err| {
            program.setHostError("system '{s}' failed to convert value for '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(err),
            });
            return 0;
        };
        const owned_field_name = program.allocator.dupe(u8, field_name) catch {
            program.setHostError("system '{s}' failed to queue field name for '{s}.{s}': {s}", .{
                program.activeSystemId(),
                component_id,
                field_name,
                @errorName(error.OutOfMemory),
            });
            return 0;
        };
        fields[index] = .{
            .name = owned_field_name,
            .value = cloneComponentValue(program.allocator, component_value) catch |err| {
                program.allocator.free(owned_field_name);
                program.setHostError("system '{s}' failed to queue value for '{s}.{s}': {s}", .{
                    program.activeSystemId(),
                    component_id,
                    field_name,
                    @errorName(err),
                });
                return 0;
            },
        };
        initialized_fields += 1;
    }

    const owned_component_id = program.allocator.dupe(u8, component_id) catch {
        program.setHostError("system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    var component_id_owned = true;
    defer {
        if (component_id_owned) {
            program.allocator.free(owned_component_id);
        }
    }

    program.queued_script_commands.append(program.allocator, .{ .add_component = .{
        .entity = entity,
        .component_id = owned_component_id,
        .fields = fields,
    } }) catch {
        program.setHostError("system '{s}' failed to queue add component '{s}' to entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    fields_owned = false;
    component_id_owned = false;
    return 1;
}

fn removeComponentCallback(
    raw_context: ?*anyopaque,
    raw_world: ?*anyopaque,
    entity_index: u32,
    entity_generation: u32,
    raw_component_id: ?[*:0]const u8,
) callconv(.c) c_int {
    const program: *Program = @ptrCast(@alignCast(raw_context orelse return 0));
    const world: *runtime.World = @ptrCast(@alignCast(raw_world orelse return 0));
    const component_id = std.mem.span(raw_component_id orelse return 0);
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to remove component '{s}' without declaring it in writes", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    }
    const entity = runtime.EntityHandle{ .index = entity_index, .generation = entity_generation };
    _ = world.entity(entity) catch |err| {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(err),
        });
        return 0;
    };
    const owned_component_id = program.allocator.dupe(u8, component_id) catch {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    var component_id_owned = true;
    defer {
        if (component_id_owned) {
            program.allocator.free(owned_component_id);
        }
    }
    program.queued_script_commands.append(program.allocator, .{ .remove_component = .{
        .entity = entity,
        .component_id = owned_component_id,
    } }) catch {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity_index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    component_id_owned = false;
    return 1;
}

fn queueDespawnEntity(program: *Program, world: *runtime.World, entity: runtime.EntityHandle) c_int {
    _ = world.entity(entity) catch |err| {
        program.setHostError("system '{s}' failed to despawn entity {d}: {s}", .{
            program.activeSystemId(),
            entity.index,
            @errorName(err),
        });
        return 0;
    };

    var components = world.entityComponents(entity) catch |err| {
        program.setHostError("system '{s}' failed to inspect entity {d}: {s}", .{
            program.activeSystemId(),
            entity.index,
            @errorName(err),
        });
        return 0;
    };
    while (components.next()) |component_id| {
        if (!program.activeSystemAllowsWrite(component_id)) {
            program.setHostError("system '{s}' tried to despawn entity {d} without declaring write access to '{s}'", .{
                program.activeSystemId(),
                entity.index,
                component_id,
            });
            return 0;
        }
    }

    program.queued_script_commands.append(program.allocator, .{ .despawn_entity = entity }) catch {
        program.setHostError("system '{s}' failed to queue despawn entity {d}: {s}", .{
            program.activeSystemId(),
            entity.index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    return 1;
}

fn queueRemoveComponent(program: *Program, world: *runtime.World, entity: runtime.EntityHandle, component_id: []const u8) c_int {
    if (!program.activeSystemAllowsWrite(component_id)) {
        program.setHostError("system '{s}' tried to remove component '{s}' without declaring it in writes", .{
            program.activeSystemId(),
            component_id,
        });
        return 0;
    }
    _ = world.entity(entity) catch |err| {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(err),
        });
        return 0;
    };
    const owned_component_id = program.allocator.dupe(u8, component_id) catch {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    var component_id_owned = true;
    defer {
        if (component_id_owned) {
            program.allocator.free(owned_component_id);
        }
    }
    program.queued_script_commands.append(program.allocator, .{ .remove_component = .{
        .entity = entity,
        .component_id = owned_component_id,
    } }) catch {
        program.setHostError("system '{s}' failed to queue remove component '{s}' from entity {d}: {s}", .{
            program.activeSystemId(),
            component_id,
            entity.index,
            @errorName(error.OutOfMemory),
        });
        return 0;
    };
    component_id_owned = false;
    return 1;
}

fn componentValueFromLuau(
    world: *runtime.World,
    entity: runtime.EntityHandle,
    component_id: []const u8,
    field_name: []const u8,
    value: *const c.machina_luau_field_value,
) !runtime.ComponentValue {
    return switch (value.tag) {
        c.MACHINA_LUAU_FIELD_BOOLEAN => .{ .boolean = value.boolean_value != 0 },
        c.MACHINA_LUAU_FIELD_STRING => .{ .string = stringFromLuau(value) },
        c.MACHINA_LUAU_FIELD_VEC3 => blk: {
            const vec3 = value.vec3_value;
            if (!std.math.isFinite(vec3[0]) or !std.math.isFinite(vec3[1]) or !std.math.isFinite(vec3[2])) {
                return ScriptError.InvalidScript;
            }
            break :blk .{ .vec3 = .{ vec3[0], vec3[1], vec3[2] } };
        },
        c.MACHINA_LUAU_FIELD_NUMBER => blk: {
            if (!std.math.isFinite(value.number_value)) {
                return ScriptError.InvalidScript;
            }

            const current = try world.getComponentFieldValue(entity, component_id, field_name);
            break :blk switch (current) {
                .int => .{ .int = try i32FromLuauNumber(value.number_value) },
                .float => .{ .float = try f32FromLuauNumber(value.number_value) },
                else => return ScriptError.InvalidScript,
            };
        },
        else => ScriptError.InvalidScript,
    };
}

fn componentValueFromLuauResolved(
    world: *runtime.World,
    entity: runtime.EntityHandle,
    resolved: runtime.ResolvedComponentRow,
    field_name: []const u8,
    value: *const c.machina_luau_field_value,
) !runtime.ComponentValue {
    return switch (value.tag) {
        c.MACHINA_LUAU_FIELD_BOOLEAN => .{ .boolean = value.boolean_value != 0 },
        c.MACHINA_LUAU_FIELD_STRING => .{ .string = stringFromLuau(value) },
        c.MACHINA_LUAU_FIELD_VEC3 => blk: {
            const vec3 = value.vec3_value;
            if (!std.math.isFinite(vec3[0]) or !std.math.isFinite(vec3[1]) or !std.math.isFinite(vec3[2])) {
                return ScriptError.InvalidScript;
            }
            break :blk .{ .vec3 = .{ vec3[0], vec3[1], vec3[2] } };
        },
        c.MACHINA_LUAU_FIELD_NUMBER => blk: {
            if (!std.math.isFinite(value.number_value)) {
                return ScriptError.InvalidScript;
            }

            const current = try world.getComponentFieldValueResolved(entity, resolved, field_name);
            break :blk switch (current) {
                .int => .{ .int = try i32FromLuauNumber(value.number_value) },
                .float => .{ .float = try f32FromLuauNumber(value.number_value) },
                else => return ScriptError.InvalidScript,
            };
        },
        else => ScriptError.InvalidScript,
    };
}

fn componentValueFromLuauType(field_type: runtime.FieldType, value: *const c.machina_luau_field_value) !runtime.ComponentValue {
    return switch (field_type) {
        .boolean => switch (value.tag) {
            c.MACHINA_LUAU_FIELD_BOOLEAN => .{ .boolean = value.boolean_value != 0 },
            else => ScriptError.InvalidScript,
        },
        .string => switch (value.tag) {
            c.MACHINA_LUAU_FIELD_STRING => .{ .string = stringFromLuau(value) },
            else => ScriptError.InvalidScript,
        },
        .vec3 => switch (value.tag) {
            c.MACHINA_LUAU_FIELD_VEC3 => blk: {
                const vec3 = value.vec3_value;
                if (!std.math.isFinite(vec3[0]) or !std.math.isFinite(vec3[1]) or !std.math.isFinite(vec3[2])) {
                    return ScriptError.InvalidScript;
                }
                break :blk .{ .vec3 = .{ vec3[0], vec3[1], vec3[2] } };
            },
            else => ScriptError.InvalidScript,
        },
        .int => switch (value.tag) {
            c.MACHINA_LUAU_FIELD_NUMBER => .{ .int = try i32FromLuauNumber(value.number_value) },
            c.MACHINA_LUAU_FIELD_INT => .{ .int = value.int_value },
            else => ScriptError.InvalidScript,
        },
        .float => switch (value.tag) {
            c.MACHINA_LUAU_FIELD_NUMBER => .{ .float = try f32FromLuauNumber(value.number_value) },
            c.MACHINA_LUAU_FIELD_FLOAT => .{ .float = @floatCast(value.number_value) },
            else => ScriptError.InvalidScript,
        },
    };
}

fn componentValueFromNativeType(field_type: runtime.FieldType, value: native_api.FieldValue) !runtime.ComponentValue {
    return switch (field_type) {
        .boolean => switch (value.field_type) {
            .boolean => .{ .boolean = value.boolean_value != 0 },
            else => ScriptError.InvalidScript,
        },
        .int => switch (value.field_type) {
            .int => .{ .int = value.int_value },
            else => ScriptError.InvalidScript,
        },
        .float => switch (value.field_type) {
            .float => blk: {
                if (!std.math.isFinite(value.float_value)) {
                    return ScriptError.InvalidScript;
                }
                break :blk .{ .float = value.float_value };
            },
            else => ScriptError.InvalidScript,
        },
        .vec3 => switch (value.field_type) {
            .vec3 => blk: {
                const vec3 = value.vec3_value;
                if (!std.math.isFinite(vec3.x) or !std.math.isFinite(vec3.y) or !std.math.isFinite(vec3.z)) {
                    return ScriptError.InvalidScript;
                }
                break :blk .{ .vec3 = .{ vec3.x, vec3.y, vec3.z } };
            },
            else => ScriptError.InvalidScript,
        },
        .string => switch (value.field_type) {
            .string => .{ .string = value.string_value.asSlice() orelse return ScriptError.InvalidScript },
            else => ScriptError.InvalidScript,
        },
    };
}

fn findComponentField(definition: runtime.ComponentDefinition, field_name: []const u8) ?runtime.ComponentFieldDefinition {
    for (definition.fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return field;
        }
    }
    return null;
}

fn stringFromLuau(value: *const c.machina_luau_field_value) []const u8 {
    if (value.string_len == 0) {
        return "";
    }
    return value.string_data[0..value.string_len];
}

fn cloneComponentValue(allocator: std.mem.Allocator, value: runtime.ComponentValue) !runtime.ComponentValue {
    return switch (value) {
        .boolean => |payload| .{ .boolean = payload },
        .int => |payload| .{ .int = payload },
        .float => |payload| .{ .float = payload },
        .vec3 => |payload| .{ .vec3 = payload },
        .string => |payload| .{ .string = try allocator.dupe(u8, payload) },
    };
}

fn i32FromLuauNumber(value: f64) !i32 {
    if (!std.math.isFinite(value)) {
        return ScriptError.InvalidScript;
    }
    const min = @as(f64, @floatFromInt(std.math.minInt(i32)));
    const max = @as(f64, @floatFromInt(std.math.maxInt(i32)));
    if (value < min or value > max or value != @floor(value)) {
        return ScriptError.InvalidScript;
    }
    return @intFromFloat(value);
}

fn f32FromLuauNumber(value: f64) !f32 {
    if (!std.math.isFinite(value)) {
        return ScriptError.InvalidScript;
    }
    const narrowed: f32 = @floatCast(value);
    if (!std.math.isFinite(narrowed)) {
        return ScriptError.InvalidScript;
    }
    return narrowed;
}

fn parseFieldType(value: []const u8) ScriptError!runtime.FieldType {
    if (std.mem.eql(u8, value, "boolean") or std.mem.eql(u8, value, "bool")) {
        return .boolean;
    }
    if (std.mem.eql(u8, value, "int") or std.mem.eql(u8, value, "i32")) {
        return .int;
    }
    if (std.mem.eql(u8, value, "float") or std.mem.eql(u8, value, "f32")) {
        return .float;
    }
    if (std.mem.eql(u8, value, "vec3")) {
        return .vec3;
    }
    if (std.mem.eql(u8, value, "string")) {
        return .string;
    }
    return ScriptError.UnknownFieldType;
}

fn parseSystemPhase(value: []const u8) ScriptError!runtime.SystemPhase {
    if (std.mem.eql(u8, value, "startup")) {
        return .startup;
    }
    if (std.mem.eql(u8, value, "update")) {
        return .update;
    }
    if (std.mem.eql(u8, value, "fixed_update")) {
        return .fixed_update;
    }
    if (std.mem.eql(u8, value, "render")) {
        return .render;
    }
    return ScriptError.UnknownSystemPhase;
}

fn containsString(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, needle)) {
            return true;
        }
    }
    return false;
}

fn containsEntityHandle(values: []const runtime.EntityHandle, needle: runtime.EntityHandle) bool {
    for (values) |value| {
        if (value.index == needle.index and value.generation == needle.generation) {
            return true;
        }
    }
    return false;
}

fn testNativeMoveSystem(context: *NativeSystemContext) callconv(.c) c_int {
    const component_ids = [_][*:0]const u8{ "machina.transform", "velocity", "boost" };
    var cursor: usize = 0;
    while (native_api.queryNext(context, component_ids[0..], &cursor) catch return 0) |entity| {
        const position = native_api.getVec3(context, entity, "machina.transform", "position") catch return 0;
        const velocity = native_api.getVec3(context, entity, "velocity", "linear") catch return 0;
        const boost = native_api.getF32(context, entity, "boost", "amount") catch return 0;
        native_api.setVec3(context, entity, "machina.transform", "position", position.addScaled(velocity, boost * context.delta_seconds)) catch return 0;
    }
    return 1;
}

fn testFailingNativeSystem(context: *NativeSystemContext) callconv(.c) c_int {
    _ = context;
    return 0;
}

fn testNativeLifecycleSystem(context: *NativeSystemContext) callconv(.c) c_int {
    const stats_query = [_][*:0]const u8{"native_stats"};
    var stats_cursor: usize = 0;
    while (native_api.queryNext(context, stats_query[0..], &stats_cursor) catch return 0) |stats_entity| {
        const ready = native_api.getBool(context, stats_entity, "native_stats", "ready") catch return 0;
        const label = native_api.getString(context, stats_entity, "native_stats", "label") catch return 0;
        const gain = native_api.getF32(context, stats_entity, "native_stats", "gain") catch return 0;
        const direction = native_api.getVec3(context, stats_entity, "native_stats", "direction") catch return 0;
        const previous_spawned = native_api.getI32(context, stats_entity, "native_stats", "spawned_count") catch return 0;
        if (!ready or !std.mem.eql(u8, label, "ready")) {
            return 0;
        }

        const survivor = native_api.spawnEntity(context, "native-survivor", "Native Survivor") catch return 0;
        const payload_fields = [_]native_api.FieldValue{
            native_api.FieldValue.int("count", previous_spawned + 7),
            native_api.FieldValue.boolean("enabled", true),
            native_api.FieldValue.float("speed", gain + 0.25),
            native_api.FieldValue.vec3("direction", direction.addScaled(.{ .x = 1.0, .y = 0.0, .z = -1.0 }, 2.0)),
            native_api.FieldValue.string("label", "spawned"),
        };
        native_api.addComponent(context, survivor, "native_payload", payload_fields[0..]) catch return 0;

        const doomed = native_api.spawnEntity(context, "native-doomed", "Native Doomed") catch return 0;
        const marker_fields = [_]native_api.FieldValue{
            native_api.FieldValue.int("value", 3),
        };
        native_api.addComponent(context, doomed, "native_marker", marker_fields[0..]) catch return 0;
        native_api.despawnEntity(context, doomed) catch return 0;

        const marker_query = [_][*:0]const u8{"native_marker"};
        var marker_cursor: usize = 0;
        var removed_count: i32 = 0;
        while (native_api.queryNext(context, marker_query[0..], &marker_cursor) catch return 0) |marker_entity| {
            native_api.removeComponent(context, marker_entity, "native_marker") catch return 0;
            removed_count += 1;
            break;
        }

        native_api.setI32(context, stats_entity, "native_stats", "spawned_count", 2) catch return 0;
        native_api.setI32(context, stats_entity, "native_stats", "removed_count", removed_count) catch return 0;
        native_api.setI32(context, stats_entity, "native_stats", "despawned_count", 1) catch return 0;
        native_api.setBool(context, stats_entity, "native_stats", "ready", false) catch return 0;
        native_api.setString(context, stats_entity, "native_stats", "label", "done") catch return 0;
        native_api.setF32(context, stats_entity, "native_stats", "gain", gain + 1.0) catch return 0;
        native_api.setVec3(context, stats_entity, "native_stats", "direction", direction.addScaled(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, 1.5)) catch return 0;
    }
    return 1;
}

test "luau declarations register components and executable systems" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\local RotatingCubes = ecs.query(Transform, Spin)
        \\
        \\ecs.system("rotate_cubes", {
        \\  phase = "update",
        \\  query = RotatingCubes,
        \\  writes = ecs.refs(Transform),
        \\  run = function(world, dt)
        \\    for _entity, transform, spin in RotatingCubes:iter(world) do
        \\      transform.rotation = {
        \\        transform.rotation[1] + spin.angular_velocity[1] * dt * (1 + 1.5),
        \\        transform.rotation[2] + spin.angular_velocity[2] * dt * (1 + 1.5),
        \\        transform.rotation[3] + spin.angular_velocity[3] * dt * (1 + 1.5),
        \\      }
        \\    end
        \\  end,
        \\})
    );
    defer program.deinit();

    try std.testing.expect(program.registry.findComponent("spin") != null);
    const system = program.registry.findSystem("rotate_cubes") orelse return error.TestExpectedEqual;
    try std.testing.expect(system.runner.luau != 0);
    try std.testing.expectEqual(@as(usize, 1), system.reads.len);
    try std.testing.expectEqualStrings("spin", system.reads[0]);
    try std.testing.expectEqual(@as(usize, 1), system.writes.len);
    try std.testing.expectEqualStrings("machina.transform", system.writes[0]);
    {
        const profiles = program.systemProfileSnapshots();
        try std.testing.expectEqual(@as(usize, 1), profiles.len);
        try std.testing.expectEqualStrings("rotate_cubes", profiles[0].id);
        try std.testing.expectEqual(runtime.SystemPhase.update, profiles[0].phase);
        try std.testing.expectEqual(@as(u32, 0), profiles[0].sample_count);
        try std.testing.expectEqual(@as(u32, system_profile_window_frames), profiles[0].window_size);
    }

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("spinner", "Spinner");
    try world.setTransform(entity, .{});
    try world.setSpin(entity, .{ .angular_velocity = .{ 1.0, 0.0, 0.0 } });

    try std.testing.expect(program.update(&world, 0.5));
    const transform = (try world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 1.25), transform.rotation[0]);
    {
        const profiles = program.systemProfileSnapshots();
        try std.testing.expectEqual(@as(usize, 1), profiles.len);
        try std.testing.expectEqual(@as(u32, 1), profiles[0].sample_count);
        try std.testing.expectEqual(profiles[0].last_ns, profiles[0].rolling_average_ns);
    }
}

test "native and luau systems share components and scheduling" {
    const velocity_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "linear", .value_type = .vec3 },
    };
    const native_systems = [_]NativeSystemRegistration{
        .{ .definition = .{
            .id = "native_move",
            .phase = .update,
            .reads = &.{ "velocity", "boost" },
            .writes = &.{runtime.transform_component_id},
            .after = &.{"accelerate_velocity"},
        }, .run = testNativeMoveSystem },
    };
    const native_extension = NativeExtension{
        .components = &.{.{ .id = "velocity", .fields = &velocity_fields }},
        .systems = &native_systems,
    };

    var program = try loadSourceProgramWithNative(
        std.testing.allocator,
        "test.luau",
        \\--!strict
        \\
        \\local Velocity = ecs.component("velocity")
        \\local Boost = ecs.component("boost", {
        \\  fields = ecs.fields({
        \\    amount = "f32",
        \\  }),
        \\})
        \\local Velocities = ecs.query(Velocity)
        \\
        \\ecs.system("accelerate_velocity", {
        \\  phase = "update",
        \\  query = Velocities,
        \\  writes = ecs.refs(Velocity),
        \\  before = { "native_move" },
        \\  run = function(world, dt)
        \\    for _entity, velocity in Velocities:iter(world) do
        \\      velocity.linear = {
        \\        velocity.linear[1] + 4.0 * dt,
        \\        velocity.linear[2],
        \\        velocity.linear[3],
        \\      }
        \\    end
        \\  end,
        \\})
    ,
        native_extension,
    );
    defer program.deinit();

    const native_system = program.registry.findSystem("native_move") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 0), native_system.runner.native);
    const luau_system = program.registry.findSystem("accelerate_velocity") orelse return error.TestExpectedEqual;
    try std.testing.expect(luau_system.runner.luau != 0);

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("hybrid", "Hybrid");
    try world.setTransform(entity, .{});
    try world.setComponent(entity, "velocity", &.{
        .{ .name = "linear", .value = .{ .vec3 = .{ 1.0, 0.0, 0.0 } } },
    });
    try world.setComponent(entity, "boost", &.{
        .{ .name = "amount", .value = .{ .float = 2.0 } },
    });

    try std.testing.expect(program.update(&world, 0.5));
    try std.testing.expectEqual(@as(f32, 3.0), (try world.getVec3(entity, "velocity", "linear"))[0]);
    try std.testing.expectEqual(@as(f32, 3.0), (try world.getVec3(entity, runtime.transform_component_id, "position"))[0]);

    const profiles = program.systemProfileSnapshots();
    try std.testing.expectEqual(@as(usize, 2), profiles.len);
    try std.testing.expectEqual(@as(u32, 1), profiles[0].sample_count);
    try std.testing.expectEqual(@as(u32, 1), profiles[1].sample_count);
}

test "native host facade supports typed fields and lifecycle commands" {
    const stats_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "spawned_count", .value_type = .int },
        .{ .name = "removed_count", .value_type = .int },
        .{ .name = "despawned_count", .value_type = .int },
        .{ .name = "ready", .value_type = .boolean },
        .{ .name = "label", .value_type = .string },
        .{ .name = "gain", .value_type = .float },
        .{ .name = "direction", .value_type = .vec3 },
    };
    const payload_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "count", .value_type = .int },
        .{ .name = "enabled", .value_type = .boolean },
        .{ .name = "speed", .value_type = .float },
        .{ .name = "direction", .value_type = .vec3 },
        .{ .name = "label", .value_type = .string },
    };
    const marker_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "value", .value_type = .int },
    };
    const native_systems = [_]NativeSystemRegistration{
        .{ .definition = .{
            .id = "native_lifecycle",
            .phase = .startup,
            .reads = &.{},
            .writes = &.{ "native_stats", "native_payload", "native_marker" },
        }, .run = testNativeLifecycleSystem },
    };
    const native_extension = NativeExtension{
        .components = &.{
            .{ .id = "native_stats", .fields = &stats_fields },
            .{ .id = "native_payload", .fields = &payload_fields },
            .{ .id = "native_marker", .fields = &marker_fields },
        },
        .systems = &native_systems,
    };

    var program = try loadSourceProgramWithNative(std.testing.allocator, "test.luau", "--!strict\n", native_extension);
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const stats = try world.createEntity("stats", "Stats");
    try world.setComponent(stats, "native_stats", &.{
        .{ .name = "spawned_count", .value = .{ .int = 0 } },
        .{ .name = "removed_count", .value = .{ .int = 0 } },
        .{ .name = "despawned_count", .value = .{ .int = 0 } },
        .{ .name = "ready", .value = .{ .boolean = true } },
        .{ .name = "label", .value = .{ .string = "ready" } },
        .{ .name = "gain", .value = .{ .float = 1.5 } },
        .{ .name = "direction", .value = .{ .vec3 = .{ 1.0, 2.0, 3.0 } } },
    });
    const marked = try world.createEntity("marked", "Marked");
    try world.setComponent(marked, "native_marker", &.{
        .{ .name = "value", .value = .{ .int = 1 } },
    });

    try std.testing.expect(program.startup(&world));
    try std.testing.expectEqual(runtime.ComponentValue{ .int = 2 }, try world.getComponentFieldValue(stats, "native_stats", "spawned_count"));
    try std.testing.expectEqual(runtime.ComponentValue{ .int = 1 }, try world.getComponentFieldValue(stats, "native_stats", "removed_count"));
    try std.testing.expectEqual(runtime.ComponentValue{ .int = 1 }, try world.getComponentFieldValue(stats, "native_stats", "despawned_count"));
    try std.testing.expectEqual(runtime.ComponentValue{ .boolean = false }, try world.getComponentFieldValue(stats, "native_stats", "ready"));
    try std.testing.expectEqual(runtime.ComponentValue{ .float = 2.5 }, try world.getComponentFieldValue(stats, "native_stats", "gain"));
    try std.testing.expectEqual(runtime.ComponentValue{ .vec3 = .{ 1.0, 3.5, 3.0 } }, try world.getComponentFieldValue(stats, "native_stats", "direction"));
    const stats_label = try world.getComponentFieldValue(stats, "native_stats", "label");
    try std.testing.expectEqualStrings("done", stats_label.string);

    const survivor = world.findEntityById("native-survivor") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(runtime.ComponentValue{ .int = 7 }, try world.getComponentFieldValue(survivor, "native_payload", "count"));
    try std.testing.expectEqual(runtime.ComponentValue{ .boolean = true }, try world.getComponentFieldValue(survivor, "native_payload", "enabled"));
    try std.testing.expectEqual(runtime.ComponentValue{ .float = 1.75 }, try world.getComponentFieldValue(survivor, "native_payload", "speed"));
    try std.testing.expectEqual(runtime.ComponentValue{ .vec3 = .{ 3.0, 2.0, 1.0 } }, try world.getComponentFieldValue(survivor, "native_payload", "direction"));
    const payload_label = try world.getComponentFieldValue(survivor, "native_payload", "label");
    try std.testing.expectEqualStrings("spawned", payload_label.string);

    try std.testing.expect(!try world.hasComponent(marked, "native_marker"));
    try std.testing.expect(world.findEntityById("native-doomed") == null);
}

test "native system failures produce runtime diagnostics" {
    const native_systems = [_]NativeSystemRegistration{
        .{ .definition = .{
            .id = "native_fail",
            .phase = .update,
        }, .run = testFailingNativeSystem },
    };
    var program = try loadSourceProgramWithNative(
        std.testing.allocator,
        "test.luau",
        "--!strict\n",
        .{ .systems = &native_systems },
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try std.testing.expect(!program.update(&world, 0.1));
    const diagnostic = program.last_diagnostic orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(DiagnosticStage.runtime, diagnostic.stage);
    try std.testing.expectEqualStrings("native_fail", diagnostic.system_id orelse return error.TestExpectedEqual);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "native system 'native_fail' failed") != null);
}

test "luau systems can spawn despawn add and remove components" {
    var program = try loadSourceProgram(
        std.testing.allocator,
        "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local Spawned = ecs.component("spawned", {
        \\  fields = ecs.fields({
        \\    value = "int",
        \\  }),
        \\})
        \\local Temporary = ecs.component("temporary", {
        \\  fields = ecs.fields({
        \\    value = "int",
        \\  }),
        \\})
        \\
        \\ecs.system("spawn_entities", {
        \\  phase = "startup",
        \\  writes = ecs.refs(Transform, Spawned, Temporary),
        \\  run = function(world, _dt)
        \\    local entity = world.spawn("spawned-one", "Spawned One")
        \\    entity:add(Transform, {
        \\      position = { 1.0, 2.0, 3.0 },
        \\      rotation = { 0.0, 0.0, 0.0 },
        \\      scale = { 1.0, 1.0, 1.0 },
        \\    })
        \\    entity:add(Spawned, { value = 7 })
        \\    entity:add(Temporary, { value = 99 })
        \\    entity:remove(Temporary)
        \\
        \\    local doomed = world.spawn("doomed", "Doomed")
        \\    doomed:add(Temporary, { value = 1 })
        \\    doomed:despawn()
        \\  end,
        \\})
        ,
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try std.testing.expect(program.startup(&world));
    const spawned = world.findEntityById("spawned-one") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), world.entityCount());
    try std.testing.expectEqual(runtime.EntityProvenance.spawned, (try world.entity(spawned)).provenance);
    try std.testing.expect(try world.hasComponent(spawned, runtime.transform_component_id));
    try std.testing.expect(try world.hasComponent(spawned, "spawned"));
    try std.testing.expect(!try world.hasComponent(spawned, "temporary"));
    try std.testing.expectEqual(@as(i32, 7), try world.getInt(spawned, "spawned", "value"));
    try std.testing.expect(world.findEntityById("doomed") == null);
}

test "luau entity proxies reject stale generated handles after despawn" {
    var program = try loadSourceProgram(
        std.testing.allocator,
        "test.luau",
        \\--!strict
        \\
        \\local Marker = ecs.component("marker", {
        \\  fields = ecs.fields({
        \\    value = "int",
        \\  }),
        \\})
        \\local stale = nil
        \\
        \\ecs.system("make_stale_proxy", {
        \\  phase = "startup",
        \\  writes = ecs.refs(Marker),
        \\  run = function(world, _dt)
        \\    local first = world.spawn("first", "First")
        \\    first:add(Marker, { value = 1 })
        \\    local second = world.spawn("second", "Second")
        \\    second:add(Marker, { value = 2 })
        \\    first:despawn()
        \\    stale = first
        \\  end,
        \\})
        \\
        \\ecs.system("reject_stale_proxy", {
        \\  phase = "update",
        \\  writes = ecs.refs(Marker),
        \\  run = function(_world, _dt)
        \\    stale:add(Marker, { value = 3 })
        \\  end,
        \\})
        ,
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try std.testing.expect(program.startup(&world));
    const second = world.findEntityById("second") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), world.entityCount());
    try std.testing.expectEqual(@as(i32, 2), try world.getInt(second, "marker", "value"));
    try std.testing.expect(!program.update(&world, 0.25));
    try std.testing.expectEqual(@as(usize, 1), world.entityCount());
    try std.testing.expectEqual(@as(i32, 2), try world.getInt(second, "marker", "value"));
}

test "luau structural commands roll back immediate spawns when a system fails" {
    var program = try loadSourceProgram(
        std.testing.allocator,
        "test.luau",
        \\--!strict
        \\
        \\local Marker = ecs.component("marker", {
        \\  fields = ecs.fields({
        \\    value = "int",
        \\  }),
        \\})
        \\
        \\ecs.system("spawn_then_fail", {
        \\  phase = "startup",
        \\  writes = ecs.refs(Marker),
        \\  run = function(world, _dt)
        \\    local entity = world.spawn("rolled-back", "Rolled Back")
        \\    entity:add(Marker, { value = 7 })
        \\    error("boom")
        \\  end,
        \\})
        ,
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try std.testing.expect(!program.startup(&world));
    try std.testing.expectEqual(@as(usize, 0), world.entityCount());
    try std.testing.expect(world.findEntityById("rolled-back") == null);
}

test "luau structural command flush failure rolls back system mutations" {
    var program = try loadSourceProgram(
        std.testing.allocator,
        "test.luau",
        \\--!strict
        \\
        \\local Marker = ecs.component("marker", {
        \\  fields = ecs.fields({
        \\    value = "int",
        \\  }),
        \\})
        \\
        \\ecs.system("conflicting_flush", {
        \\  phase = "startup",
        \\  writes = ecs.refs(Marker),
        \\  run = function(world, _dt)
        \\    local survivor = world.spawn("survivor", "Survivor")
        \\    survivor:add(Marker, { value = 1 })
        \\    local doomed = world.spawn("doomed", "Doomed")
        \\    doomed:add(Marker, { value = 2 })
        \\    doomed:despawn()
        \\    doomed:add(Marker, { value = 3 })
        \\  end,
        \\})
        ,
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try std.testing.expect(!program.startup(&world));
    try std.testing.expectEqual(@as(usize, 0), world.entityCount());
    try std.testing.expect(world.findEntityById("survivor") == null);
    try std.testing.expect(world.findEntityById("doomed") == null);

    const diagnostic = program.last_diagnostic orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(DiagnosticStage.runtime, diagnostic.stage);
    try std.testing.expectEqualStrings("conflicting_flush", diagnostic.system_id orelse return error.TestExpectedEqual);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "after it was queued for despawn") != null);
}

test "luau queued component adds become visible after system boundary" {
    var program = try loadSourceProgram(
        std.testing.allocator,
        "test.luau",
        \\--!strict
        \\
        \\local Marker = ecs.component("marker", {
        \\  fields = ecs.fields({
        \\    value = "int",
        \\  }),
        \\})
        \\local Markers = ecs.query(Marker)
        \\
        \\ecs.system("create_marker", {
        \\  phase = "startup",
        \\  query = Markers,
        \\  writes = ecs.refs(Marker),
        \\  before = { "observe_marker" },
        \\  run = function(world, _dt)
        \\    local entity = world.spawn("queued", "Queued")
        \\    entity:add(Marker, { value = 11 })
        \\    local count = 0
        \\    for _entity, _marker in Markers:iter(world) do
        \\      count += 1
        \\    end
        \\    if count ~= 0 then
        \\      error("queued add was visible inside the mutating system")
        \\    end
        \\  end,
        \\})
        \\
        \\ecs.system("observe_marker", {
        \\  phase = "startup",
        \\  query = Markers,
        \\  after = { "create_marker" },
        \\  run = function(world, _dt)
        \\    local sum = 0
        \\    for _entity, marker in Markers:iter(world) do
        \\      sum += marker.value
        \\    end
        \\    if sum ~= 11 then
        \\      error("queued add was not visible after the system boundary")
        \\    end
        \\  end,
        \\})
        ,
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try std.testing.expect(program.startup(&world));
    const entity = world.findEntityById("queued") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(i32, 11), try world.getInt(entity, "marker", "value"));
}

test "luau component handles can reference engine components without registration" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local RenderCube = ecs.component<<MachinaRenderCube>>("machina.render.cube")
        \\
        \\ecs.system("observe_cubes", {
        \\  reads = ecs.refs(Transform, RenderCube),
        \\})
    );
    defer program.deinit();

    try std.testing.expect(program.registry.findComponent("spin") == null);
    try std.testing.expect(program.registry.findSystem("observe_cubes") != null);
}

test "luau component handles expose a guarded type brand function" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\if type(Transform.__machina_component_type) ~= "function" then
        \\  error("component type brand is missing")
        \\end
        \\local ok = pcall(function()
        \\  Transform.__machina_component_type()
        \\end)
        \\if ok then
        \\  error("component type brand should not be callable gameplay API")
        \\end
    );
    defer program.deinit();
}

test "luau refs helper erases component handles for system declarations" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local RenderCube = ecs.component<<MachinaRenderCube>>("machina.render.cube")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\
        \\ecs.system("observe_everything", {
        \\  reads = ecs.refs(Transform, RenderCube, Spin),
        \\})
    );
    defer program.deinit();

    const system = program.registry.findSystem("observe_everything") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 3), system.reads.len);
    try std.testing.expectEqualStrings("machina.transform", system.reads[0]);
    try std.testing.expectEqualStrings("machina.render.cube", system.reads[1]);
    try std.testing.expectEqualStrings("spin", system.reads[2]);
}

test "luau fields helper preserves component declaration fields" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\type Spin = {
        \\  angular_velocity: MachinaVec3,
        \\}
        \\
        \\local _Spin = ecs.component<<Spin>>("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
    );
    defer program.deinit();

    const spin = program.registry.findComponent("spin") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), spin.fields.len);
    try std.testing.expectEqualStrings("angular_velocity", spin.fields[0].name);
    try std.testing.expectEqual(runtime.FieldType.vec3, spin.fields[0].value_type);
}

test "luau fields helper infers and preserves component payload types" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\local Spinners = ecs.query(Spin)
        \\
        \\ecs.system("observe_spin", {
        \\  query = Spinners,
        \\})
    );
    defer program.deinit();

    const spin = program.registry.findComponent("spin") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), spin.fields.len);
    try std.testing.expectEqualStrings("angular_velocity", spin.fields[0].name);
    try std.testing.expectEqual(runtime.FieldType.vec3, spin.fields[0].value_type);
    const system = program.registry.findSystem("observe_spin") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), system.reads.len);
    try std.testing.expectEqualStrings("spin", system.reads[0]);
}

test "luau component proxies read and write scalar fields" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Stats = ecs.component("stats", {
        \\  fields = ecs.fields({
        \\    enabled = "boolean",
        \\    count = "i32",
        \\    speed = "f32",
        \\    label = "string",
        \\  }),
        \\})
        \\local StatsQuery = ecs.query(Stats)
        \\
        \\ecs.system("update_stats", {
        \\  query = StatsQuery,
        \\  writes = ecs.refs(Stats),
        \\  run = function(world, _dt)
        \\    for _entity, stats in StatsQuery:iter(world) do
        \\      if stats.enabled and stats.label == "ready" then
        \\        stats.count = stats.count + 1
        \\        stats.speed = stats.speed + 0.5
        \\        stats.label = "done"
        \\      end
        \\    end
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("stats-entity", "Stats Entity");
    const fields = [_]runtime.ComponentFieldValue{
        .{ .name = "enabled", .value = .{ .boolean = true } },
        .{ .name = "count", .value = .{ .int = 41 } },
        .{ .name = "speed", .value = .{ .float = 1.5 } },
        .{ .name = "label", .value = .{ .string = "ready" } },
    };
    try world.setComponent(entity, "stats", &fields);

    try std.testing.expect(program.update(&world, 0.25));
    try std.testing.expectEqual(runtime.ComponentValue{ .boolean = true }, try world.getComponentFieldValue(entity, "stats", "enabled"));
    try std.testing.expectEqual(runtime.ComponentValue{ .int = 42 }, try world.getComponentFieldValue(entity, "stats", "count"));
    try std.testing.expectEqual(runtime.ComponentValue{ .float = 2.0 }, try world.getComponentFieldValue(entity, "stats", "speed"));
    const label = try world.getComponentFieldValue(entity, "stats", "label");
    try std.testing.expectEqualStrings("done", label.string);
}

test "luau component proxy rejects scalar values outside host field range" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Stats = ecs.component("stats", {
        \\  fields = ecs.fields({
        \\    speed = "f32",
        \\  }),
        \\})
        \\local StatsQuery = ecs.query(Stats)
        \\
        \\ecs.system("break_stats", {
        \\  query = StatsQuery,
        \\  writes = ecs.refs(Stats),
        \\  run = function(world, _dt)
        \\    for _entity, stats in StatsQuery:iter(world) do
        \\      stats.speed = 1e100
        \\    end
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("stats-entity", "Stats Entity");
    const fields = [_]runtime.ComponentFieldValue{
        .{ .name = "speed", .value = .{ .float = 1.5 } },
    };
    try world.setComponent(entity, "stats", &fields);

    try std.testing.expect(!program.update(&world, 0.25));
    try std.testing.expectEqual(runtime.ComponentValue{ .float = 1.5 }, try world.getComponentFieldValue(entity, "stats", "speed"));
}

test "luau query views bulk read and write f32 and vec3 fields" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Motion = ecs.component("motion", {
        \\  fields = ecs.fields({
        \\    position = "vec3",
        \\    velocity = "vec3",
        \\    speed = "f32",
        \\  }),
        \\})
        \\local Movers = ecs.query(Motion)
        \\
        \\ecs.system("advance_movers", {
        \\  query = Movers,
        \\  writes = ecs.refs(Motion),
        \\  run = function(world, dt)
        \\    local view = Movers:view(world)
        \\    local count = view:count()
        \\    local positions = view:read_vec3(Motion, "position")
        \\    local velocities = view:read_vec3(Motion, "velocity")
        \\    local speeds = view:read_f32(Motion, "speed")
        \\
        \\    for index = 0, count - 1 do
        \\      local f32_offset = index * 4
        \\      local vec3_offset = index * 12
        \\      local px = buffer.readf32(positions, vec3_offset)
        \\      local py = buffer.readf32(positions, vec3_offset + 4)
        \\      local pz = buffer.readf32(positions, vec3_offset + 8)
        \\      local vx = buffer.readf32(velocities, vec3_offset)
        \\      local vy = buffer.readf32(velocities, vec3_offset + 4)
        \\      local vz = buffer.readf32(velocities, vec3_offset + 8)
        \\      buffer.writef32(positions, vec3_offset, px + vx * dt)
        \\      buffer.writef32(positions, vec3_offset + 4, py + vy * dt)
        \\      buffer.writef32(positions, vec3_offset + 8, pz + vz * dt)
        \\      buffer.writef32(speeds, f32_offset, buffer.readf32(speeds, f32_offset) + dt)
        \\    end
        \\
        \\    view:write_vec3(Motion, "position", positions)
        \\    view:write_f32(Motion, "speed", speeds)
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const first = try world.createEntity("first", "First");
    const second = try world.createEntity("second", "Second");
    try world.setComponent(first, "motion", &[_]runtime.ComponentFieldValue{
        .{ .name = "position", .value = .{ .vec3 = .{ 1.0, 2.0, 3.0 } } },
        .{ .name = "velocity", .value = .{ .vec3 = .{ 2.0, 0.0, -2.0 } } },
        .{ .name = "speed", .value = .{ .float = 10.0 } },
    });
    try world.setComponent(second, "motion", &[_]runtime.ComponentFieldValue{
        .{ .name = "position", .value = .{ .vec3 = .{ -1.0, 4.0, 0.5 } } },
        .{ .name = "velocity", .value = .{ .vec3 = .{ 0.0, -4.0, 1.0 } } },
        .{ .name = "speed", .value = .{ .float = 20.0 } },
    });

    try std.testing.expect(program.update(&world, 0.5));
    try std.testing.expectEqual(runtime.ComponentValue{ .vec3 = .{ 2.0, 2.0, 2.0 } }, try world.getComponentFieldValue(first, "motion", "position"));
    try std.testing.expectEqual(runtime.ComponentValue{ .float = 10.5 }, try world.getComponentFieldValue(first, "motion", "speed"));
    try std.testing.expectEqual(runtime.ComponentValue{ .vec3 = .{ -1.0, 2.0, 1.0 } }, try world.getComponentFieldValue(second, "motion", "position"));
    try std.testing.expectEqual(runtime.ComponentValue{ .float = 20.5 }, try world.getComponentFieldValue(second, "motion", "speed"));
}

test "luau query views require declared writes" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Stats = ecs.component("stats", {
        \\  fields = ecs.fields({
        \\    speed = "f32",
        \\  }),
        \\})
        \\local StatsQuery = ecs.query(Stats)
        \\
        \\ecs.system("write_without_access", {
        \\  query = StatsQuery,
        \\  run = function(world, _dt)
        \\    local view = StatsQuery:view(world)
        \\    local speeds = view:read_f32(Stats, "speed")
        \\    view:write_f32(Stats, "speed", speeds)
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("stats-entity", "Stats Entity");
    try world.setComponent(entity, "stats", &[_]runtime.ComponentFieldValue{
        .{ .name = "speed", .value = .{ .float = 1.5 } },
    });

    try std.testing.expect(!program.update(&world, 0.25));
    try std.testing.expectEqual(runtime.ComponentValue{ .float = 1.5 }, try world.getComponentFieldValue(entity, "stats", "speed"));
}

test "luau query views reject non-finite bulk writes" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Stats = ecs.component("stats", {
        \\  fields = ecs.fields({
        \\    speed = "f32",
        \\  }),
        \\})
        \\local StatsQuery = ecs.query(Stats)
        \\
        \\ecs.system("write_bad_value", {
        \\  query = StatsQuery,
        \\  writes = ecs.refs(Stats),
        \\  run = function(world, _dt)
        \\    local view = StatsQuery:view(world)
        \\    local speeds = view:read_f32(Stats, "speed")
        \\    buffer.writef32(speeds, 0, 1e100)
        \\    view:write_f32(Stats, "speed", speeds)
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("stats-entity", "Stats Entity");
    try world.setComponent(entity, "stats", &[_]runtime.ComponentFieldValue{
        .{ .name = "speed", .value = .{ .float = 1.5 } },
    });

    try std.testing.expect(!program.update(&world, 0.25));
    try std.testing.expectEqual(runtime.ComponentValue{ .float = 1.5 }, try world.getComponentFieldValue(entity, "stats", "speed"));
}

test "luau query views cannot be reused across system invocations" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Stats = ecs.component("stats", {
        \\  fields = ecs.fields({
        \\    speed = "f32",
        \\  }),
        \\})
        \\local StatsQuery = ecs.query(Stats)
        \\local saved_view = nil
        \\
        \\ecs.system("stash_view", {
        \\  query = StatsQuery,
        \\  run = function(world, _dt)
        \\    if saved_view ~= nil then
        \\      saved_view:count()
        \\    end
        \\    saved_view = StatsQuery:view(world)
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("stats-entity", "Stats Entity");
    try world.setComponent(entity, "stats", &[_]runtime.ComponentFieldValue{
        .{ .name = "speed", .value = .{ .float = 1.5 } },
    });

    try std.testing.expect(program.update(&world, 0.25));
    try std.testing.expect(!program.update(&world, 0.25));
}

test "luau query object plans invalidate when component tables appear" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Marker = ecs.component("marker", {
        \\  fields = ecs.fields({
        \\    value = "int",
        \\  }),
        \\})
        \\local Markers = ecs.query(Marker)
        \\
        \\ecs.system("observe_empty", {
        \\  query = Markers,
        \\  before = { "create_marker" },
        \\  run = function(world, _dt)
        \\    local count = 0
        \\    for _entity, _marker in Markers:iter(world) do
        \\      count += 1
        \\    end
        \\    if count ~= 0 then
        \\      error("query unexpectedly found markers")
        \\    end
        \\  end,
        \\})
        \\
        \\ecs.system("create_marker", {
        \\  after = { "observe_empty" },
        \\  before = { "observe_created" },
        \\  writes = ecs.refs(Marker),
        \\  run = function(world, _dt)
        \\    local entity = world.spawn("marker-one", "Marker One")
        \\    entity:add(Marker, { value = 3 })
        \\  end,
        \\})
        \\
        \\ecs.system("observe_created", {
        \\  query = Markers,
        \\  after = { "create_marker" },
        \\  run = function(world, _dt)
        \\    local sum = 0
        \\    for _entity, marker in Markers:iter(world) do
        \\      sum += marker.value
        \\    end
        \\    if sum ~= 3 then
        \\      error("query plan did not invalidate")
        \\    end
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try std.testing.expect(program.update(&world, 0.25));
}

test "luau schema helper rejects non-marker field values" {
    try std.testing.expectError(ScriptError.InvalidScript, loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local _Spin = ecs.component("spin", {
        \\  fields = ecs.schema({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
    ));
}

test "luau query objects infer system reads from unwritten query components" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local RenderCube = ecs.component<<MachinaRenderCube>>("machina.render.cube")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\local RotatingCubes = ecs.query(Transform, Spin, RenderCube)
        \\
        \\ecs.system("rotate_cubes", {
        \\  query = RotatingCubes,
        \\  writes = ecs.refs(Transform),
        \\})
    );
    defer program.deinit();

    const system = program.registry.findSystem("rotate_cubes") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), system.reads.len);
    try std.testing.expectEqualStrings("spin", system.reads[0]);
    try std.testing.expectEqualStrings("machina.render.cube", system.reads[1]);
    try std.testing.expectEqual(@as(usize, 1), system.writes.len);
    try std.testing.expectEqualStrings("machina.transform", system.writes[0]);
}

test "luau query objects reject duplicate component refs" {
    try std.testing.expectError(ScriptError.InvalidScript, loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local _BadQuery = ecs.query(Transform, Transform)
    ));
}

test "luau world mutation requires declared system access" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\type Marker = {}
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\
        \\local Marker = ecs.component<<Marker>>("marker", {})
        \\local RotatingCubes = ecs.query(Transform, Spin)
        \\
        \\ecs.system("bad_rotate", {
        \\  query = RotatingCubes,
        \\  writes = ecs.refs(Marker),
        \\  run = function(world, dt)
        \\    for _entity, transform, spin in RotatingCubes:iter(world) do
        \\      transform.rotation = { dt, 0, 0 }
        \\    end
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("spinner", "Spinner");
    try world.setTransform(entity, .{});
    try world.setSpin(entity, .{ .angular_velocity = .{ 1.0, 0.0, 0.0 } });

    try std.testing.expect(!program.update(&world, 1.0));
    const diagnostic = program.last_diagnostic orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(DiagnosticStage.runtime, diagnostic.stage);
    try std.testing.expectEqualStrings("bad_rotate", diagnostic.system_id orelse return error.TestExpectedEqual);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "bad_rotate") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "machina.transform.rotation") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "writes") != null);
    const transform = (try world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 0.0), transform.rotation[0]);
}

test "luau world query requires declared component access" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\type Marker = {}
        \\
        \\local Transform = ecs.component<<MachinaTransform>>("machina.transform")
        \\local Spin = ecs.component("spin", {
        \\  fields = ecs.fields({
        \\    angular_velocity = "vec3",
        \\  }),
        \\})
        \\
        \\local Marker = ecs.component<<Marker>>("marker", {})
        \\local Markers = ecs.query(Marker)
        \\
        \\ecs.system("bad_query", {
        \\  reads = ecs.refs(Spin),
        \\  writes = ecs.refs(Transform),
        \\  run = function(world, dt)
        \\    for entity, marker in Markers:iter(world) do
        \\      entity.set_vec3("machina.transform", "rotation", { dt, 0, 0 })
        \\    end
        \\  end,
        \\})
    );
    defer program.deinit();

    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();
    const entity = try world.createEntity("spinner", "Spinner");
    try world.setTransform(entity, .{});
    try world.setSpin(entity, .{ .angular_velocity = .{ 1.0, 0.0, 0.0 } });

    try std.testing.expect(!program.update(&world, 1.0));
    const diagnostic = program.last_diagnostic orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(DiagnosticStage.runtime, diagnostic.stage);
    try std.testing.expectEqualStrings("bad_query", diagnostic.system_id orelse return error.TestExpectedEqual);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "bad_query") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "marker") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "reads or writes") != null);
}

test "script runtime schedule includes startup and update batches" {
    var registry = runtime.ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try runtime.registerEngineComponents(&registry);

    try registry.registerProjectComponent(.{ .id = "stamina" });
    try registry.registerProjectSystem(.{
        .id = "spawn_initial",
        .phase = .startup,
        .writes = &.{"machina.transform"},
    });
    try registry.registerProjectSystem(.{
        .id = "read_transform",
        .reads = &.{"machina.transform"},
    });
    try registry.registerProjectSystem(.{
        .id = "observe_stamina",
        .reads = &.{"stamina"},
    });
    try registry.registerProjectSystem(.{
        .id = "regen_stamina",
        .reads = &.{"machina.transform"},
        .writes = &.{"stamina"},
    });

    var schedule = try buildRuntimeSchedule(std.testing.allocator, registry);
    defer schedule.deinit();

    try std.testing.expectEqual(@as(usize, 3), schedule.batchCount());
    try std.testing.expectEqual(@as(usize, 4), schedule.systemCount());
    try std.testing.expectEqual(runtime.SystemPhase.startup, schedule.batches[0].phase);
    try std.testing.expectEqual(@as(usize, 1), schedule.batches[0].systems.len);
    try std.testing.expectEqualStrings("spawn_initial", schedule.batches[0].systems[0].id);
    try std.testing.expectEqual(runtime.SystemPhase.update, schedule.batches[1].phase);
    try std.testing.expectEqual(@as(usize, 2), schedule.batches[1].systems.len);
    try std.testing.expectEqual(runtime.SystemPhase.update, schedule.batches[2].phase);
    try std.testing.expectEqual(@as(usize, 1), schedule.batches[2].systems.len);
}
