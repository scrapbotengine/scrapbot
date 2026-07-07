<img alt="Scrapbot Engine" src="https://github.com/user-attachments/assets/dbb0eb91-449d-49b1-99ea-93429b10734c" />

# Scrapbot Engine

A compact, experimental, and probably mostly useless game engine that tries to answer the question: what if a game engine was 100% agentically engineered, and structured specifically so agents can help you build your game?

> [!WARNING]
> **Do not expect this engine to be useful**. In particular, **do not try to make a game with it**! It's a **research project** with no aims to be production-ready, stable, or even particularly usable. It is a playground for exploring agentic workflows and game engine design and not much else. You have been warned. (We still love you though!)

## Contributing

Scrapbot is maintained as an agent-first codebase. Before opening a PR, read [`CONTRIBUTING.md`](CONTRIBUTING.md) for contributor expectations and [`AGENTS.md`](AGENTS.md) for the rules coding agents must follow when changing this repository.

The high-level roadmap is below. Active follow-up work lives in [`docs/TODO.md`](docs/TODO.md), with architecture and feature decisions tracked in [`docs/adr/`](docs/adr/) and [`docs/fdr/`](docs/fdr/).

## Features / Roadmap

### Engine Core

- Runtime
  - [ ] Single-binary CLI
  - [ ] Cross-platform runtime
  - [ ] Interactive commands
  - [ ] Headless commands
- Projects
  - [ ] Text-first projects
  - [ ] TOML scene files
  - [ ] Project initialization
  - [ ] Project templates
  - [ ] Scene migrations
- Reloading
  - [ ] Live reload
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
  - [ ] Generation-aware entities
  - [ ] Component registry
  - [ ] Component lifecycles
  - [ ] World snapshots
- Scheduling
  - [ ] Scheduled systems
  - [ ] Access-controlled systems
  - [ ] Deferred mutations
  - [ ] Parallel system scheduling
- Queries
  - [ ] Bulk Luau query views
  - [ ] Advanced queries

### Scripting And Native Extensions

- Luau
  - [ ] Luau scripting
  - [ ] Script components
  - [ ] Script systems
  - [ ] Script hot reload
  - [ ] Luau type definitions
  - [ ] Editor scripting
- Native
  - [ ] Native Odin modules
  - [ ] Native hot reload
  - [ ] Native extension examples
  - [ ] Static native packaging
- Developer Experience
  - [ ] Script/native diagnostics
  - [ ] Performance documentation

### Rendering

- Backend
  - [ ] WebGPU renderer
  - [ ] Headful rendering
  - [ ] Offscreen rendering
- Scene Data
  - [ ] Cameras
  - [ ] Lighting
  - [ ] Primitive meshes
  - [ ] Materials
  - [ ] Legacy cube rendering
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
  - [ ] Native extension tests
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
