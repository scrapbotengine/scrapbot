# Resources and Registries

**Last verified:** 2026-08-12
**Persistent declarations:** `shared.Project_Resource` and `project.load_project_resources`  
**Runtime authority:** `resources.Registry`

Scrapbot resources live outside ECS. Persistent project files use stable UUIDs; ECS components store resolved generational handles into runtime registries. Project resources, transient runtime resources, built-ins, and derived backend caches have different identities and lifetimes.

Scene assets are also UUID-addressed project files, but they are not runtime resource-registry entries. `project.load_project_scenes` owns a compact catalog of UUID, name, relative source path, and dependency-first resource closure. The root runtime owns one active scene UUID/path and builds its entity payload into the ECS World. Replace transitions reuse the project registry; only the active world and one candidate world coexist, and successful activation destroys the old world immediately.

## Identity layers

| Layer | Identity | Authority | Lifetime |
| --- | --- | --- | --- |
| Project declaration | `Resource_UUID` plus a relative `resources/**/*.resource.toml` source | Project files on disk; in-memory authoring is authoritative until Save/Revert | Survives runs and editor sessions |
| Scene asset | `Resource_UUID` plus a relative `scenes/**/*.scene.toml` source | Scene catalog on disk; entity payload becomes one active ECS World | Catalog and resource closures survive the run; only active and staged candidate entity payloads are resident |
| Imported product | Parent resource UUID plus common product format and versioned importer schema | Asset source/dependencies and importer settings under `.scrapbot/imported/` | Regenerated before runtime bootstrap; packaged with host builds |
| Runtime registry entry | `{index, generation}` handle plus per-entry `version` | `resources.Registry` | One engine runtime; slots may survive reload while generations invalidate dead handles |
| ECS reference | Geometry or Material handle | Active ECS world | Entity/component lifetime; resolved again when a world is rebuilt |
| Backend cache | Handle/generation/version keyed records | Renderer backend | Renderer lifetime; refreshed from exact resource versions/topology changes |
| Font atlas product | Project font name and generated MTSDF files | Project config/source font plus `.scrapbot/cache/fonts` build products | Regenerated product; runtime Font handle is not persistent identity |

## Persistent project resource kinds

<!-- inventory:project-resource-kinds:start -->
| Source kind | TOML `type` | Runtime family | ECS reference | Editor persistence |
| --- | --- | --- | --- | --- |
| `Texture` | `scrapbot.texture` | Texture | Material Texture handle | Incrementally imported and inspectable; source/settings remain text-authored |
| `Model` | `scrapbot.model` | Model bundle plus generated Geometry/Material entries and an authored submission preference | `scrapbot.model` root reconciles derived ECS children | Incrementally imported and inspectable; source remains text-authored |
| `Environment` | `scrapbot.environment` | Environment | `scrapbot.world_environment` references lighting/background UUIDs | Incrementally imported and inspectable; source/settings remain text-authored |
| `Icon_Set` | `scrapbot.icon_set` | Icon Set | `scrapbot.ui_icon` and icon-bearing controls reference set UUID plus symbol | Incrementally imported and inspectable; source directory remains text-authored |
| `Shader` | `scrapbot.shader` | Shader | Material references the Shader UUID | Text-authored WGSL hooks; loaded and versioned with project resources |
| `Material` | `scrapbot.material` | Material | `scrapbot.material` | Create, duplicate, rename/move, edit, delete, Undo/Redo, Save/Revert |
| `Geometry_LOD` | `scrapbot.geometry_lod` | Geometry plus internal LOD Geometry entries | `scrapbot.geometry` | Loaded/hot-reloaded and referenceable; full inline authoring is not yet symmetric with materials |
| `UI_Theme` | `scrapbot.ui_theme` | UI Theme | Scene/Luau/native/editor composition resolves UUID plus recipes into ordinary `scrapbot.ui_*` values | Text-authored; listed and inspected read-only |
<!-- inventory:project-resource-kinds:end -->

The recursive project loader rejects duplicate UUIDs. Scene validation resolves Material, Model, authored Geometry, World Environment, and UI icon-set UUID references; materials validate Texture and Shader UUIDs. Resource file paths are relative to `resources/`; Shader sources are safe paths under `shaders/`, while Texture, Model, Environment, and Icon Set import sources are safe paths under `assets/`.

