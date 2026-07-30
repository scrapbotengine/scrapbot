# UI Showcase

This project puts two unrelated visual treatments on the same public ECS UI:

- a restrained, almost-black application panel built partly from `reduced_dark` recipes;
- the saturated **Neon Overdrive** arcade panel built from a project-owned
  `scrapbot.ui_theme` resource plus the same ordered public recipes.

Both panels are aligned inside one authored `scrapbot.ui_canvas`. Its `expand` policy
preserves the 1280×720 reference scale while exposing extra logical space on wider
or taller windows, and its safe area plus start/end alignment keep the panels
anchored without Luau resize code.

Neon Overdrive's subtitle uses intrinsic word wrapping and fit-content height.
Its action deck uses child basis/grow/shrink factors: BOOST and DRIFT share one
line, while TURBO MODE wraps and grows across the second. These rectangles come
from the public retained layout system rather than showcase-specific code.

Buttons, the checkbox, input, and HDR color picker carry ordinary `scrapbot.ui_action` components. `scripts/main.luau` reads the immutable public event history with its own sequence cursor and updates the neon event monitor. Nothing in the example uses editor-only controls or callbacks.

The neon event monitor is also a public dock space. Its **EVENT BUS** and
**TELEMETRY** children are ordinary dock items with saturated HDR tab styling.
Click either tab to switch the active content. The same dock-space and
dock-item components power the Scrapbot editor workspace; the showcase merely
chooses a wholly different theme.

Run it with:

```sh
mise scrapbot run examples/ui-showcase
```

Try **BOOST**, **DRIFT**, the overdrive checkbox, the small editable field, the
HDR picker, and both dock tabs. Controls produce the same generic ordered event
contract with different semantic actions.
