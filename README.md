<img alt="Scrapbot Engine" src="https://github.com/user-attachments/assets/dbb0eb91-449d-49b1-99ea-93429b10734c" />

# Scrapbot Engine

A compact, experimental, and probably mostly useless game engine that tries to answer the question: what if a game engine was 100% agentically engineered, and structured specifically so agents can help you build your game?

> [!WARNING]
> **Do not expect this engine to be useful**. In particular, **do not try to make a game with it**! It's a **research project** with no aims to be production-ready, stable, or even particularly usable. It is a playground for exploring agentic workflows and game engine design and not much else. You have been warned. (We still love you though!)

## Contributing

Scrapbot is maintained as an agent-first codebase. Before opening a PR, read [`CONTRIBUTING.md`](CONTRIBUTING.md) for contributor expectations and [`AGENTS.md`](AGENTS.md) for the rules coding agents must follow when changing this repository.

The high-level roadmap is below. Active follow-up work lives in [`docs/TODO.md`](docs/TODO.md), with architecture and feature decisions tracked in [`docs/adr/`](docs/adr/) and [`docs/fdr/`](docs/fdr/). Project vocabulary lives in [`docs/GLOSSARY.md`](docs/GLOSSARY.md).

## Current Runtime Slice

Scrapbot currently has a small Odin CLI and runtime skeleton:

- `scrapbot init [path] [name]` creates a text-first project with `project.toml`, `scenes/main.scene.toml`, `scripts/main.luau`, an `assets/` directory, and Luau LSP metadata.
- `scrapbot check [path] [--json]` builds declared native extensions, validates the project manifest, default scene, and project Luau component schemas, refreshes generated Luau LSP types, and runs Luau static analysis when `luau-analyze` is available.
- `scrapbot build [path] [--target host] [--json]` creates a host-native runnable package under `build/<target>`, including the game executable, project data, and active native extension artifacts.
- `scrapbot run [path] [--backend null|wgpu] [--window] [--editor] [--hot-reload] [--scheduler-trace] [--runtime-stats] [--frames n] [--framegrab out.png] [--framegrab-region x,y,width,height] [--ui-script actions.json] [--ui-dump tree.json] [--json]` builds declared native extensions, loads the scene into a tiny native ECS world, executes `scripts/main.luau` if present, runs registered native and script systems, and submits the world through the selected renderer backend. `Ctrl+Esc` toggles the editor shell in a visible window, and `--editor` starts it open. Scheduler tracing reports native worker utilization. Runtime statistics report early/late engine-frame cost through render preparation, engine-allocator bytes including post-teardown retention, and ECS storage high-water marks. Windowed runtime statistics require a bounded `--frames` value. Framegrab regions preserve 1:1 output pixels and use top-left coordinates. UI diagnostic scripts semantically target reconciled ECS controls by UUID, name, or text, automatically reveal clipped targets, replay interactions, assert state, and select tight capture regions; UI dumps expose the final logical and screen-space tree as structured JSON.
- `scrapbot help <command>` prints command-specific options parsed by Odin's `core:flags`.

During development, use `mise build` to compile the CLI and `mise scrapbot -- [args...]` to compile and run it with arguments forwarded to Scrapbot.

This first slice intentionally uses a narrow schema-driven TOML reader instead of a complete TOML implementation. Every scene entity has a required project-wide UUID distinct from its editable name, and runtime spawns receive fresh UUIDs. Rendering is pluggable at the runtime boundary. The `null` backend supports headless smoke tests, while the `wgpu` backend renders full indexed geometry with shared base-color and PNG-textured materials, ECS ambient/directional/point lights, backend-owned GPU caches, automatic instanced batching, live window resizing, and a retained ECS UI overlay with a responsive box model, fixed or proportional horizontal and vertical stacks, draggable separators, per-axis fill and fit-to-content sizing, hidden subtrees, smooth clipped scroll areas, selectable lists, reusable progress indicators, collapsible titled panels with SDF disclosure icons, horizontally aligned MTSDF text, pointer-aware buttons, keyboard-focused single-line inputs, reusable SDF checkboxes, and SDF-rounded backgrounds and borders. Scene TOML, Luau systems, native Odin extensions, and transient editor chrome construct and mutate the same typed UI component values and per-entity styles; the renderer publishes shared read-only interaction state. UI, render-instance, camera, and light membership update from structural dirty queues and compact active sets instead of being discovered by rescanning the complete world every frame; retained UI parent/child/sibling links make steady-state layout and paint linear in the visible hierarchy. A transient ECS-built editor shell can frame the live project viewport with top, status, resizable scene and inspector chrome, independently smoothed scroll panes, an ECS-owned fly camera, and a system profiler that publishes engine, project-Odin, and Luau callback timings every five frames from a rolling 50-frame window. Headless WGPU can write a final-frame PNG with `--framegrab`. Luau scripting is embedded from a pinned source dependency and exposes the ECS, full geometry/material resource creation, scheduled systems, deferred lifecycle commands, generated types, native extension integration, and hot reload.