## Scene residency

- `project.scene_resource_closure` extracts direct scene references and recursively orders Material dependencies before the Material. Duplicate references collapse to one UUID.
- `Resource_Residency` owns cloned project declarations, always-resident project-config environments, active/staging closures, delayed evictions, and its frame counter. Scene metadata owns closures; the registry owns admitted payloads.
- Startup admits only the active closure. Transition staging admits destination-only resources before candidate World resolution. Activation changes closure ownership atomically; failure leaves active ownership unchanged.
- Old-only resources receive a three-frame grace period. A new active or staging reference cancels eviction. Stable frames inspect only the bounded pending-eviction list; they do not rescan declarations or registry capacity.
- Retirement releases family payloads, cascades a Model retirement through its generated Geometry/Material entries, increments generations, and preserves authored UUID slots for later reuse. Project fonts, built-ins, and transient script-created resources are outside scene residency.
- Project-wide render/background Environment UUIDs remain resident independently of scene references. Current admission is synchronous and has no explicit byte budget; those are tracked extensions to this owner, not competing lifecycle paths.
- Source/tests: `project/resources.odin`, `project/scenes.odin`, `resource_residency.odin`, `resources/residency.odin`; `project/resource_closure_test.odin`, `resource_residency_test.odin`, `scene_transition_test.odin`.

## Runtime registry families

<!-- inventory:runtime-resource-families:start -->
| Family | Persistent identity | Runtime identity/versioning | Primary consumers |
| --- | --- | --- | --- |
| `Geometry` | Optional UUID/source when authored; name for transient/built-in registration | `Geometry_Handle`, generation, entry version, registry-wide geometry topology revision | Render-instance extraction, bounds/picking, LOD selection, GPU geometry and draw caches |
| `Texture` | UUID/source when authored | `Texture_Handle`, generation, entry version | Material registry and shared WGPU texture cache |
| `Environment` | UUID/source when authored | `Environment_Handle`, generation, entry version, registry-wide environment revision | Global WGPU IBL binding and isolated material/model previews |
| `Icon_Set` | UUID/source directory when authored; reserved UUID for the embedded catalog | `Icon_Set_Handle`, generation, entry version, registry-wide icon-set revision | UI icon resolution, MTSDF atlas layers, standalone icons and icon-bearing controls |
| `Model` | UUID/source when authored | `Model_Handle`, generation, entry version | Model-root reconciliation into derived node/primitive ECS entities |
| `Material` | Optional UUID/source when authored; name for transient/built-in registration | `Material_Handle`, generation, entry version | Render-instance extraction, material/texture GPU cache, world shading and bloom |
| `Shader` | UUID/source when authored | `Shader_Handle`, generation, entry version, registry-wide shader revision | WGPU custom-material pipeline cache |
| `Font` | Project-config font name/source; generated atlas is derived | `Font_Handle`, generation, entry version | UI measurement, glyph lookup, MTSDF atlas upload and UI rendering |
| `UI_Theme` | UUID/source when authored | `UI_Theme_Handle`, generation, entry version, registry-wide UI-theme revision | Scene parsing, Luau/native recipe resolution, editor resource inspection; never layout or paint |
<!-- inventory:runtime-resource-families:end -->

## Registration contracts

### Geometry

