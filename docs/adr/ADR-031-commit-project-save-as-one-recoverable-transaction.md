# ADR-031: Commit project Save as one recoverable transaction

**Date:** 2026-07-17

## Context

One editor Save can change both the scene and several standalone project-resource files. Writing every resource independently before writing the scene exposes a partially saved project when a later serialization, validation, or filesystem operation fails. Per-file atomic replacement prevents torn TOML, but it does not make the authored project state atomic across files.

## Decision

Treat one editor Save as a project-level transaction. Prepare every dirty scene and resource output completely in memory, parse the generated TOML, and validate scene resource references before changing disk state. Derive resource file creation, replacement, move, and deletion by comparing each dirty UUID with the loaded project baseline. Stage every write beside its destination, mark destinations that did not previously exist, rename every existing write or delete destination to a reserved backup, and install every staged write. Create a separate committed marker only after every candidate is installed.

Before the committed marker exists, any failure restores every backup, removes newly installed destinations identified by creation markers, and removes all staged output. After it exists, the new file set is authoritative and cleanup removes backups and creation markers. Project loading checks the transaction markers before reading project data, so a process crash rolls an incomplete transaction backward or finishes cleanup for a committed transaction. The editor and hot-reload paths use the same coordinator and filesystem protocol.

## Consequences

Save can no longer leave new resource values paired with an old scene, or the inverse. Serialization and reference failures occur before the first destination changes. Adjacent staging keeps each rename on the destination filesystem, while deterministic fault injection covers staging, backup, installation, commit marking, rollback, and recovery on both sides of the commit boundary.

The protocol reserves `.scrapbot-save.*` marker and suffix names inside a project. New nested resource destinations create their parent directories before staging; rollback may leave an empty directory but never a partially authored file. A requested create refuses to overwrite an existing destination, and a requested delete refuses to target a missing source. Recovery performs a project-tree scan only when a transaction marker is present. A successful commit may be recovered forward if cleanup is interrupted. This protects against engine/process interruption and ordinary filesystem errors; without explicit directory and file syncing, it is not a claim of power-loss durability against storage hardware or operating-system cache loss.
