# Proposal

## Why

agent-works is built with a spec-driven loop (Orca worktrees, OpenSpec, GitHub PRs, CI spec lock), but the loop exists only as bootstrap files from PR #1 and the operator's head. Nothing says who does what, what approval means, or what a judge must check, and none of it can be copied to another Orca-hosted project. Documenting it as a portable kit now makes the rules testable before the first implementation change relies on them.

This concerns how agent-works is *developed*. It is not product design: the factory's changes, stage attempts and approvals in `docs/architecture.md` are a separate subject, and the loop's files must not be mistaken for them.

## What Changes

- Add `docs/dev-loop.md`: the loop (setup, intake, propose, approve, implement, judge, ship, archive), roles, the eight rules, the exact `orca-ide` / `openspec` / `gh` commands per step, failure handling, and a "Reuse in another Orca project" checklist (what to copy, what to adapt, what the operator does in the GitHub UI).
- Add `.agents/loop/`: project-agnostic prompt templates with `<placeholders>` (`propose.md`, `apply.md` with the MUST-NOT list, `judge.md`, `fix.md`, `archive.md`) and a `README.md` mapping each to its step and command.
- Add `.github/ISSUE_TEMPLATE/change.md` and `.github/pull_request_template.md`.
- Add `scripts/test-spec-lock.sh`, which reproduces the spec-lock scenarios in a throwaway git repo and fails if any behaves wrongly.
- Edit `AGENTS.md`: replace the workflow paragraph under "Repository and change workflow" with a short pointer to `docs/dev-loop.md`; keep every existing rule.
- Add the OpenSpec capability `development-loop`, whose requirements are the rules above with testable scenarios.

Deliberately not used: hooks, multi-reviewer fan-out, adversarial verification waves, a project board, hash-bound approvals, a long-waiting Orca gate, a coordinator agent for small changes.

## Capabilities

### New Capabilities
- `development-loop`: how a change moves from intake to archive in this repository: approval by merged spec PR, the spec lock, the config-change rule, an independent judge, fix-round limit, operator-only merge, and the portable kit that carries the loop to other projects.

### Modified Capabilities

None. `openspec/specs/` holds no capabilities yet.

## Impact

- New: `docs/dev-loop.md`, `.agents/loop/*`, `.github/ISSUE_TEMPLATE/change.md`, `.github/pull_request_template.md`, `scripts/test-spec-lock.sh`.
- Edited: `AGENTS.md` (workflow paragraph only).
- Unchanged: `.github/workflows/ci.yml` (agents' token cannot edit it), `scripts/spec-lock.sh`, `openspec/config.yaml`, all product docs, and decisions D1–D6. No product code, no new dependencies.
- Files under `.github/` trigger the spec-lock config NOTE; the judge must justify them against this change.
- Operator task, outside this change: optionally wire `bash scripts/test-spec-lock.sh` into `.github/workflows/ci.yml`.

## Open questions

- Should CI run `scripts/test-spec-lock.sh`? Only the operator can edit the workflow. Until then the script is run by the builder and re-run by the judge, and the PR evidence says so.
- The issue records no decision on which Claude/Codex models or effort levels workers use (`--model`, `--effort` exist on `orca-ide worktree create`). The templates leave them to the operator's defaults.