- Built-in/transient geometry registers by unique name and may be replaced in place only when it is not authored.
- Authored `Geometry_LOD` declarations register by UUID and name. The base entry owns authored identity; additional LOD entries use internal names and handles.
- Content replacement increments the entry version. LOD membership, addition, disappearance, or other batch-shape changes also increment `geometry_topology_revision`.
- Registration builds deterministic meshoptimizer meshlets plus a crack-aware cluster-LOD hierarchy when no compiled hierarchy is supplied. Imported catalogs derive compatibility meshlets from the hierarchy's exact leaves without decoding canonical geometry. Both use at most 64 vertices and 124 triangles per cluster.
- Geometry owns local vertex/triangle streams, conservative spheres, normal cones, hierarchy groups, monotonic simplification errors, refined-group links, deterministic group-aligned page identities, maximum depth, and canonical source counts. Hierarchy construction locks source boundary loops by canonical position so simplification cannot enlarge open regions.
- Every page has one self-contained canonical-vertex subset and page-local expanded index stream. Imported Geometry owns validated ranges in its immutable Model product plus a position-only query proxy. Model v21 keeps every terminal refinement-DAG frontier page pinned, including regions that stop before the hierarchy's global maximum depth. It stores those pages and a bounded evictable bootstrap tail in the coarse chunk; later refinements remain independently addressable in the detail chunk.
- Each imported base primitive retains a validated quantized distance-field descriptor whose samples remain in their independent chunk until requested. Runtime registration clones the descriptor onto Geometry; generated LOD entries do not duplicate it. Cache-hit loading does not decode complete render vertices, source indices, or distance samples.
- WGPU is the only current field consumer. Its per-Geometry packed buffer feeds both the local slice diagnostic and the debug-requested three-cascade world composition; the Registry neither owns clipmap state nor observes camera movement.
- Other producers own equivalent in-memory bytes and retain their canonical arrays because they have no persistent fallback product. Clone, replacement, generated-LOD registration, retirement, and destruction move or release the proxy, source contract, and distance-field descriptor with the Geometry entry.
- A transient Luau voxel surface additionally retains its finite density lattice, origin, voxel size,
  cell dimensions, and source lineage in the Geometry entry. Direct editor cell edits mutate a
  bounded sample set, replace the Geometry in place with a new resource version, and retain an owned
  reversible sample delta tied to that lineage. Registry clone and teardown copy or release that
  source with the Geometry. This is session authority only; it is not the persistent Terrain source
  described by ADR-062.
- Exact CPU queries iterate leaf-cluster topology and resolve canonical IDs through either resident vertices or the position proxy. Leaves may terminate above maximum hierarchy depth. Backend fallback reconstructs an owned temporary canonical view from every leaf-containing page, while memory-backed Geometry returns a borrowed view. Consumers release owned views after use.
- Page construction occurs only at import or explicit registration/replacement boundaries. Stable frames do no partitioning, simplification, payload construction, or cluster work.
- Missing authored declarations mark prior entries dead, increment generation/version, and invalidate old handles without compacting registry indexes.
- Render preparation and the WGPU backend consume exact handle/version/topology changes; stable geometry is neither re-extracted nor re-uploaded.
- The retained renderer resolves submission preference at topology boundaries in entity, Model asset, then project order. Automatic mode selects virtual submission only for capable, hierarchy-bearing Geometry at or above the stable source-triangle crossover. Camera movement never changes the chosen path.
- WGPU uploads ordinary Geometry versions into shared aligned vertex and index arena ranges. Streamed Virtual Geometry allocates only resident page-local vertex and index ranges and retains no complete canonical GPU allocation. Distance-field storage is a separate lazy, geometry-versioned cache: no GPU buffer exists until a consumer requests the field, and invalidation releases it with the Geometry cache entry.
- Complete resources that fit the remaining budget retain canonical vertex/index ranges plus expanded page indices as a nonduplicating fast path. Larger resources pin the coarsest frontier. Bounded GPU feedback reports prioritized visible demand, future-camera prefetch, and visible resident-group touches.
- Imported refinement payloads are read from exact product ranges by a dedicated worker. Versioned completions reach the render thread without waiting, then admit or evict complete groups under per-frame byte/group limits and the combined vertex/index project budget. Demand precedes speculative work, may reclaim prefetched groups immediately, and promotes them on visible use; speculative requests cannot evict recently visible groups.
- Native multi-draw submits retained per-cluster indexed commands. Other capable adapters compact instance/cluster records into bounded shared spans and vertex-pull from the arenas. Portable shadows use classic canonical indices for complete resources and page-local compact records for streamed resources. Adapters without indirect-first-instance and capacity-limited layouts retain whole-primitive indexed-indirect submission.
- Source hierarchy clusters continue to reference canonical vertex IDs. Hierarchy leaf topology is runtime authority because construction may sanitize degenerate source triangles. The C++ bridge in `native/clusterlod/` owns no runtime data after registration; it adapts the pinned meshoptimizer builder into allocator-owned Odin slices.
- Source/tests: `geometry/hierarchy.odin`, `resources/geometry_pages.odin`, `resources/resources.odin`, `resources/models.odin`, `render/wgpu_page_io.odin`, `render/wgpu_visibility.odin`, `render/wgpu_distance_field.odin`; `asset_import/models_test.odin`, `resources/models_test.odin`, `resources/resources_test.odin`, `render/render_test.odin`.

