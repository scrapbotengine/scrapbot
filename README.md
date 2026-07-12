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

- `scrapbot init [path] [name]` creates a text-first project with `project.toml`, `scenes/main.scene.toml`, `scripts/main.luau`, and Luau LSP metadata.
- `scrapbot check [path]` builds declared native extensions, validates the project manifest, default scene, and project Luau component schemas, refreshes generated Luau LSP types, and runs Luau static analysis when `luau-analyze` is available.
- `scrapbot build [path]` builds declared native extensions without running or validating the scene.
- `scrapbot run [path] [--backend null|wgpu] [--window] [--hot-reload] [--frames n] [--framegrab out.png]` builds declared native extensions, loads the scene into a tiny native ECS world, executes `scripts/main.luau` if present, runs registered native and script systems, and submits the world through the selected renderer backend.
- `scrapbot help <command>` prints command-specific options parsed by Odin's `core:flags`.

During development, use `mise build` to compile the CLI and `mise scrapbot -- [args...]` to compile and run it with arguments forwarded to Scrapbot.

This first slice intentionally uses a narrow schema-driven TOML reader instead of a complete TOML implementation. Rendering is pluggable at the runtime boundary. The `null` backend supports headless smoke tests, while the `wgpu` backend uses SDL3 and `wgpu-native` to render ECS cube renderables with a perspective camera. Headless WGPU can write a final-frame PNG with `--framegrab`. Luau scripting is embedded from a pinned source dependency and currently exposes a small ECS bridge for project-local systems, typed schema markers, typed script-defined, library, native-extension, and built-in component handles, access-declared scheduled systems, reusable ID-keyed query objects, joined query views, query-driven script systems with declared transform and schema-backed custom component payload write-back, deferred entity/component lifecycle commands, generation-aware entity handles, generated component type aliases, native extension systems with scheduled ECS access through the `scrapbot:extension` Odin helper package, and periodic hot reload for `project.toml`, the default scene, `scripts/main.luau`, native extension libraries, and declared native extension source directories. A small component registry validates project-level Luau components, script-registered library components, native extension components, and known engine component names.

Example projects live in [`examples/`](examples/). The minimal example can be verified with `mise scrapbot run examples/minimal`.

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
  - [ ] Host game builds
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
  - [ ] World snapshots
- Scheduling
  - [x] Scheduled systems
  - [x] Access-controlled systems
  - [x] Deferred mutations
  - [ ] Parallel system scheduling
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
  - [ ] General WebGPU scene renderer
  - [ ] Offscreen render comparison
- Scene Data
  - [x] Basic cameras
  - [ ] Lighting
  - [x] Cube primitive mesh
  - [ ] Materials
  - [ ] Scene camera workflow
- Pipeline
  - [ ] Render batching
  - [ ] Shadows
  - [ ] HDR rendering
  - [ ] Postprocessing
  - [ ] Frustum culling
  - [ ] GPU-driven rendering
  - [ ] Multi-light rendering
- Assets
  - [ ] Mesh assets
  - [ ] Texture assets
  - [ ] Material system
- Tooling
  - [ ] Resource hot reload
  - [ ] Render debug views

### Input And UI

- Input
  - [ ] ECS platform input
  - [ ] Runtime input resources
  - [ ] Controller input
- Retained UI
  - [ ] Retained UI primitives
  - [ ] Retained layout system
  - [ ] UI command events
  - [ ] UI scrolling
  - [ ] Canvas scaling
  - [ ] Built-in bitmap UI text
  - [ ] SDF-based font rendering
  - [ ] UI gallery
- Controls
  - [ ] Reusable editor controls
  - [ ] Form controls
  - [ ] Text input
  - [ ] Keyboard focus
  - [ ] Clipboard support
- Styling
  - [ ] Public UI API
  - [ ] Richer layout system
  - [ ] UI themes

### Editor

- Shell
  - [ ] Editor shell
  - [ ] Game viewport
  - [ ] Resizable panels
  - [ ] Dockable editor workspace
- Inspection
  - [ ] System profiler
  - [ ] Entity browser
  - [ ] Entity selection
  - [ ] Component inspector
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
  - [ ] Translate gizmo
  - [ ] Transform gizmo modes
  - [ ] Precise picking
- Extensibility
  - [ ] Asset browser
  - [ ] Editor plugins

### Testing And Tooling

- Commands
  - [ ] Project validation
  - [ ] Deterministic stepping
  - [ ] Benchmark runner
  - [ ] JSON command output
- Verification
  - [ ] Gameplay test fixtures
  - [ ] Offscreen render verification
  - [ ] Editor screenshot tests
  - [x] Native extension tests
- Project Support
  - [ ] Example projects
  - [ ] Documentation site
  - [ ] Agent workflow docs
  - [ ] CI workflow
  - [ ] Docs checks
  - [ ] Benchmark trend reporting

### Assets, Simulation, And Larger Systems

- Assets
  - [ ] Primitive geometry
  - [ ] Embedded UI font
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
