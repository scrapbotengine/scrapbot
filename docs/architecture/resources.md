# Resources and Registries

**Last verified:** 2026-07-21
**Persistent declarations:** `shared.Project_Resource` and `project.load_project_resources`  
**Runtime authority:** `resources.Registry`

Scrapbot resources live outside ECS. Persistent project files use stable UUIDs; ECS components store resolved generational handles into runtime registries. Project resources, transient runtime resources, built-ins, and derived backend caches have different identities and lifetimes.

## Identity layers

| Layer | Identity | Authority | Lifetime |
| --- | --- | --- | --- |
| Project declaration | `Resource_UUID` plus a relative `resources/**/*.resource.toml` source | Project files on disk; in-memory authoring is authoritative until Save/Revert | Survives runs and editor sessions |
| Imported product | Parent resource UUID plus versioned artifact schema | Asset source/dependencies and importer settings under `.scrapbot/imported/` | Regenerated before runtime bootstrap; packaged with host builds |
| Runtime registry entry | `{index, generation}` handle plus per-entry `version` | `resources.Registry` | One engine runtime; slots may survive reload while generations invalidate dead handles |
| ECS reference | Geometry or Material handle | Active ECS world | Entity/component lifetime; resolved again when a world is rebuilt |
| Backend cache | Handle/generation/version keyed records | Renderer backend | Renderer lifetime; refreshed from exact resource versions/topology changes |
| Font atlas product | Project font name and generated MTSDF files | Project config/source font plus `.scrapbot/cache/fonts` build products | Regenerated product; runtime Font handle is not persistent identity |

## Persistent project resource kinds

<!-- inventory:project-resource-kinds:start -->
| Source kind | TOML `type` | Runtime family | ECS reference | Editor persistence |
| --- | --- | --- | --- | --- |
| `Texture` | `scrapbot.texture` | Texture | Material Texture handle | Incrementally imported and inspectable; source/settings remain text-authored |
| `Model` | `scrapbot.model` | Model bundle plus generated Geometry/Material entries | `scrapbot.model` root reconciles derived ECS children | Incrementally imported and inspectable; source remains text-authored |
| `Material` | `scrapbot.material` | Material | `scrapbot.material` | Create, duplicate, rename/move, edit, delete, Undo/Redo, Save/Revert |
| `Geometry_LOD` | `scrapbot.geometry_lod` | Geometry plus internal LOD Geometry entries | `scrapbot.geometry` | Loaded/hot-reloaded and referenceable; full inline authoring is not yet symmetric with materials |
<!-- inventory:project-resource-kinds:end -->

The recursive project loader rejects duplicate UUIDs. Scene validation resolves Material, Model, and authored Geometry UUID references; materials validate Texture UUIDs. Resource file paths are relative to `resources/`; Texture and Model import sources are safe paths under `assets/`.

## Runtime registry families

<!-- inventory:runtime-resource-families:start -->
| Family | Persistent identity | Runtime identity/versioning | Primary consumers |
| --- | --- | --- | --- |
| `Geometry` | Optional UUID/source when authored; name for transient/built-in registration | `Geometry_Handle`, generation, entry version, registry-wide geometry topology revision | Render-instance extraction, bounds/picking, LOD selection, GPU geometry and draw caches |
| `Texture` | UUID/source when authored | `Texture_Handle`, generation, entry version | Material registry and shared WGPU texture cache |
| `Model` | UUID/source when authored | `Model_Handle`, generation, entry version | Model-root reconciliation into derived node/primitive ECS entities |
| `Material` | Optional UUID/source when authored; name for transient/built-in registration | `Material_Handle`, generation, entry version | Render-instance extraction, material/texture GPU cache, world shading and bloom |
| `Font` | Project-config font name/source; generated atlas is derived | `Font_Handle`, generation, entry version | UI measurement, glyph lookup, MTSDF atlas upload and UI rendering |
<!-- inventory:runtime-resource-families:end -->

## Registration contracts

### Geometry

- Built-in/transient geometry registers by unique name and may be replaced in place only when it is not authored.
- Authored `Geometry_LOD` declarations register by UUID and name. The base entry owns authored identity; additional LOD entries use internal names and handles.
- Content replacement increments the entry version. LOD membership, addition, disappearance, or other batch-shape changes also increment `geometry_topology_revision`.
- Missing authored declarations mark prior entries dead, increment generation/version, and invalidate old handles without compacting registry indexes.
- Render preparation and the WGPU backend consume exact handle/version/topology changes; stable geometry is neither re-extracted nor re-uploaded.
- Source/tests: `resources/resources.odin`; `resources/resources_test.odin`, `render/render_test.odin`.

