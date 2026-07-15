---
name: "bazinga"
description: "Invoke this skill when the user asks you to develop a feature back-to-back, with all the trimmings. This skill defines a full feature development workflow that includes code reviews, branch management, and ends in a fully fleshed-out PR."
---

Hi. We're here to develop a feature, or make a change, that the user has asked you for. We're going to follow a back-to-back workflow that consists of the following steps:

- Environment Setup
- Planning
- Planning Checkpoint
- Loop:
  - Writing code
  - Running tests
  - Code review
- Loop:
  - Publish a Pull Request
  - Watch CI
- Final Report

## The Context File

We're going to track the state of our work in a Markdown file in the gitignored `.context/` directory. Please create this file, use it to jot down any thoughts and notes you want to keep in the context, but most importantly: include a checkbox item list of the above steps, including separate "Planning Checkpoint" and "Watch CI" items, and cross them off as things progress.

## Looping

It is imperative to note that the three steps "Writing Code", "Running tests" and "Code review" are expected to loop until the code review finds no more significant issues with your work.

## The Individual Phases

### Environment Setup

- Make sure you work in a git worktree. The user is likely using an agent orchestrator that will already have set this up for you. Use that worktree directly; do not create a nested worktree. If no worktree or branch scope is available, stop and alert the user.
- Make sure to name the branch something that properly reflects the work being done. Please follow any instructions the user has provided about the naming conventions of these branches. When in doubt, use Conventional Commit style branch names (eg. `fix/...`, `feat/...` etc.)
- Record the base branch, assigned file/surface ownership, and any sibling-agent boundaries in the context file. Do not edit, stage, or commit another agent's files.

### Planning

- Make sure you fully understand the work the user is asking you to do.
- When in doubt, ask the user questions.
- Make sure this work is reflected in a GH issue (or whatever else the user is using for issue tracking.) Remember this GH issue; when you post a PR later, it must reference the issue (so it can be auto-closed when the PR is merged.)
- Jot down any additional details in your context file.
- Inspect the relevant code and docs before making material design choices.

### Planning Checkpoint

- For non-trivial feature work, do not begin implementation immediately after planning. First present a concise implementation brief to the user and call out material choices.
- Treat a change as non-trivial when it affects architecture, persisted data, API shape, permissions, compatibility, user-facing workflows, or documentation commitments.
- The brief should cover intended behavior, data/event/API model, compatibility or migration concerns, UI placement and user flows, expected tests/docs, and any open questions or assumptions.
- Proceed only after the user confirms, or after clearly stating that no material choices are open. Skip this checkpoint only for truly small, low-risk changes or when the user explicitly asks you to proceed without discussion.
- Record the brief and the user's confirmation or the reason for skipping in the context file.

### Writing code

- Write code to implement the requested feature or change as you would normally do.
- Be sure to follow any additional guidance the user may have given you for this.
- Write new tests as you go along, or update existing tests. Please respect the user's preference for tests.
- If the task involves visual work, use a browser or Chrome DevTools MCP to verify your work, in case these are available to you. Also follow any guidance given by design-focused skills and instructions.
- When delegating, partition tasks by ownership boundary and file set. Give one integration owner responsibility for shared registries, generated artifacts, documentation indexes, cross-surface tests, and the final combined diff.

### Running tests

- Run relevant tests before making or pushing commits.
- Avoid running the entire test suite unless you think it's justified. Remember that CI will ultimately run the complete test suite for us.

### Code Review

- If you're working on a branch/in a PR, make a commit before having the review done. This allows us to see how the code evolves across multiple reviews and commits. Create individual commits for each fix you make.
- Perform a review of the changes. Please consult any skills related to this for guidance.
- Address any findings identified in the Code Review.
- Repeat the last three steps, including this one, until the code review comes up empty, or only reports findings you don't find necessary to address.
- Review the integrated branch after delegated changes land. A clean review of isolated agent diffs does not replace the combined cross-surface review.

### Pull Request

- Finally, post a Pull Request with the changes.
- Verify the PR body after creating or editing it.

### Watch CI

- After opening or updating the PR, wait until GitHub has attached checks to the current PR head. If `gh pr checks <pr>` says no checks are reported, wait briefly and poll again; do not treat that as success.
- Watch CI to completion with `gh pr checks <pr> --watch --fail-fast`.
- If CI fails, examine the failure logs, try to fix the error, push your fixes, and repeat the CI watch loop from the new PR head until CI is green.
- Do not send the final completion report until CI is green, or until you clearly report a blocker that prevents CI from being observed or fixed.

### Final Report

- Report to the user what you did. If there were Code Review findings that you decided to not address, inform the user about them, together with an explanation why you decided that way.
- Also include a list of review agent findings that you addressed, but keep it concise. This way the user will know that the workflow actually worked.
- Voice any suggestions for new or changed agent rules/instructions that might have helped you get things right faster, or that you feel will help future agent sessions. Ask the user if they want you to apply these changes.
