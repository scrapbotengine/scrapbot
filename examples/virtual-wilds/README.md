# Virtual Wilds

Virtual Wilds is Scrapbot's real-world virtual-geometry showcase. It builds a moving coastal route
from three full-detail CC0 Poly Haven scans: Coastal Cliff 04, Coast Rocks 01, and Dead Tree Trunk
02.

Install the ignored source fixtures, then launch the editor:

```sh
mise setup-assets
mise scrapbot -- run examples/virtual-wilds --editor
```

The source assets are not stored in Git. `mise setup-assets` downloads immutable,
checksum-verified files and places them under `assets/`. Scrapbot compiles them into its ordinary
versioned runtime products on first use.

Use the camera's `virtual_geometry`, `meshlets`, and `lod` debug views to inspect the selected
cluster frontier. The scans contain about 2.3 million source triangles and compile into 5,970
streamable cluster pages. The 128 MiB residency budget is intentionally smaller than that complete
detail set, so the camera tour exercises visible page demand, predictive prefetch, and eviction
while coarse geometry remains available.

All scanned assets are from [Poly Haven](https://polyhaven.com/) and licensed CC0. See
[`tests/fixtures/external/README.md`](../../tests/fixtures/external/README.md) for pinned sources,
authors, and fixture policy.
