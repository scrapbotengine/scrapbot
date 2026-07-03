const machina = @import("machina_native");

const velocity_fields = [_]machina.ComponentField{
    .{ .name = "linear", .field_type = .vec3 },
};

const native_move_reads = [_][*:0]const u8{ "velocity", "boost" };
const native_move_writes = [_][*:0]const u8{"machina.transform"};

export fn machina_register(api: *const machina.RegisterApi) callconv(.c) c_int {
    machina.registerComponent(api, .{
        .id = "velocity",
        .fields = velocity_fields[0..],
    }) catch return 0;

    machina.registerSystem(api, .{
        .id = "native_move",
        .phase = .update,
        .reads = native_move_reads[0..],
        .writes = native_move_writes[0..],
        .run = nativeMove,
    }) catch return 0;

    return 1;
}

fn nativeMove(context: *machina.SystemContext) callconv(.c) c_int {
    const query = [_][*:0]const u8{ "machina.transform", "velocity", "boost" };
    var cursor: usize = 0;
    while (machina.queryNext(context, query[0..], &cursor) catch return 0) |entity| {
        const position = machina.getVec3(context, entity, "machina.transform", "position") catch return 0;
        const linear = machina.getVec3(context, entity, "velocity", "linear") catch return 0;
        const boost = machina.getF32(context, entity, "boost", "amount") catch return 0;
        machina.setVec3(context, entity, "machina.transform", "position", position.addScaled(linear, boost * context.delta_seconds)) catch return 0;
    }
    return 1;
}
