# Sponza

This example loads Khronos's glTF 2.0 Sponza scene through Scrapbot's real incremental model importer. It exercises 103 textured primitives, 25 metallic-roughness materials, alpha-cutout surfaces, low-contrast outdoor image-based lighting from Poly Haven's Kloppenheim 01 Pure Sky, cascaded shadows, depth-aware temporal antialiasing, eleven gently animated clustered point lights arranged as warm and cool architectural pools, and a subtle 30-second camera dolly into the atrium.

Install the pinned, checksum-verified external model and HDRI, then run it:

```sh
mise setup-assets
mise scrapbot run examples/sponza --editor
```

The Sponza source package and CC0 HDRI are installed into the ignored `assets/` directory and are not committed or redistributed by Scrapbot. The model is governed by the Cryengine Limited License Agreement. Read [`tests/fixtures/external/README.md`](../../tests/fixtures/external/README.md) and the linked upstream licenses before using or distributing the source or generated import products.
