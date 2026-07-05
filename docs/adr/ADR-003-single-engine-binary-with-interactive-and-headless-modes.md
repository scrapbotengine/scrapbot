# ADR-003: Single Engine Binary with Interactive and Headless Modes

**Date:** 2026-07-01

## Context

Scrapbot should be usable as an interactive engine/editor and as a command-line tool that can run inside build scripts, tests, CI jobs, and agent workflows. A project should not require separate editor, runner, importer, validator, and build executables with inconsistent behavior.

Agentic workflows particularly benefit from a deterministic binary that can be launched in a project directory, inspect and mutate files, validate project state, run tests, and produce build artifacts without opening a graphical window.

## Decision

Scrapbot is distributed primarily as a single `scrapbot` binary. The binary supports interactive modes such as running a project and launching the editor, and headless modes such as validation, asset import, testing, snapshot rendering, and building.

The current working directory is a first-class project selection mechanism. Commands may also accept explicit project paths.

## Consequences

Users and agents have one tool to learn and automate. Interactive and headless workflows share project loading, validation, asset resolution, scripting, and diagnostics.

The application architecture must separate core engine services from windowing and graphics presentation so that headless commands do not initialize unnecessary platform systems.

Command behavior must remain deterministic enough for CI and agent use. Interactive conveniences cannot become hidden requirements for project correctness.
