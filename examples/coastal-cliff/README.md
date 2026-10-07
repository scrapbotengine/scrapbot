# Coastal Cliff

This diagnostic project isolates one Coastal Cliff 04 photogrammetry instance.
It exercises indexed mesh import, ordinary LODs, and a stretched transform without
water, foliage, scripts, or post-processing.

Install the pinned CC0 source fixture and run the scene:

```sh
mise setup-assets
mise scrapbot -- run examples/coastal-cliff
```

Use Lit, Depth, and LOD debug views to inspect topology and level selection.
The complete mesh and its LODs remain resident.

Run the focused import check with:

```sh
mise test-coastal-cliff
```
