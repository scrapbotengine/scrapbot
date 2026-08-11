# Virtual Wilds

Virtual Wilds combines high-detail Poly Haven geometry with deliberately lightweight 1K material
images. The geometry products exercise virtual geometry, residency, batching, and culling; the 1K
textures keep the current eager RGBA8 texture path within a reasonable startup and memory budget.
Close-up material detail is therefore limited until Scrapbot supports GPU-compressed,
mip-resident high-resolution textures.

Virtual Wilds is Scrapbot's real-world virtual-geometry showcase. It builds a moving coastal route
from twelve full-detail CC0 Poly Haven models.

Install the ignored source fixtures, then launch the editor:

```sh
mise setup-assets
mise scrapbot -- run examples/virtual-wilds --editor
```

The source assets are not stored in Git. `mise setup-assets` downloads immutable,
checksum-verified files and places them under `assets/`. Scrapbot compiles them into its ordinary
versioned runtime products on first use.

Use the camera's `virtual_geometry`, `meshlets`, and `lod` debug views to inspect the selected
cluster frontier. The photogrammetry models contain 8,347,283 unique source triangles and compile
into 22,266 streamable cluster pages. The 192 MiB residency budget is intentionally smaller than that
complete detail set.

The camera tour therefore exercises visible page demand, predictive prefetch, and eviction while
coarse geometry remains available.

The route also demonstrates project-authored vertex and fragment hooks. A subdivided procedural
plane consumes Scrapbot's reusable GPU spectral-surface field: three deterministic Phillips wind
bands evolve through deep-water dispersion and batched two-axis 64×64 inverse FFTs. The 384-, 96-,
and 24-metre patches partition swell, agitation, and ripple wavelengths instead of summing three
copies of the same spectrum. Frequency-domain
horizontal orbital displacement sharpens the result into Gerstner-style crests and broader troughs.
The public helper returns world-space displacement, reconstructed normals, crest compression, and
persistent foam history,
while the example decides how those values deform and shade water.

The vertex hook combines that three-band cascade with an
eleven-octave Gerstner bank spanning 42-meter swells into fine chop. Wavelength and amplitude
decay geometrically, deep-water dispersion determines each octave's speed, shorter waves receive
progressively wider directional spreading, and one bounded steepness budget is divided across the
complete bank. A low-frequency non-periodic psrdnoise domain warp bends the swell phase so long
parallel bands do not expose the periodic simulation tile. This composition stays in the project
shader rather than moving ocean policy into the renderer.

