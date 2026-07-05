const scrapbot = @import("scrapbot_native");

const velocity_fields = [_]scrapbot.ComponentField{
    .{ .name = "linear", .field_type = .vec3 },
};

const native_move_reads = [_][*:0]const u8{ "velocity", "boost" };
const native_move_writes = [_][*:0]const u8{"scrapbot.transform"};

export fn scrapbot_register(api: *const scrapbot.RegisterApi) callconv(.c) c_int {
    scrapbot.registerComponent(api, .{
        .id = "velocity",
        .fields = velocity_fields[0..],
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
    const query = [_][*:0]const u8{ "scrapbot.transform", "velocity", "boost" };
    var cursor: usize = 0;
    while (scrapbot.queryNext(context, query[0..], &cursor) catch return 0) |entity| {
        const position = scrapbot.getVec3(context, entity, "scrapbot.transform", "position") catch return 0;
        const linear = scrapbot.getVec3(context, entity, "velocity", "linear") catch return 0;
        const boost = scrapbot.getF32(context, entity, "boost", "amount") catch return 0;
        scrapbot.setVec3(context, entity, "scrapbot.transform", "position", position.addScaled(linear, boost * context.delta_seconds)) catch return 0;
    }
    return 1;
}
