# ADR-004: Use core:flags for command options

**Date:** 2026-07-07

## Context

Scrapbot will have many CLI commands for project creation, validation, running, editor workflows, headless testing, and build/export tasks. The first implementation used simple manual parsing, which was acceptable for a small skeleton but would not scale cleanly.

## Decision

Dispatch the first CLI token as a Scrapbot subcommand manually, and parse each command's options with Odin's `core:flags` package in Unix style.

## Consequences

Each command gets a typed option struct, command-specific help, positional argument handling, named flags, and consistent parse errors. This keeps the command router simple while avoiding ad hoc option parsing inside each command.

`core:flags` is not a full subcommand framework, so Scrapbot still owns command routing and top-level help. Development through `mise scrapbot` also needs `--` when forwarding Scrapbot's own `--help`, because mise consumes task-level help otherwise.
