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

The route also demonstrates project-authored vertex and fragment hooks. A subdivided procedural
plane becomes animated coastal water with geometric swells and derivative-driven surface detail.
The shader composes guarded screen-space refraction, Beer–Lambert absorption and scattering,
environment Fresnel reflection, and narrow depth-intersection and crest foam.

The material uses Scrapbot's sorted transparent pass and public scene-sampling ABI. Virtual Wilds
is therefore a normal consumer of the same shader-resource and material API available to every
project, not a renderer-only water path.

The water shader adapts Stefan Gustavson and Ian McEwan's
[`psrdnoise2.wgsl`](https://github.com/stegu/psrdnoise) at commit
`419175a270862ce7ae692038fafafb42ec0427e9`. psrdnoise is distributed under the MIT License; the
required copyright and permission notice is retained in `shaders/coastal-water.wgsl`.

All scanned assets are from [Poly Haven](https://polyhaven.com/) and licensed CC0. See
[`tests/fixtures/external/README.md`](../../tests/fixtures/external/README.md) for pinned sources,
authors, and fixture policy.
