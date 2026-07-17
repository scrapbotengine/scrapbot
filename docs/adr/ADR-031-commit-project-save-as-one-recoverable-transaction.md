# ADR-031: Commit project Save as one recoverable transaction

**Date:** 2026-07-17

## Context

One editor Save can change both the scene and several standalone project-resource files. Writing every resource independently before writing the scene exposes a partially saved project when a later serialization, validation, or filesystem operation fails. Per-file atomic replacement prevents torn TOML, but it does not make the authored project state atomic across files.

## Decision

Treat one editor Save as a project-level transaction. Prepare every dirty scene and resource output completely in memory, parse the generated TOML, and validate scene resource references before changing disk state. Stage every candidate beside its destination, rename every existing destination to a reserved backup, and install every staged candidate. Create a separate committed marker only after every candidate is installed.

Before the committed marker exists, any failure restores every backup and removes all staged output. After it exists, the new file set is authoritative and cleanup removes the backups. Project loading checks the transaction markers before reading project data, so a process crash rolls an incomplete transaction backward or finishes cleanup for a committed transaction. The editor and hot-reload paths use the same coordinator and filesystem protocol.

The current transaction replaces existing scene and resource files. Creating, deleting, or moving project-resource files will extend the transaction manifest when those authoring operations become supported.

## Consequences

Save can no longer leave new resource values paired with an old scene, or the inverse. Serialization and reference failures occur before the first destination changes. Adjacent staging keeps each rename on the destination filesystem, while deterministic fault injection covers staging, backup, installation, commit marking, rollback, and recovery on both sides of the commit boundary.

The protocol reserves `.scrapbot-save.*` marker and suffix names inside a project. Recovery performs a project-tree scan only when a transaction marker is present. A successful commit may be recovered forward if cleanup is interrupted. This protects against engine/process interruption and ordinary filesystem errors; without explicit directory and file syncing, it is not a claim of power-loss durability against storage hardware or operating-system cache loss.
