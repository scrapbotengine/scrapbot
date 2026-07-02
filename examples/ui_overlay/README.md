# Machina UI Overlay

This project demonstrates the first engine-native UI slice. The scene is
text-authored ECS data: a canvas marker, screen-space rectangles, fixed-pixel
text labels, and a button marker rendered by Machina's own renderer.

```sh
mise machina check examples/ui_overlay
mise machina render examples/ui_overlay zig-out/ui-overlay.bmp
mise machina render-test examples/ui_overlay zig-out/ui-overlay-render-test.bmp
```
