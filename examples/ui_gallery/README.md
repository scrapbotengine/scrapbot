# Scrapbot UI Gallery

This project demonstrates the current retained UI primitives: canvas scaling,
screen-space panels, rounded borders, text labels, layout containers, scroll
views, buttons, non-rendering hit areas, command ids, command events, toggles,
progress bars, separators, and script-mutated UI state.

The `inspector-control-sample` entity is intentionally near the top of the
scene so `scrapbot test` and selected editor renders can exercise the current
inspector controls for booleans, ints, floats, strings, vec3 lanes, and the
built-in geometry primitive selector.

Button labels are parented to their button rects with `scrapbot.ui.layout.item`,
so they inherit the button's resolved layout instead of duplicating absolute
positions. This is the preferred pattern for small composite controls.

The content area includes a responsive table form row that demonstrates
`scrapbot.ui.table` column split control.

The primary action button also has a `scrapbot.ui.hit_area` that is slightly
larger than its visible rect, demonstrating how thin or compact controls can
keep ergonomic pointer targets without adding invisible renderer-only widgets.

```sh
mise scrapbot check examples/ui_gallery
mise scrapbot test examples/ui_gallery
mise scrapbot render examples/ui_gallery odin-out/ui-gallery.png
mise scrapbot render-test examples/ui_gallery odin-out/ui-gallery-render-test.png
mise scrapbot render --editor --select inspector-control-sample examples/ui_gallery odin-out/ui-gallery-inspector.png
```
