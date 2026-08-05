# Virtual Geometry Cliff

This diagnostic project isolates one real Coastal Cliff 04 photogrammetry instance from Virtual
Wilds. It preserves the failing cliff transform and the captured near-cliff camera pose while
removing water, foliage, procedural scatter, scripts, post-processing, and competing geometry.

The project intentionally uses a 32 MiB virtual-geometry budget with prefetch disabled. The source
model's complete streamable product is substantially larger, so the renderer must maintain a
complete coarse fallback while admitting and evicting detail pages.

Install the pinned CC0 Poly Haven fixture, then launch the editor with live diagnostics:

```sh
mise setup-assets
mise scrapbot run examples/virtual-geometry-cliff --live-debug
```

Use the editor fly camera to approach, cross, and orbit the cliff from arbitrary directions. A
correct renderer may change geometric detail, but it must never expose the background through
missing clusters. Select `Cliff Camera` and switch its `debug_view` between `lit`, `depth`, and
`virtual_geometry` when isolating topology, depth, and the active cluster frontier.

Run the focused import check with:

```sh
mise test-virtual-geometry-cliff
```