### Material

- Built-in/transient materials register by unique name and cannot replace an authored material with the same name.
- Authored materials register by UUID, name, and source path. Reload updates an existing UUID in place, preserving its slot/generation while incrementing version.
- Deletion/disappearance marks the entry dead and increments generation/version. Reappearance by UUID reuses its registry slot through the authored registration path.
- Editor history stores deep `Project_Material_Snapshot` values. Save derives create/write/delete files from the disk baseline and dirty UUID candidates.
- Base color, metallic/roughness factors, normal/occlusion strengths, HDR emissive value, or any material image change increments version; backend material/texture caches update only affected entries.
- Source/tests: `resources/resources.odin`, `ui/editor_resource_authoring.odin`, `project_save.odin`; `resources/resources_test.odin`, `project_save_test.odin`.

### Shader

- A `scrapbot.shader` resource owns one safe project-relative `shaders/*.wgsl` source and a fixed cull-mode policy.
- Project source supplies `scrapbot_vertex` and `scrapbot_fragment` hooks. WGPU owns camera,
  instance, material, scene sampling, timing, blending, and previous-frame contracts. The fragment ABI
  includes bounded custom-surface SSR against opaque scene depth, returning confidence for
  environment fallback. WGPU replays the vertex hook with the previous project-time context and
  prior spectral field to publish custom-surface motion for TAA. A Water Volume sharing the
  material can also invoke the canonical vertex hook through a one-thread compute pipeline; this
  produces the displaced camera-surface height without a second project wave implementation.
- An optional typed spectral-surface description owns one-to-three frequency-partitioned patch
  bands, wind speed/direction, amplitude,
  small-wave damping, and bounded choppiness. WGPU derives one shader-versioned GPU
  current and previous displacement/normal/crest fields from it. The project never owns backend
  bindings or compute pipelines.
- Materials reference Shader UUIDs and four `Vec4` parameter slots. A changed Shader version invalidates only its cached module, render pipeline, and water-height query pipeline.
- Blended custom materials render after opaque world shading, test existing depth without writing it, sample a retained opaque-color copy, and sort material batches back to front. Exact per-instance sorting remains tracked work.
- Custom shaders currently require blended materials. Matching displaced opaque depth-prepass and shadow variants remain tracked work.
- Source/tests: `resources/shaders.odin`, `render/wgpu_custom_shader.odin`, `project/parse.odin`; project/resource parser tests, spectral shader-contract tests, and WGPU framegrabs.

### Font

### Texture, Model, Environment, and Icon Set imports

- `asset_import.ensure_project_imports` fingerprints source/dependency bytes plus an importer schema and writes products atomically under `.scrapbot/imported/`.
- The common asset-product envelope owns format identity, product kind, and a bounded directory of typed, indexed, non-overlapping chunks. Importer schemas own chunk contents.
- The reusable sequential writer reserves and patches the chunk directory while payloads stream to disk. It synchronizes the completed file before atomic installation.
- Model products separate material images, pinned resident pages, evictable detail pages, quantized distance fields, and the catalog.
- Terminal group error identifies mandatory fallback roots. Hierarchy construction extends them with a 1/32 payload target, 256 KiB minimum, and 2 MiB maximum of reachable error-prioritized refinements.
- Import streams resident pages and signed 16-bit distance samples directly. It spools detail pages temporarily, copies them with a fixed buffer, and emits the catalog one primitive at a time.
- The importer bakes one shared `KHR_texture_transform` per material into UV0. The reader validates page and field ranges against their expected chunks before publication; the field loader performs bounded positional reads only on demand.
- Texture products contain validated RGBA8 mip chains.
- Icon Set products contain a deterministic linear RGBA8 MTSDF atlas plus symbolic names and normalized UV rectangles. The importer fingerprints every recursively discovered SVG, normalizes supported monochrome geometry through the pinned compiler, and atomically retains the last valid atlas on failure.
- Environment products contain:
  - the source-resolution 2:1 Radiance HDR panorama in linear RGBA16F;
  - a diffuse irradiance cube;
  - a roughness-prefiltered specular cube.
