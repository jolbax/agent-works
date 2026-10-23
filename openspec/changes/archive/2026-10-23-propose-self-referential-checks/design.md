## Context

See proposal.md (Why). Step 2 of `.agents/loop/propose.md` ends with "Every task carries a check that can be verified." and says nothing about checks that run the loop's own launcher. A change to the loop kit is built and judged while its own workers exist: the propose worktree `<change-name>` (status `completed` once its spec PR merged), the builder `<change-name>-impl`, the judges `<change-name>-judge[-N]` and, if amended, `<change-name>-amend[-N]`. `loop-start.sh` refuses a launch whose worker name is taken (exit 6), and `cleanup` lists every Orca worktree of the repository, including these. `scripts/loop-prompt.sh` replaces every `<key>` in a template and exits 1 on any it was not given; `scripts/test-loop-prompt.sh` fills `propose.md` with `owner`, `repo`, `change-name` and either `issue-number` or `brief`.

## Goals / Non-Goals

**Goals:**
- Tasks written by the propose worker can be met by the change's own builder, so the judge's blocking verdict on an unmet task reflects a real defect.

**Non-Goals:**
- Changing the judge's handling of unmet tasks, any script or test, or the other templates.

## Decisions

1. **Rule text in `propose.md`.** Append to step 2, after "Every task carries a check that can be verified.", wording to this effect: "A check that runs a loop launcher or cleanup for real (`loop-start.sh` implement, judge, archive, amend or cleanup, or `loop-launch.sh`) runs while this change's own workers exist (`<change-name>`, `<change-name>-impl`, `<change-name>-judge[-N]`, `<change-name>-amend[-N]`): it names the expected refusal (for example exit 6 because `<change-name>-impl` exists), targets state this change does not create, or is covered by a stub simulation instead. An "exactly these" list of worktrees, PRs or branches states whether this change's own appear in it." Only the documented key `<change-name>` appears in angle brackets, so `loop-prompt.sh` fills it and leaves no placeholder. Alternative: a new numbered step. Rejected: it renumbers steps that docs and workers refer to, for a rule that belongs to writing tasks.

2. **Project-agnostic template, project examples in the docs.** `propose.md` does not cite PRs or name the repository. `docs/dev-loop.md` adds, under "### 2. Propose", a short paragraph with the same rule and the two examples: PR #33 (task 5.2, the cleanup dry run's "exactly" list missed the change's own completed propose worktree) and PR #37 (task 4.2, a real `--dry-run implement` of the change itself, refused with exit 6 because its builder worktree existed).

3. **Judge unchanged.** `.agents/loop/judge.md` keeps treating an unmet task as blocking; the dev-loop paragraph says the operator settles a task that cannot be met with amend, as the existing "Settling a finding about the approved change" procedure describes. Alternative: let the judge waive self-referential checks. Rejected: the judge would then interpret the approved change instead of checking it.

4. **This change's own checks.** Following the rule, no task here runs the launcher or cleanup for real. The confinement check compares the implementation branch with `origin/main`, where this change's directory already is after its spec PR merged, so the expected paths are the two edited files and this change's `tasks.md` ticks.

## Risks / Trade-offs

- [A future template edit adds a `<change>` token to the rule] → `scripts/test-loop-prompt.sh` already fails on an unfilled placeholder in `propose.md`.
- [The rule names the launcher verbs; a new verb is added later] → the rule says "a loop launcher or cleanup for real" before the list, so the list reads as examples of the class; a new verb's change can extend it.
- [The rule does not reach `amend.md`] → recorded in proposal.md (Open questions) as a follow-up.

## Migration Plan

None: wording in one template and one document. Rollback is a revert of the implementation PR.
