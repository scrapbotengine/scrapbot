# External development fixtures

This directory describes heavyweight or license-constrained development fixtures that Scrapbot downloads instead of committing to the repository.

Run `mise setup` for a complete contributor checkout, or `mise setup-assets` to install only these fixtures. Downloads are pinned by immutable source URL, byte length, and SHA-256 in `manifest.json`. `mise check-assets` verifies the local files without accessing the network.

Downloaded files live under ignored `downloads/` state. The setup tool may copy verified files to ignored example `assets/` placements declared by the manifest, but neither downloads nor placements may be added to Git or included in Scrapbot's own packages and releases.

## Khronos Damaged Helmet

- Local path: `downloads/gltf/DamagedHelmet.glb`
- Upstream: [Khronos glTF Sample Assets](https://github.com/KhronosGroup/glTF-Sample-Assets/tree/5bad5aaa0bbb5d0f9cdc934e626f27d0df1e79b8/Models/DamagedHelmet)
- Purpose: real-world glTF 2.0 import and rendering development
- Licensing: the rebuilt glTF is credited under CC BY 4.0 and the earlier model under CC BY-NC 4.0. Downloading the file does not remove those terms. Read the upstream README before using it outside Scrapbot's development tests.

The ordinary test suite must remain independent of external downloads. Tests that require these fixtures should be explicit integration tasks and produce a direct `mise setup-assets` instruction when a fixture is absent.

## Poly Haven Studio Small 09

- Local path: `downloads/hdr/studio_small_09_1k.hdr`
- Upstream: [Poly Haven](https://polyhaven.com/a/studio_small_09)
- Author: Sergej Majboroda
- Purpose: deterministic HDR environment import and image-based-lighting development
- Licensing: CC0

## Poly Haven Kloppenheim 01 Pure Sky

- Local path: `downloads/hdr/kloppenheim_01_puresky_1k.hdr`
- Upstream: [Poly Haven](https://polyhaven.com/a/kloppenheim_01_puresky)
- Authors: Greg Zaal and Jarod Guest
- Purpose: neutral low-contrast outdoor image-based lighting for the Sponza architectural workload
- Licensing: CC0

## Khronos Sponza

- Local path: `downloads/gltf/Sponza/`
- Upstream: [Khronos glTF Sample Assets](https://github.com/KhronosGroup/glTF-Sample-Assets/tree/2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf/Models/Sponza/glTF)
- Purpose: large multi-material external-file glTF import, GPU-driven rendering, clustered lighting, and shadow development
- Pinned shape: 71 files, 103 primitives, 25 materials, 192,496 vertices, and 262,267 triangles
- Licensing: model files use the Cryengine Limited License Agreement (`LicenseRef-CRYENGINE-Agreement`); repository metadata uses CC BY 4.0. Read the pinned upstream `LICENSE.md` before redistributing any model bytes.

Sponza is a manifest bundle: every file has an individual byte count and SHA-256, while setup downloads up to six files concurrently. The verified files are copied into ignored `examples/sponza/assets/` state. Neither the bundle nor its 393 MiB uncompressed Scrapbot import product belongs in Git or engine distributions.

## Poly Haven Virtual Wilds

- Local path: `downloads/gltf/VirtualWilds/`
- Upstream: [Poly Haven models](https://polyhaven.com/models)
- Purpose: high-density photogrammetry import, generated LODs, virtual-geometry paging, bounded residency, and temporal streaming development
- Pinned shape: 15 files, 3 models, 1,183,929 vertices, 2,300,990 source triangles, and 5,970 cluster pages
- Licensing: CC0

The bundle contains [Coastal Cliff 04](https://polyhaven.com/a/coastal_cliff_04) and [Coast Rocks 01](https://polyhaven.com/a/coast_rocks_01), photographed and processed by Rob Tuytel with cleanup by Rico Cilliers. [Dead Tree Trunk 02](https://polyhaven.com/a/dead_tree_trunk_02) was photographed by Jenelle van Heerden and processed by Rico Cilliers.

`mise setup-assets` copies the verified bundle into ignored `examples/virtual-wilds/assets/` state. The example compiles these ordinary glTF inputs into Scrapbot's versioned split model products; neither source nor imported products belong in Git or Scrapbot distributions.

Run `mise test-gltf` to validate the real-world import product, or `mise test-gltf-gpu` to import it and produce a bounded headless WGPU framegrab in the platform temporary directory.

`mise setup-assets` also copies the verified helmet and studio HDRI into the ignored `examples/gltf-showcase/assets/` directory, and the pure-sky HDRI into `examples/sponza/assets/`. Run `mise scrapbot run examples/gltf-showcase --editor` for the persistent interactive showcase.

Run `mise test-sponza` for the explicit heavyweight import contract, or `mise test-sponza-gpu` to import it and capture a bounded WGPU frame. Launch the persistent example with `mise scrapbot run examples/sponza --editor`.

Run `mise test-virtual-wilds` for the pinned three-scan import contract. `mise test-virtual-wilds-gpu` additionally drives the camera long enough to require detail-page reads, checks the 128 MiB residency bound, and captures a WGPU frame. Launch the interactive tour with `mise scrapbot -- run examples/virtual-wilds --editor`.