### Material

- Built-in/transient materials register by unique name and cannot replace an authored material with the same name.
- Authored materials register by UUID, name, and source path. Reload updates an existing UUID in place, preserving its slot/generation while incrementing version.
- Deletion/disappearance marks the entry dead and increments generation/version. Reappearance by UUID reuses its registry slot through the authored registration path.
- Editor history stores deep `Project_Material_Snapshot` values. Save derives create/write/delete files from the disk baseline and dirty UUID candidates.
- Base color, HDR emissive value, or texture changes increment version; backend material/texture caches update only affected entries.
- Source/tests: `resources/resources.odin`, `ui/editor_resource_authoring.odin`, `project_save.odin`; `resources/resources_test.odin`, `project_save_test.odin`.

### Font

### Texture and Model imports

- `asset_import.ensure_project_imports` fingerprints source/dependency bytes plus an importer schema and writes products atomically under `.scrapbot/imported/`.
- Texture products contain validated RGBA8 mip chains. Model products contain static triangle vertices/indices, TRS nodes, and material factors decoded through pinned `cgltf`.
- Texture and Model declarations retain UUID-backed registry handles and entry versions. Imported model registration publishes ordinary Geometry and Material handles for every primitive.
- Editor Reimport addresses one authored UUID, forces only that importer, updates the existing registry slot, and then reconciles model instances. Reimport All uses the same path for every imported declaration; neither action reloads Luau or native Odin.
- A replaced or removed Model retires generated Geometry and Material outputs absent from the replacement by marking their slots dead and incrementing generation/version. Stable/reused products retain their handles.
- Texture, Model, and Material inspection target the public `scrapbot.ui_viewport` component at the resource UUID. WGPU resolves the UUID by registry family, assigns an independently sized pooled target, and renders either an aspect-preserving Texture pass or an isolated Model/Material preview scene with its own camera, lighting, environment, and renderer-owned presentation geometry. Stable targets cache by component, target size/aspect, exact resource version, and relevant registry revisions. Import state, dependency path, product type/size, and the last explicit failure remain editor presentation over registry/import state rather than new resource authority.
- `scrapbot.model` roots reconcile a derived runtime hierarchy during resource/bootstrap reload work and after an explicit model-root structural revision. Stable ordinary frames only compare revision counters and consume the resulting standard Transform/Geometry/Material entities without model scans.
- Source/tests: `asset_import/imports.odin`, `asset_import/models.odin`, `resources/textures.odin`, `resources/models.odin`, `scrapbot.odin`; importer, registry, and model-instance tests.

### Font

- Project config names source fonts. `prepare_project_fonts` builds fixed-size MTSDF atlas/metadata products under `.scrapbot/cache/fonts`.
- Runtime registration validates atlas dimensions, complete supported glyph coverage, ascender, and RGBA8 byte count.
- Re-registering a font name replaces atlas pixels in place and increments entry version; the handle generation remains stable while alive.
- UI retains font-dependent measurement/paint state; changed font resources invalidate their atlas/cache consumers rather than unrelated ECS membership.
- Inter remains the baked fallback when a project font is absent or unavailable.
- Source/tests: `project/fonts.odin`, `resources/resources.odin`, `ui/font_data.odin`; `project/project_test.odin`, `resources/resources_test.odin`, `ui/ui_test.odin`.

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
- **Play** captures authored Material base color and emissive values in the in-memory playback baseline alongside authored scene entities.
- **Stop** restores those captured base color/emissive values by UUID and increments a material version only when restored content differs. It does not reread resource files or reload Luau/native code.
- **Explicit Reimport** forces one UUID (or all imported resources), mutates live registry entries, retires stale generated model outputs, and reconciles Model roots without reloading the world, Luau, or native extensions.
- **Hot reload** ensures imports and re-registers fonts, textures, models, materials, and LOD geometry before replacing the world/runtime. Failed project/world reload keeps or restores the last-good runtime path. Its current aggregate asset stamp remains intentionally coarser than explicit Reimport until platform file watching lands.

See [Lifecycle matrix](lifecycle.md), [State ownership](state-ownership.md), [FDR-009](../fdr/FDR-009-project-resources.md), and [ADR-030](../adr/ADR-030-identify-project-resources-by-uuid-outside-the-ecs.md).
