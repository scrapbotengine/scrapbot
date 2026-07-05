# Native Motion

This example uses a project-local Zig module at `native/game.zig`.

- Zig registers the `motion` component.
- Luau registers the `boost` component.
- The native `native_move` system reads both and writes `scrapbot.transform`.
- Motion is computed from bounded sine/cosine curves, so the objects stay in frame while testing native hot reload.

Run it with:

```sh
mise scrapbot run examples/native_motion
```
