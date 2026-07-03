# Native Motion

This example uses a project-local Zig module at `native/game.zig`.

- Zig registers the `velocity` component.
- Luau registers the `boost` component.
- The native `native_move` system reads both and writes `machina.transform`.

Run it with:

```sh
mise machina run examples/native_motion
```
