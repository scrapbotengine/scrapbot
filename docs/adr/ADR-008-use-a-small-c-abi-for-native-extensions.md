# ADR-008: Use a small C ABI for native extensions

**Date:** 2026-07-11

## Context

Scrapbot projects should be able to move hot code from Luau into compiled native modules over time. The engine is written in Odin, but extension authors may eventually use Odin or another compiled language. That boundary needs to be stable enough for dynamic loading and hot reload experiments without exposing internal engine package layouts.

## Decision

Let projects declare native extension targets in `project.toml`, build those targets into `build/extensions`, load the resulting platform dynamic libraries, and look for a `scrapbot_extension_register` export. The first ABI is a small C-compatible table in `extension_api`: an ABI version, opaque host userdata, and a function for registering library component schemas.

Native extensions can register dotted, non-`scrapbot` library component names into the same component registry used by Luau scripts, scene validation, queries, and generated Luau types. Project runs and checks build and load native extensions before executing `scripts/main.luau`, so scripts can retrieve native-registered component handles with `scrapbot.component_handle(name)`.

## Consequences

The first native extension surface is intentionally narrow: component schema registration only. That is enough to prove dynamic loading, registry integration, generated types, and hot reload without committing to native systems, allocators, threading, or world mutation APIs.

The C ABI keeps the runtime boundary language-neutral and avoids coupling extensions to Scrapbot internals. The tradeoff is that the API must use plain data shapes and explicit versioning. The first build path is Odin-specific for developer ergonomics, but the loaded library boundary remains language-neutral. Extension libraries must remain loaded while any runtime registry copied from their cstring metadata is in use.
