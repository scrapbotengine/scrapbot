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
