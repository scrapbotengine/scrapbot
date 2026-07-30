# Cluster Cathedral

This example fills a long dark hall with **320 independently animated HDR point lights**. Sixteen lights orbit each of twenty architectural ribs while traveling pulses move through the palette. The result exercises Scrapbot's 16×9×24 GPU-computed light clusters, growable light/index buffers beyond their initial 256-light capacity, retained dirty transforms, shared geometry/material batching, bloom, and cascaded shadows in one deliberately excessive scene.

The cathedral architecture and suspended sculptures are authored in `scenes/main.scene.toml`, so they remain visible and editable while playback is stopped. The lights are disposable runtime entities reconstructed on each Play. Run `node generate-scene.mjs` from this directory after changing the generated architectural layout.

Run it directly:

```sh
mise scrapbot run examples/clustered-lights
```

Or open the live editor and watch the performance diagnostics:

```sh
mise scrapbot run examples/clustered-lights --editor
```

The project camera drifts gently through the cathedral. Opening the editor gives you a separate fly camera, so you can move through the individual lighting volumes without disturbing the authored view.

## Inspect Hi-Z occlusion

Cluster Cathedral is also Scrapbot's dense occlusion-debugging lab:

1. Open the editor and click **Pause** so the animated marker transforms stop changing.
2. Open **View / Camera** over the Game surface.
3. Choose **Occlusion Queries** and wait one frame for a reusable Hi-Z pyramid.
4. Click **Freeze** to keep the current GPU evidence while inspecting the image.

The dim world remains as spatial context. Mint rectangles survived their conservative Hi-Z query; pink rectangles were rejected. Each rectangle is the exact projected screen-space footprint sampled by an object or meshlet query, not a CPU approximation.

The Performance panel distinguishes whole-object and meshlet occlusion. Its **Hi-Z Culling** row also explains when queries are unavailable, below the normal scene-size threshold, invalidated by scene or camera changes, warming up, or active.

The checked-in semantic replay automates the complete workflow and captures only the Game viewport:

```sh
bin/scrapbot run examples/clustered-lights \
  --headless \
  --editor \
  --no-hot-reload \
  --frames 60 \
  --ui-script tests/fixtures/ui/game-debug-occlusion.json \
  --framegrab /tmp/cluster-cathedral-occlusion.png \
  --json
```
