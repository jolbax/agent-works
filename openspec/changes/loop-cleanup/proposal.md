## Why

Every finished change leaves its Orca worktrees and idle agent sessions behind: propose, implement, one or more judges and archive, four or five per change. Nothing in the loop removes them, so the worktree list and the terminal tabs grow with every change (issue #31). While dogfooding the `sdd-loop` skill, `status` also said "no action" on a spec or archive PR whose worker was waiting for `approve <sha7>`, and offered that approval while CI was not yet green, when `loop-merge.sh` would refuse it with exit 5.

## What Changes

- New verb `scripts/loop-start.sh cleanup [--dry-run]` (also `--dry-run cleanup`) and the skill verb `cleanup`. It looks at the repository's Orca worktrees and removes one only if all of these hold: it is not the main worktree (nor the worktree the script runs in); its status is `completed`; its name is a loop worker name of a change known on the default branch (`<change>`, `<change>-impl`, `<change>-judge`, `<change>-judge-<N>`, `<change>-archive`); its HEAD is an ancestor of `origin/<default branch>` after `git fetch origin`; its linked PR, if any, is MERGED or CLOSED; it has no uncommitted changes.
- `--dry-run` prints, for every worktree, `remove` or `keep: <first failing rule>`, and removes nothing.
- The real run removes each worktree with `orca-ide worktree rm --worktree path:<path> --json`, never with `--force`, and afterwards reports per worktree whether it is gone from `worktree list`, whether its local branch was deleted or kept, and which Orca terminals remain for its path. It stops at the first failed removal and exits non-zero. It never deletes remote branches; the repository has delete-branch-on-merge on.
- The skill always runs `cleanup --dry-run` first, shows the list, and runs the real cleanup only after the operator types "yes, clean up" in that agent's terminal. It never cleans up on its own initiative.
- `status` fix: for an open `spec:` or `archive:` PR whose worker is `in-review` with "review, then type: approve <sha7>", the PR line gives the same action as the worktree line, `ACT: type approve <sha7> in the terminal of <worktree>`, instead of "no action". While the required check is not green on the PR head, both lines say to wait for CI first.
- `scripts/test-loop-start.sh` gains stub scenarios for every removal rule, the dry-run output, a failed removal stopping the run, a branch or terminal left behind, and the two status cases; each new check is guarded.
- `docs/dev-loop.md` and `.agents/loop/README.md` gain a cleanup step after archive, the rules and the delete-branch-on-merge note.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `development-loop`: new requirements "Cleanup removes only finished loop worktrees", "Cleanup dry run removes nothing", "Cleanup removes without force and reports what remains", "Cleanup stops at the first failed removal", "Skill cleans up only after the operator confirms", "Cleanup is reproducible" and "Loop documentation describes cleanup"; modified requirements "Operator starts loop steps through the sdd-loop skill" (adds the `cleanup` verb) and "Status names where the operator acts" (spec/archive PR action and CI wait).

## Impact

- Changed (implementation PR): `scripts/loop-start.sh`, `scripts/test-loop-start.sh`, `.claude/skills/sdd-loop/SKILL.md`, `.agents/skills/sdd-loop/SKILL.md`, `docs/dev-loop.md`, `.agents/loop/README.md`.
- `openspec/specs/development-loop/spec.md` at archive time.
- Removes Orca worktrees and, through Orca, local branches and worktree directories, but only on the real run after the operator's confirmation. Remote branches are untouched.
- Out of scope: deleting remote branches; the templates' worker behaviour, `loop-merge.sh`, `loop-status.sh`, `loop-await.sh`, `loop-launch.sh`, `loop-prompt.sh`, CI and Orca. The real cleanup of the existing worktrees is not a task of this change; it is an operator action after this change's archive is merged.

## Open questions

- **`<change>` matches any kebab-case name.** The bare pattern `<change>` would match a non-loop worktree such as `jlb-ideation-phase`. This change counts a name as a loop worker name only if `<change>` is a change on `origin/<default branch>`: a directory `openspec/changes/<change>/` or `openspec/changes/archive/<YYYY-MM-DD>-<change>/`. A completed non-loop worktree is therefore kept with `keep: not a loop worker name`.
- **Order of the rules.** "First failing rule" needs an order. This change checks: main or current worktree, status, name, HEAD merged, linked PR, uncommitted changes (the brief's order, with the main-worktree rule first). The rules are evaluated again immediately before each removal, so a worktree that changed after the dry run is kept.
- **The worktree the script runs in.** The brief does not say. Removing the caller's own worktree would delete its working directory mid-run, so it is always kept (`keep: current worktree`).
- **Selector.** `worktree rm` takes `path:<path>` with the path from `worktree list`, the only selector that is unique per worktree without depending on display names or branch prefixes.
- **Branch and terminals after removal.** Orca's help says removal attempts to delete the checked-out local branch and keeps branches it cannot prove merged. The script only reports the branch (deleted or kept) and the remaining terminals; it deletes no branch and closes no terminal itself. A kept branch or a remaining terminal is reported, not a failure, and does not stop the run.
- **Exit codes.** 0 when the dry run or every removal finished (even with branches or terminals reported as left behind); 1 when a `gh`, git or Orca call before any removal fails; 8, new, when a removal fails (`worktree rm` exits non-zero or reports not ok, or the worktree is still listed afterwards), after which no further worktree is attempted.
- **Which PR lines get the approve action.** The brief names spec and archive PRs. The worker's worktree is the one whose `linkedPR` is the PR, or else whose comment names `PR #<N>`. The PR line shows the action only when the comment's `<sha7>` is a prefix of the PR head; otherwise it keeps "no action", because `loop-merge.sh` would refuse that approval with exit 4. Implementation PRs keep the existing judge logic.
- **"Green".** The required check (`LOOP_REQUIRED_CHECK`, default `openspec`) is green when its latest run on the head succeeded, the condition under which `loop-merge.sh` does not exit 5. Missing, pending and failed all mean "wait for CI".
- **Count in the brief.** The brief says 13 completed worktrees; on 2026-10-22 `worktree list` shows 14 completed loop worktrees of the three merged changes (5 for reject-blank-status-message, 5 for harden-loop-handoffs, 4 for add-sdd-loop-skill). The acceptance check uses the list at the time of the run, not a fixed count.
