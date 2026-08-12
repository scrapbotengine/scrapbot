# ADR-060: Browse files through rooted metadata models

**Date:** 2026-08-12

## Context

The editor needs filesystem-shaped tooling for resources now and for open/save workflows later. Letting each consumer join arbitrary paths, scan recursively, and load file payloads would duplicate policy, make root escapes easy, and couple browsing to resource residency.

## Decision

Scrapbot provides a reusable `file_browser.State` rooted at one absolute directory. It retains only the current relative directory plus bounded entry metadata. Refresh is explicit, lists at most 4,096 direct children, filters hidden files and extensions by policy, sorts directories before files case-insensitively, and never reads file payloads.

Navigation accepts only normalized relative paths inside the root. It rejects parent escapes and every symbolic-link path component. A failed refresh or navigation leaves the previous directory and entries intact. The model exposes no open, save, delete, import, or activation policy; consumers resolve a selected relative path and apply their own capability and validation rules.

The editor Resource Browser roots this model at `resources/` and joins its directory metadata with the authoritative resource registry by source path. The browser does not load or retain additional resource payloads. Laid-out renderable rows may borrow the existing fixed embedded-viewport preview pool; non-renderable rows use the built-in icon atlas. Existing registry ownership, selected-resource inspection, authoring transactions, Save, and drag placement remain separate consumers.

Filesystem scans happen only during initialization or explicit refresh/navigation, never on stable frames. Future file dialogs reuse the model with different roots, filters, and consumer policies rather than creating new filesystem traversal code.

## Consequences

Browsing remains memory-bounded and cannot silently turn directory discovery into resource loading. Save/open/import policies stay explicit and testable. Symlinked content is intentionally invisible through this abstraction; mounting external directories requires a separately authorized root. Native platform dialogs and asynchronous scans may wrap or replace presentation later without changing the rooted path contract.
