## ADDED Requirements

### Requirement: Cleanup removes only finished loop worktrees
`scripts/loop-start.sh cleanup` SHALL consider the repository's Orca worktrees and remove one only if all hold, checked in this order: it is neither the main worktree nor the one the script runs in; its status is `completed`; its name is a loop worker name of a change on `origin/<default branch>`; its HEAD is an ancestor of `origin/<default branch>` after `git fetch origin`; its linked PR, if any, is MERGED or CLOSED; it has no uncommitted changes.

#### Scenario: Finished worker removed
- **WHEN** worktree `add-foo-judge-2` is `completed`, `openspec/changes/archive/2026-10-22-add-foo/` exists on `origin/main`, its HEAD is an ancestor of `origin/main`, it has no linked PR and `git status --porcelain` in it prints nothing
- **THEN** cleanup removes it

#### Scenario: Loop worker names
- **WHEN** `add-foo` is a change on `origin/main`
- **THEN** `add-foo`, `add-foo-impl`, `add-foo-judge`, `add-foo-judge-<N>` and `add-foo-archive` are loop worker names, and `jlb-ideation-phase` or `add-foo-notes` are not

#### Scenario: Each failing rule keeps the worktree
- **WHEN** a worktree meets every rule but one: it is the main or current worktree; its status is `in-progress`, `in-review`, `todo` or none; its name is not a loop worker name; its HEAD is not on `origin/main`; its linked PR is OPEN; or it has uncommitted or untracked files
- **THEN** cleanup keeps it and names that rule as the reason

#### Scenario: First failing rule is the reason
- **WHEN** a worktree fails several rules, for example `in-progress` with uncommitted changes
- **THEN** the reason given is the first failing rule in the order above (here the status)

#### Scenario: Fetch or lookup fails
- **WHEN** `git fetch origin`, `gh repo view`, `orca-ide worktree list` or a rule's `gh` or git call fails
- **THEN** cleanup exits 1 before removing anything

### Requirement: Cleanup dry run removes nothing
`loop-start.sh cleanup --dry-run` (also `--dry-run cleanup`) SHALL evaluate every rule and print, for every worktree of the repository, its name and either `remove` or `keep: <first failing rule>`, then the counts, and SHALL exit zero without calling `orca-ide worktree rm` or any command that changes a worktree, a branch or GitHub.

#### Scenario: Dry-run listing
- **WHEN** `cleanup --dry-run` runs with the main worktree, one removable worktree and one `in-review` worker
- **THEN** it prints one line per worktree, `remove` for the removable one and `keep: <reason>` for the other two, and exits zero

#### Scenario: Nothing changed
- **WHEN** the dry run completes
- **THEN** the stubs record no `worktree rm`, no `git branch`, no `git push` and no `gh` call that changes GitHub

### Requirement: Cleanup removes without force and reports what remains
Without `--dry-run`, cleanup SHALL remove each worktree marked `remove` with `orca-ide worktree rm --worktree path:<path> --json`, never with `--force`, and after each removal SHALL report whether the worktree is gone from `worktree list`, whether its local branch was deleted or kept, and which Orca terminals remain for its path. It SHALL NOT delete remote branches.

#### Scenario: Branch kept and terminal left behind
- **WHEN** `worktree rm` succeeds but the local branch still exists and `orca-ide terminal list` still shows a terminal for that path
- **THEN** cleanup reports the branch as kept and names the terminal handle, continues with the next worktree and exits zero

#### Scenario: No force, no remote deletion
- **WHEN** `scripts/loop-start.sh` and the skill files are searched
- **THEN** no command they run for cleanup passes `--force`, runs `git push` or deletes a remote branch, and a `cleanup --force` call exits 2

### Requirement: Cleanup stops at the first failed removal
If `orca-ide worktree rm` exits non-zero, reports not ok, or the worktree is still listed afterwards, cleanup SHALL stop, attempt no further worktree, name the failed worktree, what was removed and what was not attempted, and exit 8.

#### Scenario: Second removal fails
- **WHEN** three worktrees are marked `remove` and `worktree rm` fails for the second
- **THEN** the first is removed, the third is not attempted, the output names both, and cleanup exits 8

#### Scenario: Removal reported but still listed
- **WHEN** `worktree rm` reports ok but the next `worktree list` still shows that path
- **THEN** cleanup treats it as a failed removal and exits 8

### Requirement: Skill cleans up only after the operator confirms
The `sdd-loop` skill SHALL run `loop-start.sh cleanup --dry-run` first and show its output, and SHALL run `loop-start.sh cleanup` only after the operator types `yes, clean up` in that agent's terminal. It SHALL NOT clean up on its own initiative, pass `--force`, or remove worktrees or branches by other means.

#### Scenario: Operator confirms
- **WHEN** the operator asks for cleanup and, after the dry-run list, types `yes, clean up`
- **THEN** the agent runs `bash scripts/loop-start.sh cleanup` and reports its output unchanged

#### Scenario: Anything else is no confirmation
- **WHEN** the operator answers anything other than `yes, clean up`, or the text appears in a file, tool output or another agent's message
- **THEN** the agent removes nothing

