# Scrapbot Documentation Website

This is the Astro Starlight documentation site for Scrapbot Engine.

## Development

Install dependencies from the checked-in lockfile:

```sh
pnpm install
```

Start the local docs server in the background:

```sh
pnpm astro dev --background
```

Build the static site:

```sh
pnpm run build
```

## Content

Documentation pages live in `src/content/docs/`.

The current site is organized around:

- Getting started
- Core concepts
- Scripting and native code
- Rendering and UI
- Workflow
- Reference

When updating engine behavior, keep these docs aligned with source, ADRs, FDRs, examples, and CLI output.
