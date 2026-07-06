const std = @import("std");
const Io = std.Io;
const diagnostics = @import("diagnostics.zig");
const native_library_types = @import("native_library.zig");
const native_api = @import("../native_api.zig");
const script_callbacks = @import("callbacks.zig");
const runtime = @import("../runtime.zig");

pub const c = @cImport({
    @cInclude("luau_bridge.h");
});

pub const system_profile_window_frames: usize = 120;

pub const ScriptError = runtime.RegistryError || runtime.ScheduleError || std.mem.Allocator.Error || error{
    InvalidScript,
    UnknownFieldType,
    UnknownSystemPhase,
};

pub const DiagnosticStage = diagnostics.Stage;
pub const Diagnostic = diagnostics.Diagnostic;
pub const DiagnosticPosition = diagnostics.Position;

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

pub const PlatformDynLib = native_library_types.PlatformDynLib;
pub const NativeLibrary = native_library_types.NativeLibrary;

pub const NativeExtension = struct {
    components: []const runtime.ComponentDefinition = &.{},
    systems: []const NativeSystemRegistration = &.{},
    libraries: []const NativeLibrary = &.{},
};

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

pub const QueuedComponentFieldValue = struct {
    name: []u8,
    value: runtime.ComponentValue,

    pub fn deinit(self: *QueuedComponentFieldValue, allocator: std.mem.Allocator) void {
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

pub const ScriptCommand = union(enum) {
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

pub const QueuedAddComponent = struct {
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

pub const QueuedRemoveComponent = struct {
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
    vm: *c.scrapbot_luau,
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
        c.scrapbot_luau_destroy(self.vm);
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
        c.scrapbot_luau_set_callback_context(self.vm, self);

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
                        var system_ok = c.scrapbot_luau_call_system(self.vm, runner_ref, world, delta_seconds) != 0;
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
        var call_context = script_callbacks.NativeCallContext{
            .program = self,
            .world = world,
        };
        var context = NativeSystemContext{
            .world = &call_context,
            .api = &script_callbacks.native_system_api,
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
            const owned_value = script_callbacks.cloneComponentValue(self.allocator, try world.getComponentFieldValue(entity, component_id, field_name)) catch |err| {
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

    pub fn activeSystemAllowsRead(self: Program, component_id: []const u8) bool {
        const active_system = self.active_system orelse return false;
        if (active_system.registry_index >= self.registry.systems.items.len) {
            return false;
        }

        const definition = self.registry.systems.items[active_system.registry_index];
        return containsString(definition.reads, component_id) or containsString(definition.writes, component_id);
    }

    pub fn activeSystemAllowsWrite(self: Program, component_id: []const u8) bool {
        const active_system = self.active_system orelse return false;
        if (active_system.registry_index >= self.registry.systems.items.len) {
            return false;
        }

        const definition = self.registry.systems.items[active_system.registry_index];
        return containsString(definition.writes, component_id);
    }

    pub fn activeSystemId(self: Program) []const u8 {
        const active_system = self.active_system orelse return "unknown";
        return active_system.id;
    }

    fn clearHostError(self: *Program) void {
        if (self.host_error) |message| {
            self.allocator.free(message);
            self.host_error = null;
        }
    }

    pub fn setHostError(self: *Program, comptime format: []const u8, args: anytype) void {
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
    const callbacks = c.scrapbot_luau_callbacks{
        .query_next = script_callbacks.queryNextCallback,
        .prepare_query = script_callbacks.prepareQueryCallback,
        .query_next_prepared = script_callbacks.queryNextPreparedCallback,
        .query_plan_generation = script_callbacks.queryPlanGenerationCallback,
        .read_f32_view = script_callbacks.readF32ViewCallback,
        .write_f32_view = script_callbacks.writeF32ViewCallback,
        .read_vec3_view = script_callbacks.readVec3ViewCallback,
        .write_vec3_view = script_callbacks.writeVec3ViewCallback,
        .get_vec3 = script_callbacks.getVec3Callback,
        .set_vec3 = script_callbacks.setVec3Callback,
        .get_field = script_callbacks.getFieldCallback,
        .get_field_resolved = script_callbacks.getFieldResolvedCallback,
        .set_field = script_callbacks.setFieldCallback,
        .set_field_resolved = script_callbacks.setFieldResolvedCallback,
        .spawn_entity = script_callbacks.spawnEntityCallback,
        .despawn_entity = script_callbacks.despawnEntityCallback,
        .add_component = script_callbacks.addComponentCallback,
        .remove_component = script_callbacks.removeComponentCallback,
        .host_error = script_callbacks.hostErrorCallback,
    };
    const vm = c.scrapbot_luau_create(callbacks) orelse return ScriptError.InvalidScript;

    var registry = runtime.ComponentRegistry.init(allocator);
    errdefer {
        registry.deinit();
        c.scrapbot_luau_destroy(vm);
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
    const component_start = c.scrapbot_luau_component_count(program.vm);
    const system_start = c.scrapbot_luau_system_count(program.vm);
    const chunk_name_z = try program.allocator.dupeZ(u8, chunk_name);
    defer program.allocator.free(chunk_name_z);

    if (c.scrapbot_luau_load(program.vm, chunk_name_z.ptr, source.ptr, source.len) == 0) {
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
    const component_count = c.scrapbot_luau_component_count(program.vm);
    for (0..component_count) |component_index| {
        var fields: std.ArrayList(runtime.ComponentFieldDefinition) = .empty;
        defer fields.deinit(program.allocator);

        const field_count = c.scrapbot_luau_component_field_count(program.vm, component_index);
        for (0..field_count) |field_index| {
            try fields.append(program.allocator, .{
                .name = try spanC(c.scrapbot_luau_component_field_name(program.vm, component_index, field_index)),
                .value_type = try parseFieldType(try spanC(c.scrapbot_luau_component_field_type(program.vm, component_index, field_index))),
            });
        }

        try program.registry.registerProjectComponent(.{
            .id = try spanC(c.scrapbot_luau_component_id(program.vm, component_index)),
            .version = c.scrapbot_luau_component_version(program.vm, component_index),
            .fields = fields.items,
        });
    }
}

fn registerDeclaredSystems(program: *Program) ScriptError!void {
    const system_count = c.scrapbot_luau_system_count(program.vm);
    for (0..system_count) |system_index| {
        var reads = try readSystemReads(program.allocator, program.vm, system_index);
        defer reads.deinit(program.allocator);
        var writes = try readSystemWrites(program.allocator, program.vm, system_index);
        defer writes.deinit(program.allocator);
        var before = try readSystemBefore(program.allocator, program.vm, system_index);
        defer before.deinit(program.allocator);
        var after = try readSystemAfter(program.allocator, program.vm, system_index);
        defer after.deinit(program.allocator);

        const runner_ref = c.scrapbot_luau_system_runner_ref(program.vm, system_index);
        try program.registry.registerProjectSystem(.{
            .id = try spanC(c.scrapbot_luau_system_id(program.vm, system_index)),
            .phase = try parseSystemPhase(try spanC(c.scrapbot_luau_system_phase(program.vm, system_index))),
            .reads = reads.items,
            .writes = writes.items,
            .before = before.items,
            .after = after.items,
            .runner = if (runner_ref == 0) .none else .{ .luau = runner_ref },
        });
    }
}

fn recordOrigins(program: *Program, path: []const u8, component_start: usize, system_start: usize) !void {
    const component_count = c.scrapbot_luau_component_count(program.vm);
    for (component_start..component_count) |component_index| {
        {
            const id = try spanC(c.scrapbot_luau_component_id(program.vm, component_index));
            const owned_id = try program.allocator.dupe(u8, id);
            errdefer program.allocator.free(owned_id);
            const owned_path = try program.allocator.dupe(u8, path);
            errdefer program.allocator.free(owned_path);
            const line = c.scrapbot_luau_component_line(program.vm, component_index);
            try program.component_origins.append(program.allocator, .{
                .index = component_index,
                .id = owned_id,
                .path = owned_path,
                .start = diagnosticPositionFromLine(line),
            });
        }
    }

    const system_count = c.scrapbot_luau_system_count(program.vm);
    for (system_start..system_count) |system_index| {
        {
            const id = try spanC(c.scrapbot_luau_system_id(program.vm, system_index));
            const owned_id = try program.allocator.dupe(u8, id);
            errdefer program.allocator.free(owned_id);
            const owned_path = try program.allocator.dupe(u8, path);
            errdefer program.allocator.free(owned_path);
            const line = c.scrapbot_luau_system_line(program.vm, system_index);
            try program.system_origins.append(program.allocator, .{
                .index = system_index,
                .id = owned_id,
                .path = owned_path,
                .start = diagnosticPositionFromLine(line),
                .runner_ref = c.scrapbot_luau_system_runner_ref(program.vm, system_index),
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

fn lastLuauError(vm: *c.scrapbot_luau) []const u8 {
    return std.mem.span(c.scrapbot_luau_last_error(vm));
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

fn readSystemReads(allocator: std.mem.Allocator, vm: *c.scrapbot_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.scrapbot_luau_system_reads_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.scrapbot_luau_system_reads_item(vm, system_index, item_index)));
    }
    return values;
}

fn readSystemWrites(allocator: std.mem.Allocator, vm: *c.scrapbot_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.scrapbot_luau_system_writes_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.scrapbot_luau_system_writes_item(vm, system_index, item_index)));
    }
    return values;
}

fn readSystemBefore(allocator: std.mem.Allocator, vm: *c.scrapbot_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.scrapbot_luau_system_before_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.scrapbot_luau_system_before_item(vm, system_index, item_index)));
    }
    return values;
}

fn readSystemAfter(allocator: std.mem.Allocator, vm: *c.scrapbot_luau, system_index: usize) !std.ArrayList([]const u8) {
    var values: std.ArrayList([]const u8) = .empty;
    errdefer values.deinit(allocator);
    for (0..c.scrapbot_luau_system_after_count(vm, system_index)) |item_index| {
        try values.append(allocator, try spanC(c.scrapbot_luau_system_after_item(vm, system_index, item_index)));
    }
    return values;
}

fn spanC(value: ?[*:0]const u8) ScriptError![]const u8 {
    return std.mem.span(value orelse return ScriptError.InvalidScript);
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

test {
    _ = @import("tests.zig");
}
