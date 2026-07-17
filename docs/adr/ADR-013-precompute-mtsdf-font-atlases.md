# ADR-013: Precompute MTSDF font atlases

**Date:** 2026-07-12

## Context

UI text must remain sharp across arbitrary sizes without depending on platform font APIs or shipping a native font rasterizer in every game. Bitmap atlases couple quality to one baked size. Runtime SDF generation also adds startup work, and the available `stb_truetype` SDF path did not produce usable fields for the selected font.

## Decision

Generate font atlases with `msdf-atlas-gen`, using MTSDF so the RGB channels preserve sharp corners and the alpha channel remains available for future true-distance effects. Store each atlas as linear RGBA8 data alongside JSON glyph metrics. Reconstruct coverage in WGSL from the median RGB distance with derivative-based antialiasing.

The engine embeds Inter as its always-available screen-oriented fallback. The source font and its SIL Open Font License remain beside the generated atlas.

Projects may declare up to 15 named TTF or OTF resources from their `assets/` directory. `check`, `build`, `run`, hot reload, and packaging hash each source font plus the atlas settings and automatically invoke `msdf-atlas-gen` only when its generated `.scrapbot/cache/fonts/` artifacts are absent or stale. The generator is therefore an asset-development dependency on a cache miss, not a packaged-game runtime dependency. `SCRAPBOT_MSDF_ATLAS_GEN` may override the executable path.

WGPU stores embedded Inter in layer zero of a fixed texture array and project fonts in layers one through fifteen. Each glyph paint command carries its atlas layer, preserving mixed-font paint order and clipping without regrouping commands into per-font passes. UI text, buttons, inputs, and panel titles select fonts by declared project resource name; an unavailable runtime resource resolves to Inter.

## Consequences

Text scales smoothly from one atlas per font, and packaged games remain independent of system fonts, FreeType, atlas generators, and C++ runtime libraries. Source or compiler-setting changes regenerate the matching cache artifact rather than all fonts. Packaging includes the generated artifacts.

This slice remains ASCII-only and uses fixed 512×512 atlases generated at size 48 with an eight-pixel distance range. It has no shaping, kerning, Unicode fallback chain, variable-font axis selection, or dynamic atlas growth. Inter is the resource fallback, but unsupported characters still render as `?`.
