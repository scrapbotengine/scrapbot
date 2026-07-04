# FDR-019: Host Game Builds

**Status:** Active
**Last reviewed:** 2026-07-04

## Overview

Host game builds let users package a Machina project into a runnable bundle for the current machine's operating system and architecture. The feature exists so projects can be validated, copied, and launched outside the source workspace without requiring project-local native Zig source to be rebuilt on the target machine.

## Behavior

- `machina build [path]` validates the project and creates a host-platform bundle.
- The bundle contains the Machina runtime executable, a copied project tree, a launcher script, and a build manifest.
- Build output defaults to `build` inside the project directory.
- Users can choose the output root, bundle name, text or JSON output, and whether to replace a previous Machina-generated bundle.
- Generated project caches and repository/build directories are excluded from the copied project tree.
- Projects with `native = "..."` are packaged with a prebuilt native library artifact.
- Projects that already contain only `native_artifact` copy that artifact explicitly even when it lives under the otherwise-excluded `.machina` directory.
- Packaged projects load `native_artifact` when present, so they do not need the Zig compiler or native source file to run.
- Build validates the copied packaged project before reporting success, including loading and registering the packaged native artifact.
- Build bundles are host-only. Cross-platform export, mobile packaging, codesigning, notarization, and fully static project-native executables are not part of this feature.

## Design Decisions

### 1. Start with host-platform bundles

**Decision:** `machina build` produces a bundle for the current OS and architecture.
**Why:** Machina already has a validated project loader, headful runtime, and project-local native dynamic module path. Packaging those pieces gives immediate value without pretending cross-compilation, app bundles, or store-ready distribution are solved.
**Tradeoff:** Users must build separately on each target platform for now.

### 2. Use native artifacts for packaged projects

**Decision:** Packaged project manifests can include `native_artifact`, which takes precedence over rebuilding `native` source.
**Why:** Runtime bundles should not require a Zig toolchain on the target machine. This follows the source-level native boundary established by ADR-019 while keeping the first build path compatible with the current dynamic module implementation.
**Tradeoff:** The bundle still uses dynamic native loading. Platforms that forbid dynamic code loading need the future static SDK path.

### 3. Validate packaged output before success

**Decision:** `machina build` validates the copied project after manifest rewriting and artifact copying, then reports any packaged native build/load/registration failure as a structured diagnostic.
**Why:** The development-time precheck can validate a Debug native build while the bundle uses a ReleaseFast artifact. The build command must prove the artifact it ships can actually load and register.
**Tradeoff:** Native projects pay one extra packaged validation pass during build.

### 4. Keep replacement explicit

**Decision:** Existing bundle directories are replaced only with `--force`, and only when they carry the Machina build marker.
**Why:** Build commands should not delete arbitrary user directories by accident. This follows the project-directory runtime's non-destructive command direction.
**Tradeoff:** Users may need to manually remove stale partial directories that were not produced by a completed Machina build.

### 5. Treat external runtime libraries as packaging work

**Decision:** The first bundle copies discoverable SDL3 runtime libraries into `lib/`, and generated launchers add that directory to the platform dynamic library search path before running `bin/machina`. If SDL3 cannot be discovered, the build records a warning.
**Why:** The current runtime links SDL3 as a platform library. Copying known local libraries and making the launcher search `lib/` gives host bundles a practical same-platform relocation path without turning v1 into a platform installer.
**Tradeoff:** Deeper app relocation, rpath/install-name repair, codesigning, and installer-grade dependency management remain future packaging work.

## Related

- **ADRs:** ADR-003, ADR-005, ADR-019
- **FDRs:** FDR-001, FDR-012

## Open Questions

- What SDK shape should support fully static project-native builds?
- What platform-specific bundle formats should Machina produce first after host folders?
