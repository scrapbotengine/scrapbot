# FDR-019: Host Game Builds

**Status:** Active
**Last reviewed:** 2026-07-04

## Overview

Host game builds let users package a Scrapbot project into a runnable bundle for the current machine's operating system and architecture. The feature exists so projects can be validated, copied, and launched outside the source workspace without requiring project-local native Zig source to be rebuilt on the target machine.

## Behavior

- `scrapbot build [path]` validates the project and creates a host-platform bundle.
- The bundle contains the Scrapbot runtime executable, a copied project tree, a launcher script, and a build manifest.
- Build output defaults to `build` inside the project directory.
- Users can choose the output root, bundle name, text or JSON output, and whether to replace a previous Scrapbot-generated bundle.
- Generated project caches and repository/build directories are excluded from the copied project tree.
- Projects with `native = "..."` are packaged with a prebuilt native library artifact.
- Projects that already contain only `native_artifact` copy that artifact explicitly even when it lives under the otherwise-excluded `.scrapbot` directory. During the Odin migration, the Odin `scrapbot build` path preserves these existing artifacts and reports them in the build manifest before compiled Odin-native module builds are available.
- Packaged projects load `native_artifact` when present, so they do not need the Zig compiler or native source file to run.
- Build validates the copied packaged project before reporting success. The current Zig path loads and registers packaged native artifacts; during the Odin migration, the Odin path validates preserved artifact presence and packaged metadata until compiled Odin-native module loading exists.
- Build bundles are host-only. Cross-platform export, mobile packaging, codesigning, notarization, and fully static project-native executables are not part of this feature.

## Design Decisions

### 1. Start with host-platform bundles

**Decision:** `scrapbot build` produces a bundle for the current OS and architecture.
**Why:** Scrapbot already has a validated project loader, headful runtime, and project-local native dynamic module path. Packaging those pieces gives immediate value without pretending cross-compilation, app bundles, or store-ready distribution are solved.
**Tradeoff:** Users must build separately on each target platform for now.

### 2. Use native artifacts for packaged projects

**Decision:** Packaged project manifests can include `native_artifact`, which takes precedence over rebuilding `native` source.
**Why:** Runtime bundles should not require a Zig toolchain on the target machine. This follows the source-level native boundary established by ADR-019 while keeping the first build path compatible with the current dynamic module implementation.
**Tradeoff:** The bundle still uses dynamic native loading. Platforms that forbid dynamic code loading need the future static SDK path.

### 3. Validate packaged output before success

**Decision:** `scrapbot build` validates the copied project after manifest rewriting and artifact copying, then reports packaged native build/load/registration failures as structured diagnostics on native-loading paths.
**Why:** The development-time precheck can validate a Debug native build while the bundle uses a ReleaseFast artifact. The build command must prove the artifact it ships can actually load and register.
**Tradeoff:** Native projects pay one extra packaged validation pass during build.

### 4. Keep replacement explicit

**Decision:** Existing bundle directories are replaced only with `--force`, and only when they carry the Scrapbot build marker.
**Why:** Build commands should not delete arbitrary user directories by accident. This follows the project-directory runtime's non-destructive command direction.
**Tradeoff:** Users may need to manually remove stale partial directories that were not produced by a completed Scrapbot build.

### 5. Treat external runtime libraries as packaging work

**Decision:** The first bundle copies discoverable SDL3 runtime libraries into `lib/`, and generated launchers add that directory to the platform dynamic library search path before running `bin/scrapbot`. If SDL3 cannot be discovered, the build records a warning. During the Odin migration, the Odin `scrapbot build` path follows the same host-library discovery, copy, launcher, and manifest contract.
**Why:** The current runtime links SDL3 as a platform library. Copying known local libraries and making the launcher search `lib/` gives host bundles a practical same-platform relocation path without turning v1 into a platform installer.
**Tradeoff:** Deeper app relocation, rpath/install-name repair, codesigning, and installer-grade dependency management remain future packaging work.

## Related

- **ADRs:** ADR-003, ADR-005, ADR-019
- **FDRs:** FDR-001, FDR-012

## Open Questions

- What SDK shape should support fully static project-native builds?
- What platform-specific bundle formats should Scrapbot produce first after host folders?