- Environment import wraps bilinear panorama lookup across the equirectangular seam. Deterministic 256-sample GGX integration prevents structured noise on close glossy surfaces.
- Model products contain static triangles, compiled cluster hierarchies and page tables, optional authored tangent frames, TRS nodes, metallic-roughness factors, alpha/culling state, and decoded PBR image mip chains. Sources may be GLB buffer views, data URIs, or safe external relative files parsed through pinned `cgltf`.
- Eligible model primitives also contain zero to three importer-built LOD payloads. Each level owns compact vertices/indices, its projected threshold, and measured simplification error. The import fingerprint includes normalized LOD settings.
- Model compilation walks only the selected glTF scene closure and remaps its reachable node, mesh, and material references into a compact product. Nodes, meshes, primitives, and materials carry semantic keys; generated Geometry/Material names and derived model-instance ECS UUIDs are keyed from those values rather than glTF array positions. Reordering source arrays therefore reuses live handles, while removed semantic outputs are retired normally.
- Every glTF image contributes to the model source fingerprint. Generated Material entries own cloned image payloads with explicit sRGB or linear color-space meaning and per-slot min/mag/mipmap/wrap sampler policy. The WGPU material cache uploads only a changed Material version, owns its generated texture/view/sampler set and factor/alpha uniform, and releases that complete set together. Batch rendering selects cached opaque/masked and single/double-sided pipeline variants; masked depth and shadow passes bind the same generated base-color texture and cutoff as world rendering.
- Texture, Model, Environment, and Icon Set declarations retain UUID-backed handles and entry versions.
- The singleton `scrapbot.world_environment` owns lighting selection, independent diffuse/specular environment strength, visible-background presentation, and procedural-atmosphere art direction. The fixed environment phase resolves UUIDs and copies bounded sky/ground/haze/sun values into a retained registry cache.
- A handle, version, or presentation change bumps one environment revision consumed by WGPU. A visible empty background reuses imported lighting, or selects the procedural atmosphere when both UUIDs are empty.
- Active-camera exposure remains a separate multiplier. Backend-neutral extraction derives an above-horizon sun into the first directional-light slot without mutating ECS light entities.
- Imported backgrounds use the panorama at zero blur and the prefiltered cube for intentional blur. Imported lighting uses compact irradiance/specular cubes.
- Imported models publish ordinary Geometry and Material handles for every primitive. Generated levels use the primitive semantic key plus level number, survive harmless source reordering and reimport in place, and attach through `set_geometry_lods`.
- Removed imported levels are retired with the Model's other generated subresources. Every surviving level registers its validated product hierarchy into an ordinary Geometry resource; non-imported producers use the same runtime hierarchy contract.
- Editor Reimport addresses one authored UUID, forces only that Texture, Model, Environment, or Icon Set importer, updates the existing registry slot, and then reconciles model instances when relevant. Reimport All uses the same path for every imported declaration; neither action reloads Luau or native Odin.
- A replaced or removed Model retires generated Geometry and Material outputs absent from the replacement by marking their slots dead and incrementing generation/version. Stable/reused products retain their handles.
- Texture, Model, and Material inspection target the public `scrapbot.ui_viewport` component at the resource UUID. WGPU resolves the UUID by registry family, assigns an independently sized pooled target, and renders either an aspect-preserving Texture pass or an isolated Model/Material preview scene with its own camera, lighting, environment, and renderer-owned presentation geometry. Icon Set inspection reads its symbol count, atlas shape, dependency, product size, and import state from the ordinary registry/import records. Stable viewport targets cache by component, target size/aspect, exact resource version, and relevant registry revisions. Import state, dependency path, product type/size, and the last explicit failure remain editor presentation over registry/import state rather than new resource authority.
- `scrapbot.model` roots reconcile a derived runtime hierarchy during resource/bootstrap reload work and after an explicit model-root structural revision. Structural reconciliation validates deterministic derived UUIDs and rebuilds only incomplete roots, so duplicating or restoring one root preserves every unaffected derived entity generation and renderer slot. A Model-registry revision deliberately rebuilds all roots because generated topology may have changed. Generated primitives inherit the resolved entity/asset/project geometry mode plus the root's `scrapbot.shadow_caster` and `scrapbot.shadow_receiver` membership. Stable ordinary frames only compare revision counters and consume the resulting standard Transform/Geometry/Material/shadow-marker entities without model scans.
- Source/tests: `asset_import/imports.odin`, `asset_import/icons.odin`, `asset_import/environments.odin`, `asset_import/models.odin`, `asset_import/model_lods.odin`, `geometry/hierarchy.odin`, `resources/textures.odin`, `resources/icons.odin`, `resources/models.odin`, `scrapbot.odin`; importer, icon compiler, registry, environment-filtering, model-instance, and WGPU tests.

