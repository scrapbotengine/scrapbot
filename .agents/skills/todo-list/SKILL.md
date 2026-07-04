---
name: todo-list
description: Establish and maintain a lightweight project task list in docs/TODO.md. Use when the user asks to track todos, maintain a TODO.md, preserve follow-up work while implementing features, or keep an agent-readable list of outstanding project tasks.
---

# Todo List

Maintain `docs/TODO.md` as the project's concise list of outstanding work.

## Core Rules

- Store the list at `docs/TODO.md`. Create `docs/` if needed.
- Use one todo per line in GitHub Flavored Markdown task syntax:

```markdown
- [ ] Short task description
```

- Keep each task short enough to scan. Put details, discussion, acceptance criteria, screenshots, logs, and implementation notes in an external system such as GitHub issues, Linear tickets, ADRs, FDRs, or docs, then link from the task when useful.
- Do not duplicate a full issue tracker. `docs/TODO.md` is an index of outstanding work, not the place where the work is specified in depth.
- Preserve user wording when reasonable, but normalize formatting and remove duplicates.
- Prefer current outstanding tasks only. Remove tasks once they are completed unless the user explicitly asks for completed-task history.

## Workflow

1. Read `docs/TODO.md` before editing it if it exists.
2. Create the file when the user asks for todo tracking or when this skill is invoked and no file exists.
3. Add or update tasks as new follow-up work is discovered during planning, implementation, review, or verification.
4. Remove completed tasks as the work is finished. If a partially completed task still has remaining work, rewrite it to describe only the remaining work.
5. Re-read the final file before finishing and verify that every todo line is short, actionable, and formatted as `- [ ]`.

## Sections and Milestones

Use optional second-level headings when the user requests grouping or when an existing file already has groups:

```markdown
# TODO

## Milestone Name

- [ ] Add the missing export button ([issue](https://example.com))
- [ ] Document the retry behavior
```

Keep section names user-facing and stable. Avoid creating elaborate hierarchies; use only `##` headings unless the user asks for more structure.

## Task Wording

Good tasks:

- `- [ ] Add tests for failed webhook retries`
- `- [ ] Link billing export work to the GitHub issue`
- `- [ ] Decide whether archived projects appear in search`

Avoid tasks that are too vague or too detailed:

- `- [ ] Fix stuff`
- `- [ ] Implement the entire multi-step database migration plan with all edge cases described inline`

## Agent Maintenance

When working on features, keep `docs/TODO.md` synchronized with reality. Capture legitimate follow-up work instead of burying it in chat, and remove tasks that your current work resolves. Mention material TODO changes in the final response when they affect what remains to do.