The cascade layout follows the split-spectrum production patterns documented by
[Unity HDRP](https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition%4016.0/manual/WaterSystem-simulation.html)
and [NVIDIA](https://developer.download.nvidia.com/assets/gameworks/downloads/regular/events/cgdc15/CGDC2015_ocean_simulation_en.pdf): broad patches carry swell while progressively smaller patches
spend the same grid resolution on higher frequencies. `band_count` remains a Shader-resource quality
tier, so smaller bodies can retain only the ripple band or a broad-plus-detail pair.

The fragment hook composes guarded screen-space refraction, Beer–Lambert extinction, participating-
medium scattering, procedural-sky Fresnel reflection with sun glints, local screen-space
reflections, and whitecaps formed as narrow ridges at positive Gerstner octave peaks. Their authored
physical width is clamped to a bounded pixel footprint at extreme close range and widened only
enough to antialias at distance. Two crest-aligned breakup fields and a low-amplitude phase warp turn
each eligible medium-frequency ridge into curved, separated streaks. Higher-octave interference and
aggregate compression vary brightness without expanding those streaks into detached foam blobs.
Three anisotropic psrdnoise bands add sub-vertex ripple detail with derivative-based distance
filtering.

The spectral finalization pass now deposits foam at compressed breaking crests and exponentially
decays the retained field. Virtual Wilds uses the three retained resolutions only to control the
lifetime and opacity of resolved Gerstner crest ribbons; displaying or thresholding their 64×64
history fields directly would create periodic blobs or contour scribbles. The breakup mask
drifts slowly downwind instead of travelling at the deep-water wave phase speed. This active-breaker-to-passive-foam
transition follows the lifecycle described by [Callaghan et al.](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2012JC008147), while the generation/coverage/decay controls follow the practical simulation model documented by [Crest](https://crest.readthedocs.io/en/4.9/user/ocean-simulation.html).

The volume separates scattering and absorption coefficients, derives single-scattering albedo, and
integrates ambient sky radiance over the same optical path as background transmission. Direct sun
uses a forward Schlick phase approximation, the engine's filtered cascaded-shadow visibility, and
separate body and grazing-angle wave-tip terms. Backlit crests therefore reveal the moving surface
as a lit volume without glowing through cliffs. The water hook also traces Scrapbot's dedicated
custom-surface SSR from each displaced fragment, so nearby opaque coast geometry replaces the
fallback environment where it remains on screen. This is distinct from camera post-SSR, which
reconstructs only opaque surface origins and therefore cannot locate blended water.

Visible submerged geometry also receives wave-driven caustics. The shader reconstructs the opaque
receiver along the fragment camera ray, back-projects that point through a Snell-refracted sun ray,
and applies one inverse-map correction at the water surface. Three nearby ray projections form a
finite differential; the inverse area Jacobian then measures focused photon density rather than
sampling an unrelated scrolling caustic texture. Eleven increasingly short and widely spread wave
bands supply the light-transport normal field, extending below the geometric mesh scale to form a
connected cellular pattern. The differential grows with the receiver footprint to filter distant
cells. Water-column absorption, sun elevation, receiver angle, depth discontinuities, and cascaded
shadows attenuate the result. This screen-space receiver formulation follows the projective and
refracted-ray foundations in NVIDIA's [Rendering Water Caustics](https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-2-rendering-water-caustics).

The camera-owned underwater medium repeats that receiver-space optical model after transparent
composition, because the surface hook itself is not visible from below. Its own ten-band,
project-clock slope spectrum back-projects opaque scene-depth receivers and evaluates the refracted
mapping Jacobian without a tiled caustic texture. Directional cascade shadows, receiver orientation,
water-column extinction, pixel footprint, and an authored depth fade keep the light attached to
submerged geometry and stop it at occluders.

The engine replays the water vertex hook against the previous project-clock snapshot and retained
spectral field, then writes the previous viewport position into the custom-surface motion target.
TAA therefore follows the displaced water instead of treating every animated crest as camera-static;
paused editor redraws produce zero deformation motion.

Near shore, view-space scene depth is projected through the geometric water normal to recover a
world-like layer thickness. A cubic shallow-depth ramp aggressively removes absorption, scattering,
and refraction through a three-metre transition band, while an angle-aware Fresnel ramp preserves
the reflection of thin water only at grazing views. Rocks therefore emerge through clear water
instead of crossing a uniform blue boundary.
Shore interaction uses opaque-scene depth only as a soft envelope for contact churn; it does not
pretend to derive travelling breakers from screen depth. Two independently advected multiplicative
multifractals break up that envelope: broad foam islands are successively eroded by three finer,
rotated octaves instead of being averaged into a uniform texture. The material controls their slow
animation rate, rejects discontinuous scan silhouettes, and fades subpixel bubbles.
Foam raises surface roughness without adding emissive light. The reflection lobe also broadens with
the projected surface footprint so distant waves remain stable instead of aliasing into glossy bands.

The material uses Scrapbot's sorted transparent pass and public scene-sampling ABI. Virtual Wilds
is therefore a normal consumer of the same shader-resource and material API available to every
project, not a renderer-only water path.

A seamless grid of ocean tiles and one deep matching seabed extend far beyond the complete camera
route, leaving open water around the composed cove instead of ending near the visible coast. The
deep floor lets open water reach its dark absorption color while scanned shelves retain turquoise
shallows. Every tile samples the same world-space spectrum, so boundaries match while each tile
retains useful vertex density and culls independently.

The central water entity also owns a public `scrapbot.water_volume`. When the active camera crosses
its rendered spectral/Gerstner surface, a one-invocation GPU query evaluates the same vertex hook at
the camera and analytically clips upward rays at that displaced height. Separate RGB Beer–Lambert
absorption and scattering run after transparent water rendering but before TAA. The soft transition
replaces global air fog instead of stacking both media, while bounded two-band refraction follows
the default project clock and therefore pauses with the water simulation.

Twelve complementary CC0 scans build staggered headlands, offshore stacks, rock gardens,
shallow caustic receivers, reefs, and stranded trunks along the route. Three cliff profiles break up the
canyon silhouette. Two broad coastline scans form tidal transitions, while three coast-rock
families keep repeated formations from reading as copies.

The layered topology makes the landscape denser while giving absorption, refraction, and
intersection foam real underwater surfaces.

A project-local Luau scatter system adds 220 shared low-poly rocks using the public procedural
Geometry, Material, ECS spawn, and Transform APIs. The authored landscape generator places twelve
three-tree Poly Haven fir groves across the canyon walls. It samples upward-facing triangles from
the transformed cliff scans themselves, embeds each grove's primary root into the rendered
surface, and admits the grove only when nearby samples support both offset child trunks.

The result is 36 full, detailed firs and 356 renderables in a compact shared-batch workload. This
replaces 120 sparse saplings while reducing instantiated tree source geometry by roughly 89%.
Most instances sit outside the narrow camera corridor, making frustum and Hi-Z telemetry meaningful.

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

All scanned assets are from [Poly Haven](https://polyhaven.com/) and licensed CC0. See
[`tests/fixtures/external/README.md`](../../tests/fixtures/external/README.md) for pinned sources,
authors, and fixture policy.
