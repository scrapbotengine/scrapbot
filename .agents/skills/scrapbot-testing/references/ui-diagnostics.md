# Semantic UI Diagnostics

Use this workflow for hover, click, focus, typing, scrolling, clipping, popup, and editor-composition bugs. The driver operates on retained ECS UI entities and feeds ordinary input through the reconciler; it does not automate the OS pointer.

## Tight debugging loop

1. Create a small versioned script under `tests/fixtures/ui/` when it is a durable regression, or under `/tmp` for one-off exploration. Use `target.part = "panel_action"` to click or tightly capture a panel's built-in trailing title action instead of guessing an offset inside the panel title.
2. Select targets by stable UUID or name when available. Use visible text for user-facing controls. Add `origin` (`scene`, `runtime`, or `editor`) and zero-based `occurrence` to disambiguate.
3. Reproduce the minimum interaction sequence. The driver automatically scrolls clipped targets into view.
4. Assert the state that proves the behavior: `visible`, `hovered`, `active`, `focused`, `text`, or `inside_parent`.
5. End with `capture` around the smallest target that answers the visual question.
6. Run bounded headless WGPU with both `--ui-dump` and `--framegrab`.
7. Inspect the JSON first, then load the cropped PNG at original detail. Keep the full frame only when composition is the question.

```sh
bin/scrapbot run examples/ecs-showcase \
  --backend wgpu \
  --editor \
  --headless \
  --frames 120 \
  --ui-script tests/fixtures/ui/component-picker.json \
  --ui-dump /tmp/component-picker-tree.json \
  --framegrab /tmp/component-picker.png \
  --json
```

Example script:

```json
{
  "schema_version": 1,
  "timeout_frames": 120,
  "actions": [
    {"action": "click", "target": {"text": "STOP", "origin": "editor"}},
    {"action": "click", "target": {"name": "Icosphere", "origin": "editor"}},
    {"action": "click", "target": {"text": "Manage Components", "origin": "editor"}},
    {"action": "hover", "target": {"text": "+  camera", "origin": "editor"}},
    {"action": "expect", "target": {"text": "+  camera"}, "expect": "hovered"},
    {"action": "capture", "target": {"text": "+  camera"}, "padding": 12}
  ]
}
```

## Actions

- `click`, `hover`: target a retained UI node.
- `drag`: press the target center, move by `delta_x` and `delta_y`, then release on the following frame.
- `scroll`: target a node and supply `wheel_y`.
- `type`: target an input and supply `text`.
- `key`: supply `key`: `left`, `right`, `up`, `down`, `home`, `end`, `backspace`, `delete`, `tab`, `enter`, `escape`, `select_all`, `save`, `undo`, `redo`, `editor_toggle`, `run_stop`, or `pause_step`.
- `wait`: supply a positive `frames` count.
- `expect`: target a node and supply an expectation. A `text` expectation compares the action's `text` field.
- `capture`: target a node and optionally supply pixel `padding`. This defines the framegrab crop unless `--framegrab-region` is explicit.

Every non-key target may combine `uuid`, `name`, `text`, `origin`, and `occurrence`. Prefer the least brittle selector that expresses the behavior.

## Reading failures

The command writes the tree dump even when replay fails. It also preserves the last successfully rendered PNG when a later action or assertion fails.

Start with:

- `driver_action_index`, `driver_action`, and `driver_target` to locate the stalled step.
- `screen_rect`, `visible_screen_rect`, and `clip` to diagnose padding, scroll, and overdraw.
- `parent_uuid` and component-kind flags to verify retained hierarchy and control type.
- `hovered`, `active`, and `focused` to separate interaction failure from paint failure.
- `paint_order` and `visible` when the node exists but is obscured or hidden.

Do not fix a bad screenshot by adding arbitrary waits or coordinates. Use the dump to determine whether the selector, hierarchy, clipping, interaction state, or paint geometry is wrong, then repair the reusable ECS UI behavior.

## Artifact discipline

- Keep all runs bounded with `--frames`; scripted runs stop early when complete.
- Use one overview only when necessary, then steer `capture` to the smallest useful region.
- Preserve 1:1 pixels. Never downsample the sole verification artifact.
- Use `file` and `xxd -l 16` before image inspection when PNG production itself changed.
- On macOS, rerun with graphics/window-system approval if SDL cannot access displays; do not change renderer code to accommodate a sandbox error.
