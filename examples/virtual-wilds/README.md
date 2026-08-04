# Virtual Wilds

Virtual Wilds is Scrapbot's real-world virtual-geometry showcase. It builds a moving coastal route
from six full-detail CC0 Poly Haven models plus six lightweight CC0 Kenney forest models.

Install the ignored source fixtures, then launch the editor:

```sh
mise setup-assets
mise scrapbot -- run examples/virtual-wilds --editor
```

The source assets are not stored in Git. `mise setup-assets` downloads immutable,
checksum-verified files and places them under `assets/`. Scrapbot compiles them into its ordinary
versioned runtime products on first use.

Use the camera's `virtual_geometry`, `meshlets`, and `lod` debug views to inspect the selected
cluster frontier. The photogrammetry models contain 3,536,980 source triangles and compile into
9,435 streamable cluster pages. The 192 MiB residency budget is intentionally smaller than that
complete detail set.

The camera tour therefore exercises visible page demand, predictive prefetch, and eviction while
coarse geometry remains available.

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
and narrow analytic Gerstner crest lips. Wind-advected foam packets break those lips into trailing
filaments and distance-filtered microbubbles instead of painting a broad static mask over the
surface. Three anisotropic psrdnoise bands add sub-vertex ripple detail with derivative-based
distance filtering.
Shore interaction projects opaque-scene depth onto the water normal, rejects exact zero-depth
silhouettes, and shapes a broad noise-broken wash envelope instead of outlining every submerged
photogrammetry edge.

The material uses Scrapbot's sorted transparent pass and public scene-sampling ABI. Virtual Wilds
is therefore a normal consumer of the same shader-resource and material API available to every
project, not a renderer-only water path.

A seamless grid of ocean tiles and one deep matching seabed extend far beyond the complete camera
route, leaving open water around the composed cove instead of ending near the visible coast. The
deep floor lets open water reach its dark absorption color while scanned shelves retain turquoise
shallows. Every tile samples the same world-space spectrum, so boundaries match while each tile
retains useful vertex density and culls independently.

Reused CC0 scans build staggered headlands, offshore stacks, rock gardens, submerged shelves,
reefs, and stranded trunks along the route. The layered silhouettes make the
landscape denser while giving absorption, refraction, and intersection foam real underwater
topology.

A project-local Luau scatter system adds 220 shared low-poly rocks using the public procedural
Geometry, Material, ECS spawn, and Transform APIs. The authored landscape generator stages five
three-tree Poly Haven hero groves near the route, then deploys 560 tiny Kenney pine models as distant
canopy belts. The result is 575 trees and 1,425 renderables while retaining a compact shared-batch
workload. Most instances sit outside the narrow camera corridor, making frustum and Hi-Z telemetry
meaningful.

The ordinary public `scrapbot.volumetric_fog` component adds shadowed blue-gray coastal haze. A
low sun cuts across the flooded canyon.

The same scene consumes Scrapbot's public composable post stack: a restrained vignette frames the canyon, screen-space ghost flares react to visible HDR highlights, and deterministic procedural lens dirt catches only bloom/flare energy. None of these effects is hard-coded into the example.

Three clustered point lights create cold and amber mist pockets around the rock gates.

The camera tour crosses opposing cliff walls, a tidal causeway, sea stacks, submerged reefs, distant headlands, and oversized wreckage silhouettes. Creatively stretched walls rise several times higher than the source scan without increasing the heavy scan's instance count.

The scene's complexity demonstrates virtualized geometry alongside ordinary shared-resource
instancing. Its low fog layer and forward-scattering response soften the distant route and catch
the warm sun without obscuring the photogrammetry.

The water shader adapts Stefan Gustavson and Ian McEwan's
[`psrdnoise2.wgsl`](https://github.com/stegu/psrdnoise) at commit
`419175a270862ce7ae692038fafafb42ec0427e9`. psrdnoise is distributed under the MIT License; the
required copyright and permission notice is retained in `shaders/coastal-water.wgsl`.

All scanned assets are from [Poly Haven](https://polyhaven.com/) and licensed CC0. The distant
forest uses [Kenney's Nature Kit](https://kenney.nl/assets/nature-kit), also licensed CC0. See
[`tests/fixtures/external/README.md`](../../tests/fixtures/external/README.md) for pinned sources,
authors, and fixture policy.
