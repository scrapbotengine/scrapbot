const scrapbot = @import("scrapbot_native");

const motion_fields = [_]scrapbot.ComponentField{
    .{ .name = "origin", .field_type = .vec3 },
    .{ .name = "amplitude", .field_type = .vec3 },
    .{ .name = "phase", .field_type = .float },
    .{ .name = "speed", .field_type = .float },
};

const native_move_reads = [_][*:0]const u8{ "motion", "boost" };
const native_move_writes = [_][*:0]const u8{"scrapbot.transform"};
var elapsed_seconds: f32 = 0.0;

export fn scrapbot_register(api: *const scrapbot.RegisterApi) callconv(.c) c_int {
    scrapbot.registerComponent(api, .{
        .id = "motion",
        .fields = motion_fields[0..],
    }) catch return 0;

    scrapbot.registerSystem(api, .{
        .id = "native_move",
        .phase = .update,
        .reads = native_move_reads[0..],
        .writes = native_move_writes[0..],
        .run = nativeMove,
    }) catch return 0;

    return 1;
}

fn nativeMove(context: *scrapbot.SystemContext) callconv(.c) c_int {
    elapsed_seconds += context.delta_seconds;

    const query = [_][*:0]const u8{ "scrapbot.transform", "motion", "boost" };
    var cursor: usize = 0;
    while (scrapbot.queryNext(context, query[0..], &cursor) catch return 0) |entity| {
        const origin = scrapbot.getVec3(context, entity, "motion", "origin") catch return 0;
        const amplitude = scrapbot.getVec3(context, entity, "motion", "amplitude") catch return 0;
        const phase = scrapbot.getF32(context, entity, "motion", "phase") catch return 0;
        const speed = scrapbot.getF32(context, entity, "motion", "speed") catch return 0;
        const boost = scrapbot.getF32(context, entity, "boost", "amount") catch return 0;
        const t = elapsed_seconds * speed * boost + phase;
        scrapbot.setVec3(context, entity, "scrapbot.transform", "position", .{
            .x = origin.x + amplitude.x * @sin(t),
            .y = origin.y + amplitude.y * @cos(t * 1.17),
            .z = origin.z + amplitude.z * @sin(t * 0.73),
        }) catch return 0;
    }
    return 1;
}
