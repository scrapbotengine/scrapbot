---
title: Project-Local Zig
description: Register native Zig components and systems that interoperate with Luau and scenes.
---

Scrapbot projects can declare one project-local native Zig module:

```toml
native = "native/game.zig"
```

During development, Scrapbot builds that source file as a dynamic library under `.scrapbot/native/`, loads it, and calls `scrapbot_register`.

Dynamic native module loading is supported on macOS, Linux, and Windows MSVC. Windows GNU is not a primary support target for this development loop.

## Registration Entry Point

```zig
const scrapbot = @import("scrapbot_native");

export fn scrapbot_register(api: *const scrapbot.RegisterApi) callconv(.c) c_int {
    scrapbot.registerComponent(api, .{
        .id = "velocity",
        .fields = &.{
            .{ .name = "linear", .field_type = .vec3 },
        },
    }) catch return 0;

    scrapbot.registerSystem(api, .{
        .id = "native_move",
        .phase = .update,
        .reads = &.{ "velocity", "boost" },
        .writes = &.{"scrapbot.transform"},
        .run = nativeMove,
    }) catch return 0;

    return 1;
}
```

Project native code imports the generated `scrapbot_native` API. It does not import engine internals.

## Native System Callback

```zig
fn nativeMove(context: *scrapbot.SystemContext) callconv(.c) c_int {
    const query = [_][*:0]const u8{ "scrapbot.transform", "velocity", "boost" };
    var cursor: usize = 0;

    while (scrapbot.queryNext(context, query[0..], &cursor) catch return 0) |entity| {
        const position = scrapbot.getVec3(context, entity, "scrapbot.transform", "position") catch return 0;
        const linear = scrapbot.getVec3(context, entity, "velocity", "linear") catch return 0;
        const boost = scrapbot.getF32(context, entity, "boost", "amount") catch return 0;

        scrapbot.setVec3(
            context,
            entity,
            "scrapbot.transform",
            "position",
            position.addScaled(linear, boost * context.delta_seconds),
        ) catch return 0;
    }

    return 1;
}
```

## Host API Surface

Native systems use an access-checked host facade.

Typed field helpers:

- `getBool` / `setBool`
- `getI32` / `setI32`
- `getF32` / `setF32`
- `getVec3` / `setVec3`
- `getString` / `setString`

Lifecycle helpers:

- `spawnEntity`
- `despawnEntity`
- `addComponent`
- `removeComponent`

Query helper:

- `queryNext`

The host checks declared reads and writes at query, read, write, and lifecycle command time.

## Add Components from Zig

Use typed `scrapbot.FieldValue` values:

```zig
const entity = scrapbot.spawnEntity(context, "native-survivor", "Native Survivor") catch return 0;

const fields = [_]scrapbot.FieldValue{
    scrapbot.FieldValue.int("count", 7),
    scrapbot.FieldValue.boolean("enabled", true),
    scrapbot.FieldValue.float("speed", 1.75),
    scrapbot.FieldValue.vec3("direction", .{ .x = 3.0, .y = 2.0, .z = 1.0 }),
    scrapbot.FieldValue.string("label", "spawned"),
};

scrapbot.addComponent(context, entity, "native_payload", fields[0..]) catch return 0;
```

Structural commands use the same semantics as Luau:

- Spawns happen immediately and are rolled back if the system fails.
- Add/remove component and despawn commands are queued.
- Queued commands flush only after the native system returns success.

## Live Reload

When native source changes during `scrapbot run`, Scrapbot rebuilds and reloads the module, rebuilds the ECS program, validates the current scene, and swaps only if every stage succeeds.

Failed native builds, loads, or registrations keep the last-known-good program active and report diagnostics.

## Static Build Direction

Dynamic loading is the development loop. `scrapbot build` currently packages host-platform bundles with a prebuilt native dynamic library artifact, so the bundled project can load native systems without rebuilding source on the target machine.

The registration entry point and source-level API are still designed for a future SDK/static build path that can statically link the same project-native source on platforms where dynamic code loading is impossible or forbidden.
