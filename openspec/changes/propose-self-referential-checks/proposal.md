## Why

Two implementation PRs needed an operator override because an approved task's check could not be met by design (issue #39). In loop-cleanup (PR #33) task 5.2 required the real cleanup dry run to list "exactly" the worktrees of three earlier changes, but the change's own completed propose worktree is correctly listed too. In loop-learnings-2 (PR #37) task 4.2 required a real `loop-start.sh --dry-run implement <change>` to exit 0, which is impossible for the change itself once its own builder worktree exists (the launcher refuses with exit 6). The judge rightly treated both unmet tasks as blocking; the defect is in how the checks were written.

## What Changes

- `.agents/loop/propose.md` gains a rule for writing task checks: a check that runs a loop launcher or cleanup for real (`loop-start.sh` implement, judge, archive, amend or cleanup, or `loop-launch.sh`) accounts for the change's own workers, which exist while the change is built and judged. Such a check names the expected refusal (for example exit 6 because `<change-name>-impl` exists), targets state the change does not create, or is covered by a stub simulation instead. An "exactly these" list of worktrees, PRs or branches states whether the change's own appear in it.
- `docs/dev-loop.md` states the same rule briefly under the propose step, citing PRs #33 and #37 as the examples.
- `.agents/loop/judge.md` is unchanged: a task that cannot be met stays blocking, and the operator settles it with amend.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `development-loop`: new requirement "Task checks account for the change's own workers".

## Impact

- Changed (implementation PR): `.agents/loop/propose.md`, `docs/dev-loop.md`.
- `openspec/specs/development-loop/spec.md` at archive time.
- Out of scope: scripts (including `loop-start.sh`, `loop-prompt.sh` and the tests), CI (`.github/`), the other templates (apply, judge, fix, amend, archive) and `.agents/loop/README.md`, Orca.

## Open questions

- **Placement in `propose.md`.** The brief does not say where the rule goes. This change appends it to step 2, right after "Every task carries a check that can be verified.", because that is where task checks are written; no step is renumbered.
- **Placeholders in the template.** `propose.md` is filled by `loop-prompt.sh`, which treats every `<key>` as a launch-time placeholder. The rule therefore names the change's workers with the documented key `<change-name>` (`<change-name>`, `<change-name>-impl`, `<change-name>-judge[-N]`, `<change-name>-amend[-N]`, `<change-name>-archive`), never `<change>`, so the prompt still fills with its documented keys and no placeholder is left.
- **Project-agnostic template.** The loop templates are portable, so `propose.md` does not cite PRs #33 and #37 or name this repository; only `docs/dev-loop.md` cites them.
- **`.agents/loop/README.md` and `amend.md`.** The brief names only `propose.md` and `docs/dev-loop.md`. The README's portable summary and the amend template, whose worker may also add tasks, are not changed; extending the rule to them is a follow-up.
- **Existing changes.** The rule applies to tasks written after this change ships. Archived changes are not edited.
