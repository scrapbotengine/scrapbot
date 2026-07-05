# Machina

A compact, experimental, and probably mostly useless game engine that tries to answer the question: what if a game engine was 100% agentically engineered, and structured specifically so agents can help you build your game?

> [!WARNING]
> **Do not expect this engine to be useful**. In particular, **do not try to make a game with it**! It's a **research project** with no aims to be production-ready, stable, or even particularly usable. It is a playground for exploring agentic workflows and game engine design and not much else. You have been warned. (We still love you though!)

## Features / Roadmap

### Engine Core

- Runtime
  - [x] Single-binary CLI
  - [x] Cross-platform runtime
  - [x] Interactive commands
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
  - [x] Generation-aware entities
  - [x] Component registry
  - [ ] Component lifecycles
  - [ ] World snapshots
- Scheduling
  - [x] Scheduled systems
  - [x] Access-controlled systems
  - [x] Deferred mutations
  - [ ] Parallel system scheduling
- Queries
  - [x] Bulk Luau query views
  - [ ] Advanced queries

### Scripting And Native Extensions

- Luau
  - [x] Luau scripting
  - [x] Script components
  - [x] Script systems
  - [x] Script hot reload
  - [ ] Luau type definitions
  - [ ] Editor scripting
- Native
  - [x] Native Zig modules
  - [x] Native hot reload
  - [ ] Native extension examples
  - [ ] Static native packaging
- Developer Experience
  - [x] Script/native diagnostics
  - [ ] Performance documentation

### Rendering

- Backend
  - [x] WebGPU renderer
  - [x] Headful rendering
  - [x] Offscreen rendering
- Scene Data
  - [x] Cameras
  - [x] Lighting
  - [x] Primitive meshes
  - [x] Materials
  - [x] Legacy cube rendering
  - [ ] Scene camera workflow
- Pipeline
  - [x] Render batching
  - [x] Shadows
  - [x] HDR rendering
  - [x] Postprocessing
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
  - [x] ECS platform input
  - [x] Runtime input resources
  - [ ] Controller input
- Retained UI
  - [x] Retained UI primitives
  - [x] Retained layout system
  - [x] UI command events
  - [x] UI scrolling
  - [x] Canvas scaling
  - [x] Built-in bitmap UI text
  - [ ] SDF-based font rendering
  - [x] UI gallery
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
  - [x] Editor shell
  - [x] Game viewport
  - [x] Resizable panels
  - [ ] Dockable editor workspace
- Inspection
  - [x] System profiler
  - [x] Entity browser
  - [x] Entity selection
  - [x] Component inspector
  - [ ] Searchable browser
  - [ ] Hierarchical browser
- Editing
  - [x] Inspector editing
  - [x] Inspector undo/redo
  - [ ] Component management
  - [ ] Entity management
  - [ ] Scene edit persistence
  - [ ] Multi-selection editing
  - [ ] Editor transactions
- Scene Tools
  - [x] Playback controls
  - [x] Translate gizmo
  - [ ] Transform gizmo modes
  - [ ] Precise picking
- Extensibility
  - [ ] Asset browser
  - [ ] Editor plugins

### Testing And Tooling

- Commands
  - [x] Project validation
  - [x] Deterministic stepping
  - [x] Benchmark runner
  - [x] JSON command output
- Verification
  - [x] Gameplay test fixtures
  - [x] Offscreen render verification
  - [ ] Editor screenshot tests
  - [ ] Native extension tests
- Project Support
  - [x] Example projects
  - [x] Documentation site
  - [x] Agent workflow docs
  - [ ] CI workflow
  - [ ] Docs checks
  - [ ] Benchmark trend reporting

### Assets, Simulation, And Larger Systems

- Assets
  - [x] Primitive geometry
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
