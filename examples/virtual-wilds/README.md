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
plane consumes Scrapbot's reusable GPU spectral-surface field: a deterministic Phillips wind
spectrum evolves through deep-water dispersion and a two-pass 64×64 inverse FFT. The public helper
returns world-space height and slopes, while the example decides how those values deform water.

The fragment hook composes guarded screen-space refraction, Beer–Lambert absorption and scattering,
environment Fresnel reflection, and narrow depth-intersection and crest foam. psrdnoise supplies
only the smaller derivative-driven ripples and breakup, so the broad ocean motion no longer comes
from a short repeating list of authored sine waves.

The material uses Scrapbot's sorted transparent pass and public scene-sampling ABI. Virtual Wilds
is therefore a normal consumer of the same shader-resource and material API available to every
project, not a renderer-only water path.

A broad authored seabed closes the complete camera route beneath the water. Reused instances of
the Coastal Rocks scan form submerged shelves at several depths, giving absorption, refraction,
and intersection foam real underwater topology instead of exposing the renderer's empty clear
color through the surface.

The ordinary public `scrapbot.volumetric_fog` component adds restrained blue-gray coastal haze.
Its low layer and forward-scattering response soften the distant route and catch the warm sun
without obscuring the photogrammetry.

The water shader adapts Stefan Gustavson and Ian McEwan's
[`psrdnoise2.wgsl`](https://github.com/stegu/psrdnoise) at commit
`419175a270862ce7ae692038fafafb42ec0427e9`. psrdnoise is distributed under the MIT License; the
required copyright and permission notice is retained in `shaders/coastal-water.wgsl`.

All scanned assets are from [Poly Haven](https://polyhaven.com/) and licensed CC0. See
[`tests/fixtures/external/README.md`](../../tests/fixtures/external/README.md) for pinned sources,
authors, and fixture policy.
