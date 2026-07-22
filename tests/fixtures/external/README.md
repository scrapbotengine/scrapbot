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

Run `mise test-gltf` to validate the real-world import product, or `mise test-gltf-gpu` to import it and produce a bounded headless WGPU framegrab in the platform temporary directory.

`mise setup-assets` also copies the verified helmet and studio HDRI into the ignored `examples/gltf-showcase/assets/` directory. Run `mise scrapbot run examples/gltf-showcase --editor` for the persistent interactive showcase.
