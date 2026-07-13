# ADR-013: Precompute MTSDF font atlases

**Date:** 2026-07-12

## Context

UI text must remain sharp across arbitrary sizes without depending on platform font APIs or shipping a native font rasterizer in every game. Bitmap atlases couple quality to one baked size. Runtime SDF generation also adds startup work, and the available `stb_truetype` SDF path did not produce usable fields for the selected font.

## Decision

Generate built-in font atlases offline with `msdf-atlas-gen`, using MTSDF so the RGB channels preserve sharp corners and the alpha channel remains available for future true-distance effects. Store the atlas as linear RGBA8 data and generate an Odin glyph-metrics table from the tool's layout output. Reconstruct coverage in WGSL from the median RGB distance with derivative-based antialiasing.

The engine embeds Inter as its initial screen-oriented typeface. The source font and its SIL Open Font License remain beside the generated atlas. The generator is an asset-development dependency, not a game-runtime dependency.

## Consequences

Text scales smoothly from one atlas, and packaged games remain independent of system fonts, FreeType, and C++ runtime libraries. Font changes require regenerating both atlas and metrics with a pinned tool version. This slice still handles only the embedded ASCII set; Unicode shaping, fallback, kerning, project fonts, and dynamic atlas growth remain future work.
