# Scrapbot Engine Contributing Guide

## This is an Agentic-First Codebase

PRs are welcome, but please be aware that this codebase is designed to be primarily maintained with the help of coding agents. Significant work has been done to make the codebase agent-friendly (agentic rules, skills, guardrails, and more). Please make use of this harness.

- Please use a capable coding agent to implement your changes. ("capable" here means that it reliably picks up the repository's skills and instructions.)
- We assume all PRs opened have been authored by a coding agent. If your PR contains human-typed code, please clearly indicate this in the PR description.
- You may use your coding agent to draft the PR title and body. Please include the motivation for the change, a summary of what changed, and the commands or checks used for verification.
- Either you or your agent must be able to answer review questions. PRs with unresolved review feedback and no response for 3 days may be closed.
- Changes and improvements to the repository's agent skills and instructions are welcome, but please post them as separate PRs.
- Maintainers should follow [`docs/RELEASING.md`](docs/RELEASING.md) when cutting releases.

## Pull Request Checklist

- Read `AGENTS.md` before changing code.
- Use Conventional Commits for commit messages and PR titles.
- Keep related docs, ADRs, FDRs, and `docs/TODO.md` in sync when behavior or follow-up work changes.
- Include the verification commands you ran in the PR body. If you skipped verification, say why.

## Odin Editor Tooling

Run `mise setup` from the repository root to install the pinned Odin compiler, OLS language server, and `odinfmt` formatter and activate the repository's tracked Git hooks. Start your editor from a mise-activated shell, or use `mise x -- <editor>`, so it can find `odin`, `ols`, and `odinfmt` on `PATH`.

OLS reads the repository's `ols.json`, including the checker roots and formatter integration. Editors with built-in LSP support can launch `ols` directly; VS Code users can install the official OLS extension. Enable format-on-save in your editor to apply the shared `odinfmt.json` policy.

Useful commands:

```sh
mise fmt          # Rewrite all Odin files
mise fmt-audit    # Report formatting drift without touching the worktree
mise fmt-staged   # Check the exact Odin content staged for commit
odinfmt path/to/file.odin -w
```

The pre-commit hook runs `mise fmt-staged` and blocks unformatted staged Odin files. It only reads the index, so partially staged files remain intact. Do not bypass it with `--no-verify`.

`mise fmt-audit` is informational until the existing source tree receives a dedicated baseline-format change. After that pass, it can become an enforced format check in `mise test`.
