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
- `scrapbot run [path] [--backend null|wgpu] [--window] [--editor] [--hot-reload] [--scheduler-trace] [--frames n] [--framegrab out.png] [--json]` builds declared native extensions, loads the scene into a tiny native ECS world, executes `scripts/main.luau` if present, runs registered native and script systems, and submits the world through the selected renderer backend. `Ctrl+Esc` toggles the editor shell in a visible window, and `--editor` starts it open. Scheduler tracing reports native worker utilization for the run.
- `scrapbot help <command>` prints command-specific options parsed by Odin's `core:flags`.

During development, use `mise build` to compile the CLI and `mise scrapbot -- [args...]` to compile and run it with arguments forwarded to Scrapbot.

This first slice intentionally uses a narrow schema-driven TOML reader instead of a complete TOML implementation. Rendering is pluggable at the runtime boundary. The `null` backend supports headless smoke tests, while the `wgpu` backend renders full indexed geometry with shared base-color and PNG-textured materials, ECS ambient/directional/point lights, backend-owned GPU caches, automatic instanced batching, and a retained ECS UI overlay with a box model, horizontal and vertical stacks, MTSDF text, pointer-aware buttons, and SDF-rounded backgrounds. An engine-owned editor shell can frame the live project viewport with top, status, scene, and inspector chrome, plus an ECS-owned fly camera that navigates independently from the project's camera. Headless WGPU can write a final-frame PNG with `--framegrab`. Luau scripting is embedded from a pinned source dependency and exposes the ECS, full geometry/material resource creation, scheduled systems, deferred lifecycle commands, generated types, native extension integration, and hot reload.

Example projects live in [`examples/`](examples/). The minimal example demonstrates Luau-defined and Odin-defined components and systems, and can be verified with `mise scrapbot run examples/minimal`. The ECS showcase runs a native object fountain with visible spawned cube renderables, velocity, lifetime, spin, despawn, animated point lights, editor-movable static point lights, and Luau typed queries.

Run the full local test suite with `mise test`.

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
  - [ ] Structured diagnostics
- Distribution
  - [x] Host game builds
  - [ ] Package dependencies
  - [ ] Cross-platform exports
  - [ ] Console/mobile publishing

### ECS Runtime

- World Model
  - [ ] Shared ECS runtime
  - [ ] Reflected components
  - [x] Generation-aware entities
  - [x] Component registry
  - [x] Component lifecycles
  - [x] ID-keyed custom component storage
  - [x] Engine-owned frame time resource
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
  - [ ] UI scrolling
  - [ ] Canvas scaling
  - [x] Built-in scalable UI text
  - [x] MTSDF-based font rendering
  - [x] UI gallery
- Controls
  - [x] Text and pointer-styled button controls
  - [ ] Reusable editor controls
  - [ ] Form controls
  - [ ] Text input
  - [ ] Keyboard focus
  - [ ] Clipboard support
- Styling
  - [x] Scene-defined UI API
  - [x] Margins, padding, backgrounds, and rounded corners
  - [ ] UI themes

### Editor

- Shell
  - [x] Toggleable editor shell
  - [x] Aspect-correct live game viewport
  - [ ] Resizable panels
  - [ ] Dockable editor workspace
- Inspection
  - [ ] System profiler
  - [x] Entity browser
  - [x] Entity selection
  - [x] Read-only component field/value inspector
  - [ ] Component value editing
  - [ ] Searchable browser
  - [ ] Hierarchical browser
- Editing
  - [ ] Inspector editing
  - [ ] Inspector undo/redo
  - [ ] Component management
  - [ ] Entity management
  - [ ] Scene edit persistence
  - [ ] Multi-selection editing
  - [ ] Editor transactions
- Scene Tools
  - [ ] Playback controls
  - [x] RMB-captured WASD/Space/Ctrl scene-camera navigation
  - [x] World-space translation gizmo
  - [ ] Transform gizmo modes
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
- Project Support
  - [x] Example projects
  - [ ] Documentation site
  - [ ] Agent workflow docs
  - [ ] CI workflow
  - [ ] Docs checks
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
