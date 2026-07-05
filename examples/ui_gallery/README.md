# Machina UI Gallery

This project demonstrates the current retained UI primitives: canvas scaling,
screen-space panels, rounded borders, text labels, layout containers, scroll
views, buttons, non-rendering hit areas, command ids, command events, toggles,
progress bars, separators, and script-mutated UI state.

Button labels are parented to their button rects with `machina.ui.layout.item`,
so they inherit the button's resolved layout instead of duplicating absolute
positions. This is the preferred pattern for small composite controls.

The content area includes a responsive table form row that demonstrates
`machina.ui.table` column split control.

The primary action button also has a `machina.ui.hit_area` that is slightly
larger than its visible rect, demonstrating how thin or compact controls can
keep ergonomic pointer targets without adding invisible renderer-only widgets.

```sh
mise machina check examples/ui_gallery
mise machina render examples/ui_gallery zig-out/ui-gallery.png
mise machina render-test examples/ui_gallery zig-out/ui-gallery-render-test.png
```