### Font

- Project config names source fonts. `prepare_project_fonts` builds fixed-size MTSDF atlas/metadata products under `.scrapbot/cache/fonts`.
- Runtime registration validates atlas dimensions, complete supported glyph coverage, ascender, and RGBA8 byte count.
- Re-registering a font name replaces atlas pixels in place and increments entry version; the handle generation remains stable while alive.
- UI retains font-dependent measurement/paint state; changed font resources invalidate their atlas/cache consumers rather than unrelated ECS membership.
- Inter remains the baked fallback when a project font is absent or unavailable.
- Source/tests: `project/fonts.odin`, `resources/resources.odin`, `ui/font_data.odin`; `project/project_test.odin`, `resources/resources_test.odin`, `ui/ui_test.odin`.

### UI Theme

- A `scrapbot.ui_theme` declaration explicitly names the `reduced_dark` built-in baseline, then overrides any semantic palette, metric, or typography token.
- RGB palette channels are finite non-negative HDR values. Alpha remains between zero and one. Metrics are finite and non-negative; text and container heights are positive. The font is embedded Inter or a project-config font.
- Reload updates a surviving UUID in place and increments its entry version and registry revision. Removal marks the entry dead and increments generation/version without compacting slots.
- Scene parsing validates UUIDs against loaded declarations and resolves recipes before explicit component sections. Luau and native callbacks resolve against the runtime registry. Existing entities retain their already-resolved component values.
- The UI-theme revision refreshes editor resource presentation only. Renderer, retained UI, layout, and paint code have no theme lookup, dependency, or stable-frame work.
- Source/tests: `shared/ui_theme.odin`, `project/parse.odin`, `resources/themes.odin`, `script/ui_theme.odin`, `native/ui.odin`; `project/project_test.odin`, `resources/resources_test.odin`, `script/ui_components_test.odin`, `native/ui_test.odin`.

## Resolution and invalidation

```text
project resource UUID/name
          │ parse + validation
          ▼
resources.Registry slot ── {index, generation} ──> ECS component
          │ version/topology revision                    │ exact entity dirtiness
          └──────────────────────────────┬───────────────┘
                                         ▼
                             retained render/UI consumer
                                         │ dirty cache entry
                                         ▼
                                   backend GPU cache
```

- A handle is valid only when its index is in range, the slot is alive, and generations match.
- Entry `version` means content at a still-valid identity changed.
- `geometry_topology_revision` means geometry/LOD batch shape may have changed globally.
- Authored UUIDs never become runtime storage indexes in persistent files.
- Resource disappearance must invalidate exact ECS/backend consumers; registry arrays are not compacted merely to remove dead entries.

## Persistence and playback

- **Save** serializes only dirty authored resource UUIDs, validates resulting scene references, and commits scene/resource file changes through one recoverable project transaction.
- **Revert** reloads project resource declarations from disk, updates/deactivates runtime entries, then rebuilds the scene world and rebinds the existing script runtime.
- **Play** captures authored Material base color, emissive, metallic, and roughness values in the in-memory playback baseline alongside authored scene entities.
- **Stop** restores those captured surface values by UUID and increments a material version only when restored content differs. It does not reread resource files or reload Luau/native code.
- **Explicit Reimport** forces one UUID (or all imported resources), mutates live registry entries, retires stale generated model outputs, and reconciles Model roots without reloading the world, Luau, or native extensions.
- **Hot reload** ensures imports and re-registers fonts, textures, environments, icon sets, models, shaders, materials, LOD geometry, and UI themes before replacing the world/runtime. Scene replacement and script re-execution explicitly recompose theme consumers. Failed project/world reload keeps or restores the last-good runtime path. Its current aggregate asset stamp remains intentionally coarser than explicit Reimport until platform file watching lands.

See [Lifecycle matrix](lifecycle.md), [State ownership](state-ownership.md), [FDR-009](../fdr/FDR-009-project-resources.md), and [ADR-030](../adr/ADR-030-identify-project-resources-by-uuid-outside-the-ecs.md).
