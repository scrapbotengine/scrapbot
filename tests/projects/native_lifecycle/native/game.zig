const std = @import("std");
const scrapbot = @import("scrapbot_native");

const stats_fields = [_]scrapbot.ComponentField{
    .{ .name = "spawned_count", .field_type = .int },
    .{ .name = "removed_count", .field_type = .int },
    .{ .name = "despawned_count", .field_type = .int },
    .{ .name = "ready", .field_type = .boolean },
    .{ .name = "label", .field_type = .string },
    .{ .name = "gain", .field_type = .float },
    .{ .name = "direction", .field_type = .vec3 },
};

const payload_fields = [_]scrapbot.ComponentField{
    .{ .name = "count", .field_type = .int },
    .{ .name = "enabled", .field_type = .boolean },
    .{ .name = "speed", .field_type = .float },
    .{ .name = "direction", .field_type = .vec3 },
    .{ .name = "label", .field_type = .string },
};

const marker_fields = [_]scrapbot.ComponentField{
    .{ .name = "value", .field_type = .int },
};

const lifecycle_writes = [_][*:0]const u8{ "native_stats", "native_payload", "native_marker" };

export fn scrapbot_register(api: *const scrapbot.RegisterApi) callconv(.c) c_int {
    scrapbot.registerComponent(api, .{
        .id = "native_stats",
        .fields = stats_fields[0..],
    }) catch return 0;
    scrapbot.registerComponent(api, .{
        .id = "native_payload",
        .fields = payload_fields[0..],
    }) catch return 0;
    scrapbot.registerComponent(api, .{
        .id = "native_marker",
        .fields = marker_fields[0..],
    }) catch return 0;

    scrapbot.registerSystem(api, .{
        .id = "native_lifecycle",
        .phase = .startup,
        .writes = lifecycle_writes[0..],
        .run = nativeLifecycle,
    }) catch return 0;

    return 1;
}

fn nativeLifecycle(context: *scrapbot.SystemContext) callconv(.c) c_int {
    const stats_query = [_][*:0]const u8{"native_stats"};
    var stats_cursor: usize = 0;
    while (scrapbot.queryNext(context, stats_query[0..], &stats_cursor) catch return 0) |stats_entity| {
        const ready = scrapbot.getBool(context, stats_entity, "native_stats", "ready") catch return 0;
        const label = scrapbot.getString(context, stats_entity, "native_stats", "label") catch return 0;
        const gain = scrapbot.getF32(context, stats_entity, "native_stats", "gain") catch return 0;
        const direction = scrapbot.getVec3(context, stats_entity, "native_stats", "direction") catch return 0;
        if (!ready or !std.mem.eql(u8, label, "ready")) {
            return 0;
        }

        const survivor = scrapbot.spawnEntity(context, "native-survivor", "Native Survivor") catch return 0;
        const payload = [_]scrapbot.FieldValue{
            scrapbot.FieldValue.int("count", 7),
            scrapbot.FieldValue.boolean("enabled", true),
            scrapbot.FieldValue.float("speed", gain + 0.25),
            scrapbot.FieldValue.vec3("direction", direction.addScaled(.{ .x = 1.0, .y = 0.0, .z = -1.0 }, 2.0)),
            scrapbot.FieldValue.string("label", "spawned"),
        };
        scrapbot.addComponent(context, survivor, "native_payload", payload[0..]) catch return 0;

        const doomed = scrapbot.spawnEntity(context, "native-doomed", "Native Doomed") catch return 0;
        const marker = [_]scrapbot.FieldValue{
            scrapbot.FieldValue.int("value", 3),
        };
        scrapbot.addComponent(context, doomed, "native_marker", marker[0..]) catch return 0;
        scrapbot.despawnEntity(context, doomed) catch return 0;

        const marker_query = [_][*:0]const u8{"native_marker"};
        var marker_cursor: usize = 0;
        var removed_count: i32 = 0;
        while (scrapbot.queryNext(context, marker_query[0..], &marker_cursor) catch return 0) |marker_entity| {
            scrapbot.removeComponent(context, marker_entity, "native_marker") catch return 0;
            removed_count += 1;
            break;
        }

        scrapbot.setI32(context, stats_entity, "native_stats", "spawned_count", 2) catch return 0;
        scrapbot.setI32(context, stats_entity, "native_stats", "removed_count", removed_count) catch return 0;
        scrapbot.setI32(context, stats_entity, "native_stats", "despawned_count", 1) catch return 0;
        scrapbot.setBool(context, stats_entity, "native_stats", "ready", false) catch return 0;
        scrapbot.setString(context, stats_entity, "native_stats", "label", "done") catch return 0;
        scrapbot.setF32(context, stats_entity, "native_stats", "gain", gain + 1.0) catch return 0;
        scrapbot.setVec3(context, stats_entity, "native_stats", "direction", direction.addScaled(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, 1.5)) catch return 0;
    }
    return 1;
}
