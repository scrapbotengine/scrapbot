# Sponza

This example loads Khronos's glTF 2.0 Sponza scene through Scrapbot's real incremental model importer. It exercises 103 textured primitives, 25 metallic-roughness materials, alpha-cutout surfaces, low-contrast outdoor image-based lighting from Poly Haven's Kloppenheim 01 Pure Sky, cascaded shadows, depth-aware temporal antialiasing, eleven gently animated clustered point lights arranged as warm and cool architectural pools, and a subtle 30-second camera dolly into the atrium.

The camera uses `resolution_scale = 0.75` as a quality/performance showcase: the world and post chain render at 75% of output width and height, while UI stays native-resolution. Set it to `1` when comparing native-resolution image quality.

The `World Environment` entity owns the scene's single procedural sun. Editing its sun fields keeps the visible sky, volumetric scattering, direct lighting, and primary shadow cascades on the same direction and intensity.

Install the pinned, checksum-verified external model and HDRI, then run it:

```sh
mise setup-assets
mise scrapbot run examples/sponza --editor
```

The Sponza source package and CC0 HDRI are installed into the ignored `assets/` directory and are not committed or redistributed by Scrapbot. The model is governed by the Cryengine Limited License Agreement. Read [`tests/fixtures/external/README.md`](../../tests/fixtures/external/README.md) and the linked upstream licenses before using or distributing the source or generated import products.
