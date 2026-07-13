---
title: Live Editor
description: Inspect, navigate, select, and transform entities while a Scrapbot project is running.
---

Scrapbot's editor is part of the running project rather than a separate executable. It inspects the same live ECS world, systems, and renderer launched by `scrapbot run`.

## Open the editor

Start a visible WGPU run and press `Ctrl+Esc` to toggle the editor:

```sh
bin/scrapbot run examples/ecs-showcase --backend wgpu --window
```

Pass `--editor` to start with the editor already open:

```sh
bin/scrapbot run examples/ecs-showcase --backend wgpu --window --editor
```

The project keeps running when the editor opens or closes. Its world and project-authored UI fill all currently available center space without enforcing a fixed aspect ratio. During a native window resize, the simulation, surface, camera aspect, viewport, and editor layout continue updating throughout the drag.

## Navigate the scene view

The editor creates an editor-owned scene-camera entity whose initial view matches the project camera. Moving it does not change the project's camera.

| Input | Action |
| --- | --- |
| Hold right mouse button | Capture scene-camera input |
| Mouse | Look around while captured |
| `W` / `S` | Move forward / backward |
| `A` / `D` | Move left / right |
| `Space` | Move up |
| `Ctrl` | Move down |
| Release right mouse button | Return to normal pointer interaction |

Closing and reopening the editor preserves the scene-camera viewpoint for the current run.

## Browse and inspect entities

The scene sidebar lists every live entity, including objects that do not come from the scene TOML:

| Label | Meaning |
| --- | --- |
| `SCENE` | Authored by the loaded scene |
| `LIVE` | Spawned while the project is running |
| `EDIT` | Owned temporarily by the editor |

Click an entry to select it, or click rendered geometry in the viewport. Viewport picking tests the rendered triangles and selects the nearest hit; clicking empty viewport space clears the selection. The browser scrolls to reveal a viewport-picked entity and automatically clears selection if that entity despawns.

The inspector reports the selected entity's name, identity, provenance, attached components, field names, and current values. The scene browser and inspector scroll independently with pixel-continuous targets, frame-time smoothing without line snapping, clipped partial content, and proportional scrollbars. Fractional trackpad deltas remain fractional.

## Translate an entity

Selecting an entity with a Transform adds a world-space translation gizmo:

- Red moves along X.
- Green moves along Y.
- Blue moves along Z.

Hover an axis to emphasize it, then drag to move the entity along that axis. The inspector updates with the live Transform values. Gizmo ownership is represented by a transient editor component on the selected entity and is removed when selection changes or the editor closes.

Transform edits currently affect only the running world. Scene persistence, undo, snapping, rotation, scaling, and multi-selection are not implemented yet.

## Capture the editor

For deterministic documentation or renderer checks, combine the editor with a headless framegrab:

```sh
bin/scrapbot run examples/ecs-showcase \
  --backend wgpu \
  --editor \
  --headless \
  --frames 20 \
  --framegrab /tmp/scrapbot-editor.png
```

Headless framegrabs do not provide pointer interaction. See [Rendering And Testing](/guides/rendering-testing/) for 1:1 region exports and visual verification guidance.
