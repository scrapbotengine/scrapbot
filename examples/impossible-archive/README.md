# The Impossible Archive

The Impossible Archive is a generated, ordinary glTF model designed to make Scrapbot's virtual
geometry pipeline visible. Its carved wall reliefs, columns, arch ribs, floor tiles, brass inlays,
and emissive glyphs are baked as unique source geometry inside one imported model.

Nothing in the renderer recognizes this example. It uses the same public model resource, camera,
lighting, shadow, fog, script, and project-render configuration available to every Scrapbot game.

The generator keeps hierarchy input spatially coherent by placing each four-bay region in its own
glTF primitive. They remain children of one imported model and reuse only three materials. The
renderer independently culls their hierarchy work, then merges compatible regions into bounded
material submission spans.

Columns are assembled as adjoining exterior sections rather than overlapping capped cylinders,
each arch closes its endpoint against the capital, and recessed barrel-vault panels connect the
ribs across every bay. This keeps close inspection and directional self-shadowing free from hidden
coplanar faces while preserving a complete interior shell from oblique viewpoints.

## Generate the archive

Generate the quick development asset and run it in the editor:

```sh
mise archive-assets --preset small
mise scrapbot run examples/impossible-archive --editor
```

The generated GLB and imported products are ignored. Generation is deterministic and needs only
the repository's pinned Node.js runtime.

Three presets trade generation/import time for source detail:

- `small` is the fast iteration asset, with roughly 70,000 source triangles.
- `showcase` creates roughly 360,000 unique source triangles and is the intended demonstration. It
  stays inside the current portable compact-layout capacity and the checked-in 64 MiB
  fine-geometry residency budget.
- `unhinged` creates roughly 19 million source triangles for deliberate import and residency
  stress. Expect a large GLB, substantial import time, high temporary memory use, and the safe
  whole-primitive fallback on capacity-limited portable layouts.

Pass `--json` to make the generator report its exact output path, bytes, vertices, triangles, and
per-primitive triangle counts as one machine-readable document.

## What to look for

The authored camera advances through the first twelve bays over 30 seconds, then jumps back to the
threshold. That discontinuity exercises camera-cut and visibility recovery. Predictive prefetch
remains enabled, while the checked-in 64 MiB budget keeps the showcase preset fully resident for a
clean presentation. Lower the public `render.virtual_geometry_budget_mb` setting deliberately, or
generate `unhinged`, when testing residency pressure and coarse-fallback recovery.

Open the Game debug-view selector and choose **Virtual Geometry**. The colored clusters are the
actual fully resident frontier selected by the GPU; amber marks a branch waiting for its complete
fine page group. **LOD** shows the whole-object imported fallback levels, and **Meshlets** exposes
the underlying source partition.

For a reproducible performance capture, use:

```sh
mise archive-profile
```

The task prints the profile directory. Compare profiles only on the same adapter and dimensions;
the public profiler records the workload and frame-local virtual-geometry counter deltas alongside
CPU and valid GPU timings.