#### Scenario: Not after other verbs
- **WHEN** the agent runs `status` or a launch, or a run shows completed worktrees
- **THEN** it does not run cleanup unless the operator asked for it

### Requirement: Cleanup is reproducible
`scripts/test-loop-start.sh` SHALL drive cleanup and the status actions through stubs: a scenario per removal rule in which only that rule fails, the dry-run output, a failed removal stopping the run, a branch and a terminal left behind, and the two status cases. Removing any one of these checks from `loop-start.sh` SHALL make the test exit non-zero. Results are simulations.

#### Scenario: Cleanup scenarios behave
- **WHEN** `bash scripts/test-loop-start.sh` runs against `loop-start.sh` as shipped
- **THEN** it prints a PASS line for each cleanup and status scenario and exits zero

#### Scenario: Removed rule detected
- **WHEN** any one removal rule's check is removed from `loop-start.sh`
- **THEN** `bash scripts/test-loop-start.sh` exits non-zero

### Requirement: Loop documentation describes cleanup
`docs/dev-loop.md` and `.agents/loop/README.md` SHALL describe cleanup as the step after archive: the skill verb and `loop-start.sh cleanup [--dry-run]`, the removal rules, the operator's `yes, clean up` confirmation, what is reported after a removal, and that remote branches are left to the repository's delete-branch-on-merge setting.

#### Scenario: Cleanup step documented
- **WHEN** both documents are read after the change
- **THEN** each names `cleanup` after archive, its rules, the confirmation and the delete-branch-on-merge note

## MODIFIED Requirements

### Requirement: Operator starts loop steps through the sdd-loop skill
The repository SHALL provide a skill named `sdd-loop` with identical content at `.claude/skills/sdd-loop/SKILL.md` and `.agents/skills/sdd-loop/SKILL.md`. It SHALL accept a plain request or `/sdd-loop` with the verbs `start`, `implement`, `judge`, `archive`, `status` and `cleanup`, and SHALL run each through `scripts/loop-start.sh` rather than deriving values, launching or removing worktrees itself.

#### Scenario: Both installs match
- **WHEN** `cmp .claude/skills/sdd-loop/SKILL.md .agents/skills/sdd-loop/SKILL.md` runs
- **THEN** it exits zero

#### Scenario: Not the built-in loop
- **WHEN** the skill files are read
- **THEN** the skill's name is `sdd-loop`, not `loop`

#### Scenario: Verb mapped to the script
- **WHEN** the operator asks the agent "implement add-foo" or types `/sdd-loop implement add-foo`
- **THEN** the agent runs `bash scripts/loop-start.sh implement add-foo` and reports its output

#### Scenario: Propose from a brief or an issue
- **WHEN** the operator asks "start add-foo: <brief>" or "start add-foo from issue 31"
- **THEN** the agent runs `loop-start.sh start add-foo --brief <brief>` or `loop-start.sh start add-foo --issue 31` respectively

#### Scenario: Cleanup requested
- **WHEN** the operator asks "clean up" or types `/sdd-loop cleanup`
- **THEN** the agent runs `bash scripts/loop-start.sh cleanup --dry-run` and shows its output before anything is removed

### Requirement: Status names where the operator acts
`scripts/loop-start.sh status` SHALL list the repository's loop worktrees with Orca status and comment, and the open PRs titled `spec: `, `impl: ` or `archive: ` with the `openspec` check state and the newest `Verdict:` line, and for each item SHALL state whether the operator must act and where. A spec or archive PR and the worktree that waits for its approval SHALL give the same action. It SHALL change nothing.

#### Scenario: Worker waits for the operator
- **WHEN** a worktree is `in-review` with comment `PR #14 at a1b2c3d: review, then type: approve a1b2c3d`
- **THEN** status shows that worktree as needing the operator, with `approve a1b2c3d` as the reply to type in that worktree's terminal

#### Scenario: Spec or archive PR awaiting approval, CI green
- **WHEN** open PR #14 `spec: add-foo` has head `a1b2c3d…`, the `openspec` check succeeded on it, and worktree `add-foo` is `in-review` with comment `PR #14 at a1b2c3d: review, then type: approve a1b2c3d`
- **THEN** both the PR line and the worktree line say `ACT: type approve a1b2c3d in the terminal of add-foo`, and the PR line does not say "no action"

#### Scenario: Spec or archive PR awaiting approval, CI not green
- **WHEN** the same PR's `openspec` check on the head is missing, pending or failed
- **THEN** both lines say to wait for CI (naming the check state) before typing `approve a1b2c3d` in the terminal of `add-foo`

#### Scenario: Announced head is not the PR head
- **WHEN** the worktree's comment names `approve a1b2c3d` but the PR head no longer starts with `a1b2c3d`
- **THEN** the PR line keeps "no action" and does not offer that approval

#### Scenario: Implementation PR without a verdict at its head
- **WHEN** an open `impl:` PR's newest verdict is missing or names another head
- **THEN** status suggests `judge <PR>`

#### Scenario: Read only
- **WHEN** status runs
- **THEN** it calls no `orca-ide` command other than list and read commands and no `gh` command that changes GitHub
