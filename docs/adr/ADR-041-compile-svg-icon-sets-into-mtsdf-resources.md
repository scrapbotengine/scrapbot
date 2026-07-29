# ADR-041: Compile SVG icon sets into MTSDF resources

**Date:** 2026-07-29

## Context

Scrapbot's ECS UI currently represents five control icons with an enum and
draws them as renderer-owned lines or disclosure geometry. That path cannot
name project artwork, cannot be extended without changing every public API
surface, and gives buttons capabilities that a standalone UI element cannot
use. It also tempts editor composition to accumulate private drawing behavior.

Projects need scalable, themeable icons through the same public UI contract as
the editor. SVG is a suitable authored format, but parsing arbitrary SVG
documents or rebuilding vector geometry during ordinary frames would expand
the packaged runtime and violate Scrapbot's change-driven derived-state
invariant.

## Decision

Treat an icon set as a standalone `scrapbot.icon_set` project resource with a
stable non-zero UUID, editable name, and safe source directory under `assets/`.
Each source SVG filename defines one stable symbol name within that set.

Compile supported SVG geometry into a deterministic linear RGBA8 MTSDF atlas
and symbol-metadata product under ignored engine state. Normalize primitives,
groups, transforms, strokes, and compound paths into filled monochrome
outlines before distance-field generation. Reject unsupported animation,
external references, filters, masks, embedded raster images, gradients, and
multicolor paint with resource- and symbol-specific diagnostics. Cache keys
include source and dependency contents, normalized settings, the exact
`msdf-atlas-gen` 1.4.0 contract, compiler schema, and symbol ordering. Cache
misses reject another generator version rather than producing host-dependent
bytes. Product writes are atomic and unchanged inputs reuse the last valid
product.

Load icon sets into a type-specific runtime registry. Authored references use
the icon-set UUID plus symbol name; resolved runtime state uses a generational
handle plus entry content version. A content replacement preserves a live
handle and increments its version, disappearance invalidates its generation,
and reappearance reuses the slot with a new generation. UI and renderer caches
invalidate only consumers of the changed set. WGPU uploads only new or changed
atlas layers.

Expose icons through a standalone public `scrapbot.ui_icon` ECS component.
Layout owns its rectangle; the icon component selects an icon-set UUID, symbol,
HDR tint, and inset. Paint preserves the compiled plane aspect and centers it
inside the available padded rectangle. Buttons and future controls compose the
same icon reference and resolver rather than owning an icon enum or private
paint implementation.

Ship a curated monochrome built-in catalog as an embedded icon-set product with
a reserved stable UUID. The catalog enters the same registry, lookup,
measurement, paint, and GPU path as project icon sets. Built-in theme recipes
map semantic tokens such as transport, search, disclosure, and collection
actions to ordinary icon references. Projects may replace those mappings,
reference their own sets directly, or ignore icon recipes.

Keep multicolor illustrations, logos, photographs, and arbitrary raster/vector
art outside the icon contract. A future general image component may support
those assets without weakening predictable icon tinting and batching.

The SVG compiler is an asset-development dependency on a cache miss, not a
packaged-game runtime dependency. Packages contain validated icon products and
the runtime never parses SVG.

## Consequences

Projects, native extensions, Luau scripts, text-first scenes, themes, and the
editor share one scalable icon facility. Adding an icon no longer expands an
engine enum, and controls remain consumers of reusable UI/resource behavior.
MTSDF atlases keep arbitrary scaling and HiDPI output sharp while preserving
paint order and batching through a bounded texture array.

The importer must implement and test a precise SVG subset, deterministic
normalization and packing, cache recovery, symbol diagnostics, and atlas
capacity limits. Every public icon field must remain synchronized across ECS
storage, TOML, Luau, native ABI, generated declarations, examples, tests, and
documentation. Monochrome-only authoring is intentionally narrower than SVG as
a general illustration format.
