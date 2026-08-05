---
title: Live Debug API
description: Inspect a running Scrapbot process and capture consecutive frame telemetry and images over a local authenticated API.
---

Scrapbot's live debug API lets local tools inspect the exact state of a running editor or game. It is useful when a renderer defect depends on camera pose, viewport size, virtual-geometry residency, or changes across several frames.

Windowed editor runs enable the API automatically:

```sh
bin/scrapbot run examples/virtual-wilds --editor
```

Other source and packaged runs must opt in:

```sh
bin/scrapbot run examples/minimal --live-debug
```

Pass `--live-debug-port 8088` to request a fixed port. The default `0` asks the operating system for an available port.

## Discover a process

Each process writes one ignored discovery document to:

```text
<project>/.scrapbot/live/<process-id>.json
```

The document contains `schema_version`, `process_id`, `project_root`, `url`, and a random bearer `token`. Scrapbot requests owner-only read/write permissions where the host supports them, and the file exists only while the server is running normally.

Treat the token as a local development credential. Do not publish discovery documents or copy them into build artifacts.

## Read the current snapshot

This shell example reads the newest discovery file and requests JSON:

```sh
discovery=$(ls -t my-game/.scrapbot/live/*.json | head -1)
url=$(jq -r .url "$discovery")
token=$(jq -r .token "$discovery")

curl --header "Authorization: Bearer $token" \
  "$url/v1/snapshot" | jq
```

`GET /v1/session` is an alias for `GET /v1/snapshot`. The snapshot currently reports:

- Process, project, lifecycle phase, world UUID, entity count, and editor visibility.
- Active camera UUID, transform, forward vector, clip planes, field of view, and debug view.
- Backend, frame index, physical output dimensions, pixel density, and viewport.
- Draw, visibility, virtual-geometry residency, streaming, transition, and GPU timing counters.

Read `schema_version` before assuming a response shape. Human log messages are not part of the API contract.

## Capture consecutive evidence

Request between one and 16 consecutive published frames:

```sh
curl --request POST \
  --header "Authorization: Bearer $token" \
  --header 'Content-Type: application/json' \
  --data '{"frames":5,"artifacts":["color"]}' \
  "$url/v1/captures"
```

Poll the current job:

```sh
curl --header "Authorization: Bearer $token" \
  "$url/v1/captures/current" | jq
```

A completed job reports `status: "complete"`, the number of captured frames, requested `artifacts`, and a manifest path. Its capture directory contains `frame-0000.json` and the following consecutive snapshots plus `manifest.json`.

The optional `color` artifact captures the final composited WGPU output as `color-0000.png`. In an editor run, this includes the editor chrome and the game viewport exactly as presented. Every PNG uses the same capture-frame number as its JSON snapshot.

Download a completed artifact through the authenticated API:

```sh
curl --header "Authorization: Bearer $token" \
  --output /tmp/scrapbot-color.png \
  "$url/v1/captures/current/artifacts/color-0000.png"
```

Telemetry-only requests may omit `artifacts`. The null backend accepts telemetry captures but fails a request for `color` with an explicit capture error.

Only one capture may be active. A second request receives `409 Conflict`. Values outside the supported frame count are clamped to the safe range.

A capture advances only when the renderer produces a frame. If a window is fully occluded or the platform suspends drawing, the job remains `pending` or `capturing` until rendering resumes.

Color capture performs an explicit GPU readback on each requested frame. This diagnostic work can stall presentation, so live-capture frame timings are evidence about state and ordering rather than representative performance measurements. Use `scrapbot profile` for controlled performance analysis.

## Use CBOR

Scrapbot also accepts and returns deterministic CBOR:

```sh
curl --header "Authorization: Bearer $token" \
  --header 'Accept: application/cbor' \
  --output /tmp/scrapbot-snapshot.cbor \
  "$url/v1/snapshot"
```

Use `Content-Type: application/cbor` for a CBOR capture request. JSON and CBOR represent the same versioned data model.

## Security and execution boundary

The server binds only to `127.0.0.1`, requires its per-process bearer token, rejects requests larger than 64 KiB, and closes each HTTP/1.1 connection after one response.

The network worker never traverses or mutates ECS, resource, renderer, or GPU state. The engine thread publishes immutable snapshots at frame boundaries and consumes bounded capture requests. Remote binding is intentionally unsupported.

WGPU supplies the color provider without exposing its texture or readback buffer to the service or network worker. Depth, meshlet identity, visibility, and other GPU evidence remain additional providers behind the same engine-thread capture plan.
