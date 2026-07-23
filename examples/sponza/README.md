# Sponza

This example loads Khronos's glTF 2.0 Sponza scene through Scrapbot's real incremental model importer. It exercises 103 textured primitives, 25 metallic-roughness materials, alpha-cutout surfaces, imported image-based lighting, cascaded shadows, and an initial set of clustered point lights.

Install the pinned, checksum-verified external model and HDRI, then run it:

```sh
mise setup-assets
mise scrapbot run examples/sponza --editor
```

The 50 MiB Sponza source package is installed into the ignored `assets/` directory and is not committed or redistributed by Scrapbot. The model is governed by the Cryengine Limited License Agreement. Read [`tests/fixtures/external/README.md`](../../tests/fixtures/external/README.md) and the linked upstream license before using or distributing its source or generated import products.
