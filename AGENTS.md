# Scrapbot Agent Guide

Scrapbot is an experimental, text-first game engine written in Odin with embedded Luau for project-local scripting. This file is the authoritative home for rules agents must follow before changing code. ADRs, FDRs, and skills are further reading, not replacements for these rules.

## Features

Please refer to the `README.md` for a high-level overview of the engine's features and roadmap. Detailed features, design decisions, and implementation details are documented in ADRs and FDRs in `docs/adr/` and `docs/fdr/`.

## Project Status

- This project is in super-early development.
- Breaking changes are 100% acceptable and we don't need to make changes backward-compatible unless specifically requested by the user.

## Agent Diagnostics

Prefer Scrapbot's structured CLI output when inspecting projects or verifying changes:

```sh
bin/scrapbot check <path> --json
bin/scrapbot build <path> --json
bin/scrapbot run <path> --frames <n> --json
```

- Treat `ok`, diagnostic `code`, and documented `result` fields as the automation contract.
- Branch on diagnostic codes and structured fields, never exact human-readable message text.
- Do not parse human CLI output when `--json` is available.
- Expect exactly one JSON document on stdout. Use `schema_version` before assuming an envelope shape.
- Keep automated runs bounded with `--frames`.
- Use a headless WGPU framegrab when correctness depends on rendered output; structured diagnostics do not replace visual verification.
