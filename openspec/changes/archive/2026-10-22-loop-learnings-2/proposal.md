## Why

Building the `sdd-loop` skill and the cleanup verb (issues #26 and #31, PRs #29 and #33) showed three defects in the loop kit (issue #35). `loop-start.sh` finds spec and implementation PRs through GitHub's eventually consistent search index, so `implement` refused with exit 3 a minute after the spec PR merged. A judge finding about the approved change's own wording had no verifiable way to reach the judge: the operator's decision, quoted by the builder in PR #33's body, was rightly refused by the re-judge, and the PR needed an operator override on GitHub. `spec-length.sh` uses `mapfile` and fails on macOS's bash 3.2.

## What Changes

- `loop-start.sh` finds PRs by exact title with `gh pr list --state all --limit 200 --json …` (no `--search`) and filters titles locally; the refusal codes stay the same. `scripts/test-loop-start.sh` gains stub scenarios, one of them with a stale search index (a `--search` call that would not return the just-merged PR).
- New verb `amend <change>: <what to change>` in the `sdd-loop` skill and `loop-start.sh amend <change> --brief <text>`. It launches a worker `<change>-amend` (or the lowest free `<change>-amend-<N>` from 2) from the new template `.agents/loop/amend.md`. The worker edits only `openspec/changes/<change>/` (proposal, design, specs and task wording, never a checkbox), opens a draft spec-only PR titled `amend: <change>` with `Kind: spec`, and waits at `in-review` for the operator's `approve <sha>` like a spec PR. Once it merges, the judge reads the amended change from `origin/main` as it already does.
- `loop-start.sh status` lists open `amend:` PRs and gives them the same approve action as spec and archive PRs; `cleanup` counts `<change>-amend` and `<change>-amend-<N>` as loop worker names.
- `docs/dev-loop.md` and `.agents/loop/README.md` describe amend as the way to settle a judge finding about the approved change itself, and state that a judge does not accept an operator decision quoted in a PR body, comment or other agent output; only a merged change on `origin/main` is the operator's decision about the change.
- `scripts/spec-length.sh` works on bash 3.2 (no `mapfile` or other bash 4 builtins); `scripts/test-spec-length.sh` keeps its scenarios and expectations.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `development-loop`: new requirements "Launcher finds PRs without the search index", "Amend changes an approved change through a spec-only PR", "Amend worker changes only the change's wording", "Amend is reproducible", "Loop documentation describes amend" and "Length check runs on bash 3.2"; modified requirements "Operator starts loop steps through the sdd-loop skill" (adds `amend`), "Launcher derives launch-time values from GitHub" (exact-title lookup, amend values), "Launcher uses the documented worker layout" (amend worker), "Launcher refuses what it cannot derive" (amend refusals, exit 9), "Status names where the operator acts" (amend PRs) and "Cleanup removes only finished loop worktrees" (amend worker names).

## Impact

- Changed (implementation PR): `scripts/loop-start.sh`, `scripts/test-loop-start.sh` (new scenarios; its PR stub learns to answer `--search` calls with a stale list, which the approved change names here), `scripts/spec-length.sh`, new `.agents/loop/amend.md`, `.agents/loop/README.md`, `.claude/skills/sdd-loop/SKILL.md`, `.agents/skills/sdd-loop/SKILL.md`, `docs/dev-loop.md`. `scripts/test-spec-length.sh` is not changed.
- `openspec/specs/development-loop/spec.md` at archive time.
- Out of scope: Orca, CI (`.github/`), `loop-merge.sh`, the behaviour of the other templates (propose, apply, judge, fix, archive), `loop-prompt.sh`, `loop-await.sh`, `loop-status.sh`, `loop-launch.sh`, deleting remote branches.

## Open questions

- **Amend CLI shape.** The brief gives the skill form `amend <change>: <what to change>` and names `loop-start.sh amend`. This change uses `loop-start.sh amend <change> --brief <text>`, mirroring `start … --brief`; the text is required and must not be blank (exit 2). In the template the text fills the key `amendment`, not `brief`, because `loop-prompt.sh` treats `brief` as an intake key.
- **Amend preconditions and exit codes.** Amend needs the change approved and not yet archived. It looks up the merged PR titled exactly `spec: <change>` with the same lookup as implement (exit 3 if none, or if its body has no `Refs #<N>` line; the issue number comes from it), and then requires `openspec/changes/<change>/` on `origin/<default branch>` (new exit 9 if absent, for example after archive). An open implementation PR is not required: an amendment may also come before implement starts.
- **Amend worker name.** Several amendments of one change are possible, so the name follows the judge pattern: `<change>-amend`, else the lowest free `<change>-amend-<N>` from 2, with the same name-taken check. Agent `claude`, base `origin/<default branch>`.
- **Status and cleanup.** The brief does not mention them. Without them an `amend:` PR waiting for approval would not appear in `status`, and finished amend worktrees would be kept by cleanup as `not a loop worker name` forever. Both are in `loop-start.sh`, which the brief puts in scope, so this change extends them; Orca itself is not touched.
- **"Never ticks".** An amendment changes no checkbox state: the count of checked `- [x]` tasks in `tasks.md` is the same before and after, and any task it adds is unchecked. Editing the wording of a ticked task is allowed.
- **Implementation branch after an amendment.** The open implementation branch predates the amendment. The judge already reads the change from `origin/main`, so no judge change is needed. If the amendment edits `tasks.md` and the implementation PR then conflicts, the builder merges `origin/main` into its branch as a change request (the spec lock compares against the merge base, so the amended wording does not count as an edit by the implementation PR). An amendment is not a fix round and does not change the `Verdict: BLOCKING` count.
- **List limit.** `--limit 200` covers this repository (35 PRs on 2026-10-22). When the list returns exactly 200 PRs and no PR has the exact title, the refusal says that only the newest 200 PRs were searched, so a miss beyond the window is not mistaken for a missing PR. Paging is not added.
- **Other bash 4 uses.** `loop-start.sh` (cleanup's `mapfile`) and `loop-prompt.sh` (`declare -A`) also need bash 4. The brief names only `spec-length.sh`; the others are left unchanged and recorded here as a follow-up.
- **Bash 3.2 verification.** No bash 3.2 is installed on the Linux worker. The check runs `scripts/test-spec-length.sh` inside the `bash:3.2` container image if Docker can pull it; if it cannot, the PR says so under "Not done / not run" and only the absence of bash 4 builtins is checked.
