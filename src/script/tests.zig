const std = @import("std");
const script = @import("main.zig");
const native_api = @import("../native_api.zig");
const runtime = @import("../runtime.zig");

const DiagnosticStage = script.DiagnosticStage;
const NativeExtension = script.NativeExtension;
const NativeSystemContext = script.NativeSystemContext;
const NativeSystemRegistration = script.NativeSystemRegistration;
const ScriptError = script.ScriptError;
const buildRuntimeSchedule = script.buildRuntimeSchedule;
const loadSourceProgram = script.loadSourceProgram;
const loadSourceProgramWithNative = script.loadSourceProgramWithNative;
const system_profile_window_frames = script.system_profile_window_frames;

fn testNativeMoveSystem(context: *NativeSystemContext) callconv(.c) c_int {
    const component_ids = [_][*:0]const u8{ "scrapbot.transform", "velocity", "boost" };
    var cursor: usize = 0;
    while (native_api.queryNext(context, component_ids[0..], &cursor) catch return 0) |entity| {
        const position = native_api.getVec3(context, entity, "scrapbot.transform", "position") catch return 0;
        const velocity = native_api.getVec3(context, entity, "velocity", "linear") catch return 0;
        const boost = native_api.getF32(context, entity, "boost", "amount") catch return 0;
        native_api.setVec3(context, entity, "scrapbot.transform", "position", position.addScaled(velocity, boost * context.delta_seconds)) catch return 0;
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
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
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
    try std.testing.expectEqualStrings("scrapbot.transform", system.writes[0]);
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
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
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
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
        \\local RenderCube = ecs.component<<ScrapbotRenderCube>>("scrapbot.render.cube")
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
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
        \\if type(Transform.__scrapbot_component_type) ~= "function" then
        \\  error("component type brand is missing")
        \\end
        \\local ok = pcall(function()
        \\  Transform.__scrapbot_component_type()
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
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
        \\local RenderCube = ecs.component<<ScrapbotRenderCube>>("scrapbot.render.cube")
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
    try std.testing.expectEqualStrings("scrapbot.transform", system.reads[0]);
    try std.testing.expectEqualStrings("scrapbot.render.cube", system.reads[1]);
    try std.testing.expectEqualStrings("spin", system.reads[2]);
}

test "luau fields helper preserves component declaration fields" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\type Spin = {
        \\  angular_velocity: ScrapbotVec3,
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
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
        \\local RenderCube = ecs.component<<ScrapbotRenderCube>>("scrapbot.render.cube")
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
    try std.testing.expectEqualStrings("scrapbot.render.cube", system.reads[1]);
    try std.testing.expectEqual(@as(usize, 1), system.writes.len);
    try std.testing.expectEqualStrings("scrapbot.transform", system.writes[0]);
}

test "luau query objects reject duplicate component refs" {
    try std.testing.expectError(ScriptError.InvalidScript, loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
        \\local _BadQuery = ecs.query(Transform, Transform)
    ));
}

test "luau world mutation requires declared system access" {
    var program = try loadSourceProgram(std.testing.allocator, "test.luau",
        \\--!strict
        \\
        \\type Marker = {}
        \\
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
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
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "scrapbot.transform.rotation") != null);
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
        \\local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
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
        \\      entity.set_vec3("scrapbot.transform", "rotation", { dt, 0, 0 })
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
        .writes = &.{"scrapbot.transform"},
    });
    try registry.registerProjectSystem(.{
        .id = "read_transform",
        .reads = &.{"scrapbot.transform"},
    });
    try registry.registerProjectSystem(.{
        .id = "observe_stamina",
        .reads = &.{"stamina"},
    });
    try registry.registerProjectSystem(.{
        .id = "regen_stamina",
        .reads = &.{"scrapbot.transform"},
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
