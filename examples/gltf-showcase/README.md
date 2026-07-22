# glTF Showcase

This project renders Khronos's Damaged Helmet through Scrapbot's real static glTF/GLB importer, generated resource hierarchy, material path, and WGPU renderer. A small Luau system rotates the imported model continuously.

Install the pinned, checksum-verified model and run the example:

```sh
mise setup-assets
mise scrapbot run examples/gltf-showcase --editor
```

The downloaded GLB is copied into the ignored `assets/` directory by the setup task. It is not committed or redistributed by this repository. Building or distributing this example may include derived products or source bytes, so read [`tests/fixtures/external/README.md`](../../tests/fixtures/external/README.md) for upstream provenance and licensing first.
