# ADR-023: Identify entities with project-wide UUIDs

**Date:** 2026-07-14

## Context

Scene entity names are editable labels. Using them as identity makes renames break hierarchy references and prevents two entities from sharing a useful display name. Runtime entity handles solve a different problem: their index and generation efficiently reject stale references within one world lifetime, but they cannot identify the same authored entity across reloads, editor sessions, or serialized files.

## Decision

Give every entity a non-zero RFC UUID in addition to its runtime index-and-generation handle. Require scene files to serialize a unique `id` for every `[[entities]]` table and use UUIDs for cross-entity scene references such as `ui_layout.parent`. Treat `name` only as a human-facing label.

Copy authored UUIDs into the runtime world unchanged and maintain a world-local UUID-to-entity-index map. Generate a fresh version-4 UUID for every runtime-spawned entity lifetime, including when a dead storage slot is reused. Give engine-owned transient entities deterministic version-8 UUIDs derived from their private engine names so reconciliation can find them without exposing their names as public identity.

Keep generation-aware entity handles for hot runtime access and stale-handle protection. UUIDs provide stable project identity; handles provide efficient identity for one in-memory lifetime.

## Consequences

Renaming an entity no longer breaks hierarchy links, and serialized references have a stable target independent of scene order or runtime storage. Luau entity snapshots can expose both forms of identity: `id` for durable references and index/generation for immediate runtime operations.

Every existing scene must be migrated because missing, malformed, zero, or duplicate UUIDs are rejected. Runtime spawn now performs UUID generation and world-map maintenance. Future serialization, prefab, duplication, and scene-merge tools must define when UUIDs are preserved and when new UUIDs are minted.
