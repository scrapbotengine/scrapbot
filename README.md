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

- Implementation Language
  - [x] Odin migration accepted
  - [x] Odin smoke build scaffold
  - [x] Odin project init command slice
  - [x] Odin project build command slice
  - [x] Odin project metadata check slice
  - [x] Odin scene structure check slice
  - [x] Odin engine component schema check slice
  - [x] Odin scene-to-world loading slice
  - [x] Odin project component schema check slice
  - [x] Odin runtime registry/entity identity slice
  - [x] Odin ECS component storage/query slice
  - [x] Odin ECS scheduling/deferred mutation slice
  - [x] Odin script system registration/schedule check slice
  - [x] Odin structured script validation diagnostics slice
  - [x] Odin Luau bridge declaration loading slice
  - [x] Odin Luau query/component-field execution slice
  - [x] Odin Luau structural command execution slice
  - [x] Odin Luau direct vec3 method execution slice
  - [x] Odin Luau prepared query/resolved-row execution slice
  - [x] Odin Luau bulk query view execution slice
  - [x] Odin Luau runtime bridge diagnostics slice
  - [x] Odin deterministic step command slice
  - [x] Odin benchmark command slice
  - [x] Odin render benchmark command slice
  - [x] Odin test discovery/manifest command slice
  - [x] Odin test field assertion execution slice
  - [x] Odin test input resource replay slice
  - [x] Odin retained scene UI replay slice
  - [x] Odin editor chrome input ownership replay slice
  - [x] Odin editor playback replay slice
  - [x] Odin editor entity-list selection replay slice
  - [x] Odin editor entity spawn/despawn replay slice
  - [x] Odin editor component add/remove replay slice
  - [x] Odin editor entity-list scroll replay slice
  - [x] Odin editor system-list scroll replay slice
  - [x] Odin editor inspector scroll replay slice
  - [x] Odin editor inspector retained scroll/vgroup routing slice
  - [x] Odin editor inspector field selection replay slice
  - [x] Odin editor splitter drag replay slice
  - [x] Odin editor inspector text edit replay slice
  - [x] Odin editor inspector text caret replay slice
  - [x] Odin editor inspector vec3 lane edit replay slice
  - [x] Odin editor inspector typed control replay slice
  - [x] Odin editor inspector known selector replay slice
  - [x] Odin editor inspector undo/redo replay slice
  - [x] Odin editor inspector invalid-edit diagnostics slice
  - [x] Odin editor inspector clipboard copy/paste slice
  - [x] Odin editor selected-header copy slice
  - [x] Odin editor inspector scene-field persistence slice
  - [x] Odin editor gizmo drag replay slice
  - [x] Odin bounded run command slice
  - [x] Odin bounded run reload reporting slice
  - [x] Odin live-project frame tick reload slice
  - [x] Odin render extraction stats slice
  - [x] Odin render command validation slice
  - [x] Odin software render image output slice
  - [x] Odin visual-test command validation slice
  - [x] Odin visual-test golden comparison slice
  - [x] Odin inspector widget visual-test coverage slice
  - [x] Odin offscreen editor chrome render slice
  - [x] Odin software selected inspector card render slice
  - [x] Odin software inspector visual scroll render slice
  - [x] Odin software typed inspector control render slice
  - [x] Odin WebGPU selected inspector overlay render slice
  - [x] Odin wgpu-native ABI boundary slice
  - [x] Odin wgpu-native descriptor boundary slice
  - [x] Odin wgpu-native copy/readback boundary slice
  - [x] Odin wgpu-native proc-table resolver slice
  - [x] Odin wgpu-native dynamic offscreen loader slice
  - [x] Odin wgpu-native context request boundary slice
  - [x] Odin wgpu-native render pass command boundary slice
  - [x] Odin wgpu-native resource binding boundary slice
  - [x] Odin wgpu-native shader/pipeline boundary slice
  - [x] Odin wgpu-native queue upload boundary slice
  - [x] Odin wgpu-native surface presentation boundary slice
  - [x] Odin wgpu-native default dynamic library load check slice
  - [x] Odin wgpu-native instance smoke slice
  - [x] Odin wgpu-native context smoke slice
  - [x] Odin wgpu-native offscreen clear/readback smoke slice
  - [x] Odin wgpu-native offscreen pipeline draw/readback smoke slice
  - [x] Odin wgpu-native offscreen image artifact smoke slice
  - [x] Odin wgpu-native scene render-test backend slice
  - [x] Odin bounded hidden run WebGPU offscreen frame slice
  - [x] Odin SDL hidden window surface descriptor slice
  - [x] Odin hidden WebGPU surface presentation smoke slice
  - [x] Odin bounded hidden run WebGPU surface presentation slice
  - [x] Odin wgpu-native direct library staging slice
  - [x] Odin wgpu-native Zig cache fallback removal slice
  - [x] Odin bounded visible WebGPU run SDL loop slice
  - [x] Odin unbounded visible WebGPU run SDL loop slice
  - [x] Odin first-pass WebGPU editor chrome overlay slice
  - [x] Odin bounded visible software run SDL loop slice
  - [x] Odin unbounded visible software run SDL loop slice
  - [x] Odin visible software run pixel presentation slice
  - [x] Odin visible SDL run editor input routing slice
  - [x] Odin visible SDL run editor text input slice
  - [x] Odin visible SDL run editor toggle slice
  - [x] Odin visible SDL fly-camera input state slice
  - [x] Odin renderer camera override slice
  - [x] Odin visible editor gizmo camera override slice
  - [x] Odin editor gizmo undo grouping slice
  - [x] Odin SDL editor selection/gizmo smoke coverage slice
  - [x] Odin editor translate-gizmo render styling slice
  - [x] Odin visible editor entity lifecycle controls slice
  - [x] Odin visible editor component lifecycle controls slice
  - [x] Odin macOS release artifact workflow slice
  - [x] Odin CI smoke without Zig toolchain slice
  - [x] Odin native declaration registration slice
  - [x] Odin native execution boundary diagnostics slice
  - [x] Odin CLI feature parity
  - [ ] Zig engine implementation removed
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
  - [x] SDL3 host-library bundling in Odin build
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
  - [x] Odin engine rejects project-local Zig native source
  - [x] Native Odin component/system declaration scanning
  - [x] Native Odin pending-execution diagnostics
  - [x] Native Odin set-field execution slice
  - [x] Native Odin lifecycle execution slice
  - [x] Native artifact packaging in Odin build
  - [x] Native Odin source artifact build in Odin build
  - [x] Native Odin packaged callback execution slice
  - [x] Native Odin host API callback parity slice
  - [x] Native Odin development source build/load slice
  - [x] Native Odin module execution
  - [x] Native Odin live reload transaction slice
  - [x] Native Odin example fixtures
  - [x] Native hot reload
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
  - [x] Test discovery and manifest validation
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

## License

Scrapbot is licensed under the [Apache License 2.0](LICENSE). Third-party notices and vendored dependency license details are tracked in [NOTICE](NOTICE).