Example projects live in [`examples/`](examples/). The minimal example demonstrates Luau-defined and Odin-defined components and systems, and can be verified with `mise scrapbot run examples/minimal`. The ECS showcase runs a native object fountain with visible spawned cube renderables, velocity, lifetime, spin, despawn, animated point lights, editor-movable static point lights, and Luau typed queries.

Run the full local test suite with `mise test`; it includes a 2,000-frame lifecycle CPU/RAM growth gate. Use `mise test-soak` for the extended 10,000-frame check and `mise test-sanitize` for the Linux AddressSanitizer lane. Linux CI runs both the normal suite and AddressSanitizer.

## Features / Roadmap

### Engine Core

- Runtime
  - [x] Single-binary CLI
  - [ ] Cross-platform runtime
  - [ ] Interactive commands
  - [x] Headless commands
- Projects
  - [x] Text-first projects
  - [x] TOML scene files
  - [x] Project initialization
  - [ ] Project templates
  - [ ] Scene migrations
- Reloading
  - [x] Live reload
  - [x] Structured diagnostics
- Distribution
  - [x] Host game builds
  - [ ] Package dependencies
  - [ ] Cross-platform exports
  - [ ] Console/mobile publishing

### ECS Runtime

- World Model
  - [x] Shared ECS runtime
  - [x] Reflected components
  - [x] Stable project-wide entity UUIDs
  - [x] Generation-aware entities
  - [x] Component registry
  - [x] Component lifecycles
  - [x] ID-keyed custom component storage
  - [x] Engine-owned frame time resource
  - [x] Incremental render and retained-UI membership reconciliation
  - [ ] World snapshots
- Scheduling
  - [x] Scheduled systems
  - [x] Access-controlled systems
  - [x] Deferred mutations
  - [x] Parallel native system scheduling
- Queries
  - [x] Bulk Luau query views
  - [x] Multi-component Luau queries
  - [x] Typed three-component Luau queries
  - [ ] Advanced queries

### Scripting And Native Extensions

- Luau
  - [x] Luau scripting
  - [x] Luau type definitions
  - [x] Luau analyzer checks
  - [x] Basic script components
  - [x] Basic script systems
  - [x] Script hot reload
  - [x] Reflected script components
  - [x] Scheduled script systems
  - [ ] Editor scripting
- Native
  - [x] Native Odin modules
  - [x] Native hot reload
  - [x] Native ECS systems
  - [x] Native extension examples
  - [ ] Static native packaging
- Developer Experience
  - [ ] Script/native diagnostics
  - [ ] Performance documentation

### Rendering

- Backend
  - [x] WebGPU surface smoke
  - [x] Headful rendering smoke
  - [x] WebGPU triangle render loop
  - [x] Headless WebGPU framegrab
  - [x] WebGPU ECS cube renderer
  - [x] Multi-entity WebGPU cube renderer
  - [x] General indexed-geometry WebGPU renderer
  - [ ] Offscreen render comparison
- Scene Data
  - [x] Basic cameras
  - [x] Lighting
  - [x] Generated cube, plane, icosphere, UV sphere, pyramid, and cylinder geometry
  - [x] Shared base-color materials
  - [x] ECS-owned editor scene camera and captured fly navigation
- Pipeline
  - [x] Geometry/material render batching
  - [x] Directional shadow maps with explicit caster/receiver components
  - [ ] HDR rendering
  - [ ] Postprocessing
  - [ ] Frustum culling
  - [ ] GPU-driven rendering
  - [x] Ambient, directional, and point-light rendering
- Assets
  - [ ] Mesh assets
  - [x] PNG texture assets
  - [ ] Material system
