# Scrapbot Examples

This directory contains complete Scrapbot project directories.

For a playable Luau game demonstrating runtime input and the wider ECS/render/UI stack:

```sh
mise scrapbot run examples/asteroids
```

Run the minimal example with:

```sh
mise scrapbot run examples/minimal
```

Validate it without running a frame with:

```sh
mise scrapbot check examples/minimal
```

`check` also refreshes `.scrapbot/types/scrapbot.d.luau` from the project's Luau component schemas.

For a visual high-churn workload driven by retained native query chunks and SIMD systems:

```sh
mise scrapbot run examples/ecs-stress --editor
```
