# glTF Showcase

This project renders Khronos's Damaged Helmet through Scrapbot's real static glTF/GLB importer, generated resource hierarchy, and WGPU metallic-roughness PBR path. Its base-color, metallic-roughness, normal, occlusion, and emissive maps are imported with mip chains; the emissive details feed HDR bloom. Poly Haven's CC0 Studio Small 09 HDRI is imported into diffuse-irradiance and roughness-prefiltered specular cube maps for image-based lighting. A small Luau system rotates the imported model continuously.

Install the pinned, checksum-verified model and HDRI, then run the example:

```sh
mise setup-assets
mise scrapbot run examples/gltf-showcase --editor
```

The downloaded GLB and HDRI are copied into the ignored `assets/` directory by the setup task. They are not committed or redistributed by this repository. Building or distributing this example may include derived products or source bytes, so read [`tests/fixtures/external/README.md`](../../tests/fixtures/external/README.md) for upstream provenance and licensing first.
