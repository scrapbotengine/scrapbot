# ADR-053: Expose live debugging through a transport-independent service

**Date:** 2026-08-05

## Context

Renderer defects often depend on an exact camera pose, residency state, viewport, and sequence of frames. Reconstructing that state from a screenshot or a hand-written camera path is slow and unreliable.

Scrapbot needs automation to inspect a running editor or game and request bounded evidence. The service must remain useful to game projects, avoid granting a network thread direct access to ECS or GPU state, and leave room for richer transports without coupling engine diagnostics to one RPC library.

Odin's standard library already provides deterministic CBOR and networking. Current third-party protobuf, MessagePack, and HTTP packages do not offer a sufficiently complete, stable combination to make them part of Scrapbot's core runtime contract.

## Decision

Scrapbot owns a transport-independent live debug service. Engine and renderer code publish immutable snapshots at explicit frame boundaries and consume bounded commands on the engine thread.

The first transport is a small HTTP/1.1 loopback adapter:

- JSON is the default representation.
- Deterministic CBOR is available through content negotiation.
- Binary artifacts use their native media types rather than being embedded in either representation.
- A per-process discovery file advertises the loopback URL, schema version, process ID, project root, and random bearer token, requesting owner-only permissions where the host supports them.
- The server accepts only loopback connections and applies request-size and capture-length limits.

The network worker may authenticate, parse, encode, and enqueue requests. It must never traverse or mutate the ECS, renderer, resource registry, or GPU objects.

Editor runs enable the service automatically. Standalone source and packaged games require an explicit runtime option. A future Connect/protobuf adapter may expose the same service when the Odin ecosystem and generated schema support are mature enough; it must not replace the service boundary.

## Consequences

Agents and tools can inspect the exact running camera and renderer state instead of guessing a reproduction. Bounded consecutive-frame telemetry captures preserve temporal evidence without stopping the process.

JSON keeps ad hoc inspection easy, while CBOR reduces larger machine payloads without adding a dependency or changing the data model. Clients must inspect `schema_version` and must not depend on enum ordinals or human log text.

The in-tree HTTP adapter deliberately implements only the subset Scrapbot needs. Streaming images, depth, visibility buffers, and other large artifacts remain capture providers to add behind the service rather than reasons to expose renderer internals to the network thread.

Discovery files contain a bearer token and therefore remain ignored engine state. Loopback authentication is a development safeguard, not a remote-debug security boundary; remote binding is unsupported.