- Tooling
  - [ ] Resource hot reload
  - [ ] Render debug views

### Input And UI

- Input
  - [ ] ECS platform input
  - [ ] Runtime input resources
  - [x] UI pointer position and primary-button input
  - [ ] Controller input
- Retained UI
  - [x] Retained UI primitives
  - [x] Box-model layout with horizontal, vertical, and overlay composition
  - [x] Element hover and active hit-testing state
  - [ ] UI command events
  - [x] Smooth clipped vertical scroll areas
  - [x] Collapsible titled panels
  - [x] Equal or proportional tables with draggable column separators
  - [x] Selectable lists and progress indicators
  - [ ] Canvas scaling
  - [x] Built-in scalable UI text
  - [x] MTSDF-based font rendering
  - [x] Auto-atlased project TTF/OTF fonts with embedded Inter fallback
  - [x] UI gallery
  - [x] Semantic headless UI replay, assertions, tree dumps, and target framegrabs
- Controls
  - [x] Text and pointer-styled button controls
  - [x] Reusable SDF checkbox controls
  - [x] Reusable numeric editor controls with validation, stepping, and scrubbing
  - [ ] Additional form controls
  - [x] Single-line text input with cursor movement and selection
  - [x] Keyboard focus with Tab and Shift+Tab traversal
  - [ ] Clipboard support
- Styling
  - [x] Scene-defined UI API
  - [x] Margins, padding, hidden subtrees, backgrounds, rounded corners, and borders
  - [ ] UI themes

### Editor

- Shell
  - [x] Toggleable editor shell
  - [x] Aspect-correct live game viewport
  - [x] Resizable panels
  - [ ] Dockable editor workspace
- Inspection
  - [x] System profiler
  - [x] Entity browser
  - [x] Entity selection
  - [x] Component field/value inspector with editable common fields
  - [ ] General component value editing
  - [ ] Searchable browser
  - [ ] Hierarchical browser
- Editing
  - [x] Live transform, camera, light, and custom Vec3 inspector editing
  - [x] UUID-addressed authoring transactions with inspector and gizmo undo/redo
  - [x] Registry-driven, namespaced component picker with add/remove undo/redo
  - [x] Entity create, duplicate, rename, delete, and runtime promotion
  - [x] Explicit stopped-mode scene persistence by stable entity UUID
  - [ ] Multi-selection editing
  - [x] Bounded field and structural editor transactions
- Scene Tools
  - [x] Play/Pause/Step with an in-memory authoring baseline, non-destructive Stop, and explicit Save
  - [x] RMB-captured WASD/Space/Ctrl scene-camera navigation
  - [x] World/local translation, rotation, and scale gizmo orientation
  - [x] Translation, rotation, and scale gizmo modes
  - [x] Two-axis plane handles and center free/uniform transform handles
  - [x] Precise viewport entity picking
- Extensibility
  - [ ] Asset browser
  - [ ] Editor plugins

### Testing And Tooling

- Commands
  - [x] Project validation
  - [ ] Deterministic stepping
  - [ ] Benchmark runner
  - [x] JSON command output
- Verification
  - [ ] Gameplay test fixtures
  - [ ] Offscreen render verification
  - [ ] Editor screenshot tests
  - [x] Native extension tests
  - [x] Lifecycle CPU/RAM growth gate
  - [x] Linux AddressSanitizer lane
- Project Support
  - [x] Example projects
  - [x] Documentation site
  - [x] Agent workflow docs
  - [x] macOS, Linux, and Windows CI workflow
  - [x] Docs checks
  - [ ] Benchmark trend reporting

### Assets, Simulation, And Larger Systems

- Assets
  - [x] Primitive geometry helpers
  - [x] Embedded UI font
  - [ ] Asset references
  - [ ] Asset import pipeline
  - [ ] Asset browser
- Scene Composition
  - [ ] Prefabs
  - [ ] Scene instancing
- Simulation
  - [ ] Physics
  - [ ] Animation clips
  - [ ] Skeletal meshes
  - [ ] Animation state machines
- Runtime Systems
  - [ ] Audio resources
  - [ ] Runtime audio
  - [ ] Networking
  - [ ] Terrain streaming
  - [ ] Large-world streaming

## License

Scrapbot is licensed under the [Apache License 2.0](LICENSE). Third-party notices and vendored dependency license details are tracked in [NOTICE](NOTICE).
