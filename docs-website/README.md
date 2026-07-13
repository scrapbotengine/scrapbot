# Scrapbot Documentation Website

[![Built with Starlight](https://astro.badg.es/v2/built-with-starlight/tiny.svg)](https://starlight.astro.build)

This is the Astro Starlight documentation site for Scrapbot.

## Project Structure

Documentation pages live in `src/content/docs/`:

```text
.
├── public/
├── src/
│   ├── assets/
│   ├── content/
│   │   └── docs/
│   ├── styles/
│   └── content.config.ts
├── astro.config.mjs
├── package.json
└── tsconfig.json
```

Starlight looks for `.md` or `.mdx` files in the `src/content/docs/` directory. Each file is exposed as a route based on its file name.

## Commands

Run commands from `docs-website/`:

| Command                   | Action                                           |
| :------------------------ | :----------------------------------------------- |
| `pnpm install`             | Installs dependencies                            |
| `pnpm dev`                 | Starts local dev server at `localhost:4321`      |
| `pnpm build`               | Builds the static site into `./dist/`            |
| `pnpm preview`             | Previews the built site locally                  |
| `pnpm astro ...`           | Runs Astro CLI commands                          |

## Development Notes

- Keep source-of-truth design decisions in the repository `docs/adr/` and `docs/fdr/` records.
- Use the website for reader-facing guides and reference material.
- Run `pnpm build` before committing docs site changes.
