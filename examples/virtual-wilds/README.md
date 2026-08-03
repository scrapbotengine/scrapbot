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
spectrum evolves through deep-water dispersion and a two-axis 64×64 inverse FFT. Frequency-domain
horizontal orbital displacement sharpens the result into Gerstner-style crests and broader troughs.
The public helper returns world-space displacement, reconstructed normals, and crest compression,
while the example decides how those values deform and shade water.

The vertex hook reserves a 384-meter FFT patch for broad energy, then combines it with four
world-continuous Gerstner bands. A low-frequency non-periodic psrdnoise domain warp bends the swell
phase so long parallel bands do not expose the periodic simulation tile. This composition stays in
the project shader rather than moving ocean policy into the renderer.

The fragment hook composes guarded screen-space refraction, Beer–Lambert absorption and scattering,
procedural-sky Fresnel reflection with sun glints, and whitecaps driven jointly by FFT compression
and analytic Gerstner crest phase. Three
anisotropic psrdnoise bands add sub-vertex ripple detail with derivative-based distance filtering.
Shore interaction projects opaque-scene depth onto the water normal, then uses separately broken
leading and trailing wash bands instead of tracing every intersecting triangle with a uniform white
outline.

The material uses Scrapbot's sorted transparent pass and public scene-sampling ABI. Virtual Wilds
is therefore a normal consumer of the same shader-resource and material API available to every
project, not a renderer-only water path.

A seamless grid of ocean tiles and one deep matching seabed extend far beyond the complete camera
route, leaving open water around the composed cove instead of ending near the visible coast. The
deep floor lets open water reach its dark absorption color while scanned shelves retain turquoise
shallows. Every tile samples the same world-space spectrum, so boundaries match while each tile
retains useful vertex density and culls independently.

Reused CC0 scans build staggered headlands, offshore stacks, rock gardens, submerged shelves,
reefs, and stranded trunks along the route. The layered silhouettes make the landscape denser while
giving absorption, refraction, and intersection foam real underwater topology.

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
