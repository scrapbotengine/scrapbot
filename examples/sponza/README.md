# Sponza

This example loads Khronos's glTF 2.0 Sponza scene through Scrapbot's real incremental model importer. It exercises 103 textured primitives, importer-generated mesh LOD chains, per-level meshlets, 25 metallic-roughness materials, alpha-cutout surfaces, low-contrast outdoor image-based lighting from Poly Haven's Kloppenheim 01 Pure Sky, cascaded shadows, depth-aware temporal antialiasing, eleven gently animated clustered point lights arranged as warm and cool architectural pools, and a subtle 30-second camera dolly into the atrium.

Choose **LOD** in the Game debug-view selector to see the exact GPU-selected imported level. Green is source geometry; blue, purple, and orange are progressively simplified product levels. The ordinary camera view uses the same selection without Sponza-specific renderer code.

The camera enables dynamic resolution with a native-resolution ceiling, a `0.6` floor, and a 16.667 ms GPU budget. The world and post chain step down only after sustained GPU pressure, while UI stays native-resolution. Disable `dynamic_resolution` for fixed-resolution image-quality comparisons.

The `World Environment` entity owns the scene's single procedural sun. Editing its sun fields keeps the visible sky, volumetric scattering, direct lighting, and primary shadow cascades on the same direction and intensity.

Install the pinned, checksum-verified external model and HDRI, then run it:

```sh
mise setup-assets
mise scrapbot run examples/sponza --editor
```

The Sponza source package and CC0 HDRI are installed into the ignored `assets/` directory and are not committed or redistributed by Scrapbot. The model is governed by the Cryengine Limited License Agreement. Read [`tests/fixtures/external/README.md`](../../tests/fixtures/external/README.md) and the linked upstream licenses before using or distributing the source or generated import products.
