## ADDED Requirements

### Requirement: Launcher finds PRs without the search index
`scripts/loop-start.sh` SHALL find the PR for `implement`, `archive` and `amend` by listing the repository's PRs in every state, newest first, up to 200, without `gh`'s `--search` option, and SHALL keep only PRs whose title equals the required title exactly. A PR merged just before the launch SHALL be found even while GitHub's search index does not yet show it.

#### Scenario: Implement right after the spec merged
- **WHEN** `loop-start.sh implement add-foo` runs, the PR list shows `spec: add-foo` as MERGED with `Refs #31`, and a search-index query would not return it yet
- **THEN** the apply prompt is built from that PR and the worker is launched; nothing is refused

#### Scenario: Archive right after the implementation merged
- **WHEN** `loop-start.sh archive add-foo` runs, the PR list shows `impl: add-foo` as MERGED with `Refs #31`, and a search-index query would not return it yet
- **THEN** the archive prompt is built from that PR and the worker is launched

#### Scenario: No search query
- **WHEN** `implement`, `archive` or `amend` runs
- **THEN** no `gh pr list` call it makes carries `--search`

#### Scenario: Similar titles are not matches
- **WHEN** the list holds `spec: add-foo-bar` and `Spec: add-foo` but no PR titled exactly `spec: add-foo`
- **THEN** `implement add-foo` exits 3 and uses neither

#### Scenario: Window exhausted
- **WHEN** the list returns 200 PRs and none has the exact title
- **THEN** the refusal keeps its exit code and says that only the newest 200 PRs were listed

### Requirement: Amend changes an approved change through a spec-only PR
`scripts/loop-start.sh amend <change> --brief <text>` SHALL launch an amend worker from `.agents/loop/amend.md` for a change whose `spec: <change>` PR is merged and whose `openspec/changes/<change>/` exists on `origin/<default branch>`. The worker SHALL open a draft PR titled `amend: <change>` with `Kind: spec` and wait at `in-review` for the operator's `approve <sha>`, as a propose worker does.

#### Scenario: Amend launched
- **WHEN** `loop-start.sh amend add-foo --brief "the dry run also lists the change's own propose worktree"` runs, `spec: add-foo` is merged with `Refs #31`, and `openspec/changes/add-foo/` is on `origin/main`
- **THEN** the prompt is built from `amend.md` with `change-name=add-foo`, `issue-number=31`, the spec PR number, `default-branch` and the text as `amendment`, and `loop-launch.sh` is called with `add-foo-amend claude <prompt> --base-branch origin/main --issue 31`

#### Scenario: Amend worker waits for the operator
- **WHEN** the amend worker has pushed its PR
- **THEN** it runs `loop-await.sh <N> approve`, and merges only through `loop-merge.sh <N> <sha>` after the operator's whole message `approve <sha>` in its terminal

#### Scenario: Re-judge reads the amendment
- **WHEN** the amend PR has merged and the operator launches a judge for the change's implementation PR
- **THEN** the judge reads the amended change at `origin/main`

### Requirement: Amend worker changes only the change's wording
The amend worker SHALL edit only files in `openspec/changes/<change>/`, SHALL apply only the operator's amendment, SHALL change no task's checkbox state, and SHALL keep every requirement under 500 characters. Its PR SHALL pass the spec lock as a spec-only PR and `openspec validate --all --strict`, with that output in the PR description.

#### Scenario: No tick
- **WHEN** the amend PR's `tasks.md` is compared with `origin/<default branch>`
- **THEN** the number of `- [x]` lines is the same and every added task is `- [ ]`

#### Scenario: Confined diff
- **WHEN** `git diff --name-only origin/<default branch>...HEAD` runs on the amend branch
- **THEN** every path is under `openspec/changes/<change>/`

#### Scenario: Amendment text recorded, not approval
- **WHEN** the amend PR description is read
- **THEN** it quotes the operator's amendment, contains `Kind: spec` and `Refs #<issue>`, and the change counts as amended only once the PR is merged

### Requirement: Amend is reproducible
`scripts/test-loop-start.sh` SHALL drive `amend` through stubs: the launch, the dry run, the next free amend name, each refusal (exit 2, 3 and 9), and the stale search index for implement and archive. Removing the exact-title list lookup, the amend refusals or the next free amend name from `loop-start.sh` SHALL make the test exit non-zero. Results are simulations.

#### Scenario: Amend and lookup scenarios behave
- **WHEN** `bash scripts/test-loop-start.sh` runs against `loop-start.sh` as shipped
- **THEN** it prints a PASS line for each amend and lookup scenario and exits zero

#### Scenario: Reverted lookup detected
- **WHEN** `find_pr` in `loop-start.sh` is changed back to a `--search` query
- **THEN** `bash scripts/test-loop-start.sh` exits non-zero

### Requirement: Loop documentation describes amend
`docs/dev-loop.md` and `.agents/loop/README.md` SHALL describe `amend` as the way to settle a judge finding about the approved change itself: the operator decides, records it with the amend verb, approves the amend PR, then re-judges. They SHALL state that a judge does not accept an operator decision quoted in a PR body, comment, issue or another agent's output, and that an amendment is not a fix round.

#### Scenario: Procedure documented
- **WHEN** both documents are read after the change
- **THEN** each names `/sdd-loop amend <change>: <text>`, the `amend: <change>` spec-only PR, the operator's `approve <sha7>` in the amend worker's terminal, and the re-judge after the merge

#### Scenario: Quoted decisions rejected
- **WHEN** `docs/dev-loop.md` is read
- **THEN** it says that a builder's or anyone's quote of an operator decision in a PR body or comment is not operator input for the judge; only the merged change on `origin/main` is

### Requirement: Length check runs on bash 3.2
`scripts/spec-length.sh` SHALL use only features bash 3.2 provides and SHALL give the same exit codes and output on bash 3.2 as on bash 5. `scripts/test-spec-length.sh` SHALL keep its scenarios and expected results.

#### Scenario: No bash 4 builtins
- **WHEN** `scripts/spec-length.sh` is searched for `mapfile`, `readarray`, `declare -A`, `${var,,}` and `${var^^}`
- **THEN** none appears

#### Scenario: Test under bash 3.2
- **WHEN** `bash scripts/test-spec-length.sh` runs with bash 3.2 as `bash`, for example in the `bash:3.2` container image
- **THEN** every scenario passes and it exits zero

#### Scenario: Test unchanged
- **WHEN** `git diff origin/main -- scripts/test-spec-length.sh` runs on the implementation branch
- **THEN** it prints nothing

## MODIFIED Requirements

### Requirement: Operator starts loop steps through the sdd-loop skill
The repository SHALL provide a skill named `sdd-loop` with identical content at `.claude/skills/sdd-loop/SKILL.md` and `.agents/skills/sdd-loop/SKILL.md`. It SHALL accept a plain request or `/sdd-loop` with the verbs `start`, `implement`, `judge`, `amend`, `archive`, `status` and `cleanup`, and SHALL run each through `scripts/loop-start.sh` rather than deriving values, launching or removing worktrees itself.

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

#### Scenario: Amend requested
- **WHEN** the operator asks "amend add-foo: <what to change>" or types `/sdd-loop amend add-foo: <what to change>`
- **THEN** the agent runs `bash scripts/loop-start.sh amend add-foo --brief "<what to change>"` with the text after the first `: ` as one argument, and reports its output

#### Scenario: Cleanup requested
- **WHEN** the operator asks "clean up" or types `/sdd-loop cleanup`
- **THEN** the agent runs `bash scripts/loop-start.sh cleanup --dry-run` and shows its output before anything is removed

### Requirement: Launcher derives launch-time values from GitHub
`scripts/loop-start.sh` SHALL run `git fetch origin` and derive every launch-time value with `gh` and git: owner, repository and default branch; for `implement` and `amend` the spec PR, its merge commit and the issue; for `judge` the change and head branch of the PR; for `archive` the implementation PR and the issue. It SHALL build the prompt with `scripts/loop-prompt.sh` and launch with `scripts/loop-launch.sh`.

#### Scenario: Implement derives the spec PR
- **WHEN** `loop-start.sh implement add-foo` runs and the merged PR titled exactly `spec: add-foo` has body line `Refs #31` and merge commit `abc1234…`
- **THEN** the apply prompt is built with `spec-pr-number`, `spec-merge-commit` set to that full commit, `issue-number=31` and `default-branch` from GitHub

#### Scenario: Archive derives the implementation PR
- **WHEN** `loop-start.sh archive add-foo` runs and the PR titled exactly `impl: add-foo` is merged with body line `Refs #31`
- **THEN** the archive prompt is built with that PR as `impl-pr-number` and `issue-number=31`

#### Scenario: Amend derives the spec PR
- **WHEN** `loop-start.sh amend add-foo --brief <text>` runs and the merged PR titled exactly `spec: add-foo` has body line `Refs #31`
- **THEN** the amend prompt is built with `spec-pr-number`, `issue-number=31`, `default-branch` from GitHub and `amendment=<text>`

#### Scenario: Judge derives the change from the PR
- **WHEN** `loop-start.sh judge 40` runs and PR #40 is open, titled `impl: add-foo`, with head branch `jolbax/add-foo-impl`
- **THEN** the judge prompt is built with `change-name=add-foo` and `pr-number=40`

#### Scenario: Several PRs match a title
- **WHEN** more than one PR matches the title for the verb
- **THEN** the newest one in the required state is used and the others are named in the output

#### Scenario: Prompt builder refuses
- **WHEN** `loop-prompt.sh` exits non-zero
- **THEN** `loop-start.sh` exits 1 with its message and launches nothing

### Requirement: Launcher uses the documented worker layout
`scripts/loop-start.sh` SHALL launch propose as `<change>`, implement as `<change>-impl`, judge as `<change>-judge` or else `<change>-judge-<N>`, amend as `<change>-amend` or else `<change>-amend-<N>`, each N the lowest free from 2, and archive as `<change>-archive`. The agent SHALL be `claude`, or `codex` for judge. The base branch SHALL be `origin/<default branch>`, or `origin/<PR head branch>` for judge.

#### Scenario: Launch arguments per verb
- **WHEN** each verb runs with derivable values
- **THEN** `loop-launch.sh` is called with the name, agent and `--base-branch` above, plus `--issue <N>` when the issue is known

#### Scenario: Next free judge number
- **WHEN** worktrees `add-foo-judge` and `add-foo-judge-2` exist and `judge` runs for an `add-foo` PR
- **THEN** the judge is launched as `add-foo-judge-3`

#### Scenario: Next free amend number
- **WHEN** a worktree `add-foo-amend` exists and `amend add-foo` runs
- **THEN** the amend worker is launched as `add-foo-amend-2`

#### Scenario: Output after launch
- **WHEN** `loop-launch.sh` exits zero
- **THEN** `loop-start.sh` prints the worker name, the terminal handle and the operator's next action, and exits zero

#### Scenario: Launch fails after the worktree exists
- **WHEN** `loop-launch.sh` exits non-zero
- **THEN** `loop-start.sh` exits 1, prints that output and the manual read-and-resend fallback, and neither retries nor removes the worktree

### Requirement: Launcher refuses what it cannot derive
`scripts/loop-start.sh` SHALL exit with a distinct code, launching nothing and creating no worktree, when a required value cannot be derived or the worker's name is taken: 3 no merged spec PR (implement, amend); 4 no open implementation PR (judge); 5 implementation PR not merged (archive); 6 worktree or branch of that name present; 7 intake issue missing or closed; 9 change not on the default branch (amend). It SHALL exit 2 on usage and 1 if a `gh`, git or Orca call fails.

#### Scenario: Implement before the spec merged
- **WHEN** `implement add-foo` runs and no merged PR is titled `spec: add-foo`, including when one is open
- **THEN** it exits 3 and names what it looked for

#### Scenario: Amend before the spec merged
- **WHEN** `amend add-foo --brief <text>` runs and no merged PR is titled `spec: add-foo`
- **THEN** it exits 3

#### Scenario: Amend after the archive
- **WHEN** `amend add-foo --brief <text>` runs, `spec: add-foo` is merged, and `openspec/changes/add-foo/` is not on `origin/<default branch>` (for example because it was archived)
- **THEN** it exits 9 and names the missing directory

#### Scenario: Judge on a PR that is not an open implementation PR
- **WHEN** `judge 40` runs and PR #40 is closed, merged, missing, or not titled `impl: <change>`
- **THEN** it exits 4

#### Scenario: Archive before the implementation merged
- **WHEN** `archive add-foo` runs and the PR titled `impl: add-foo` is open, closed unmerged, or absent
- **THEN** it exits 5

#### Scenario: Merged PR without an issue reference
- **WHEN** the merged `spec:` (implement, amend) or `impl:` (archive) PR has no `Refs #<N>` line
- **THEN** it exits 3 (implement, amend) or 5 (archive) and says the `Refs` line is missing

#### Scenario: Name already taken
- **WHEN** an Orca worktree of the repository already has the worker's name, or a branch named `<name>` or ending in `/<name>` exists locally or on `origin`
- **THEN** it exits 6

#### Scenario: Issue not usable
- **WHEN** `start add-foo --issue 31` runs and issue #31 does not exist or is closed
- **THEN** it exits 7

#### Scenario: Usage errors
- **WHEN** the verb is unknown, an argument is missing, both or neither of `--brief` and `--issue` are given to `start`, `amend` has no `--brief`, a blank one or another argument, the change name is not kebab-case, or the PR is not a number
- **THEN** it exits 2 and calls nothing

### Requirement: Status names where the operator acts
`scripts/loop-start.sh status` SHALL list the repository's loop worktrees with Orca status and comment, and the open PRs titled `spec: `, `amend: `, `impl: ` or `archive: ` with the `openspec` check state and the newest `Verdict:` line, and for each item SHALL state whether the operator must act and where. A spec, amend or archive PR and the worktree that waits for its approval SHALL give the same action. It SHALL change nothing.

#### Scenario: Worker waits for the operator
- **WHEN** a worktree is `in-review` with comment `PR #14 at a1b2c3d: review, then type: approve a1b2c3d`
- **THEN** status shows that worktree as needing the operator, with `approve a1b2c3d` as the reply to type in that worktree's terminal

#### Scenario: Spec or archive PR awaiting approval, CI green
- **WHEN** open PR #14 `spec: add-foo` has head `a1b2c3d…`, the `openspec` check succeeded on it, and worktree `add-foo` is `in-review` with comment `PR #14 at a1b2c3d: review, then type: approve a1b2c3d`
- **THEN** both the PR line and the worktree line say `ACT: type approve a1b2c3d in the terminal of add-foo`, and the PR line does not say "no action"

#### Scenario: Amend PR awaiting approval
- **WHEN** open PR #15 `amend: add-foo` has head `b2c3d4e…`, the `openspec` check succeeded on it, and worktree `add-foo-amend` is `in-review` with comment `PR #15 at b2c3d4e: review, then type: approve b2c3d4e`
- **THEN** PR #15 is listed, and both its line and the worktree line say `ACT: type approve b2c3d4e in the terminal of add-foo-amend`

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

### Requirement: Cleanup removes only finished loop worktrees
`scripts/loop-start.sh cleanup` SHALL consider the repository's Orca worktrees and remove one only if all hold, checked in this order: it is neither the main worktree nor the one the script runs in; its status is `completed`; its name is a loop worker name of a change on `origin/<default branch>`; its HEAD is an ancestor of `origin/<default branch>` after `git fetch origin`; its linked PR, if any, is MERGED or CLOSED; it has no uncommitted changes.

#### Scenario: Finished worker removed
- **WHEN** worktree `add-foo-judge-2` is `completed`, `openspec/changes/archive/2026-10-22-add-foo/` exists on `origin/main`, its HEAD is an ancestor of `origin/main`, it has no linked PR and `git status --porcelain` in it prints nothing
- **THEN** cleanup removes it

#### Scenario: Loop worker names
- **WHEN** `add-foo` is a change on `origin/main`
- **THEN** `add-foo`, `add-foo-impl`, `add-foo-judge`, `add-foo-judge-<N>`, `add-foo-amend`, `add-foo-amend-<N>` and `add-foo-archive` are loop worker names, and `jlb-ideation-phase` or `add-foo-notes` are not

#### Scenario: Each failing rule keeps the worktree
- **WHEN** a worktree meets every rule but one: it is the main or current worktree; its status is `in-progress`, `in-review`, `todo` or none; its name is not a loop worker name; its HEAD is not on `origin/main`; its linked PR is OPEN; or it has uncommitted or untracked files
- **THEN** cleanup keeps it and names that rule as the reason

#### Scenario: First failing rule is the reason
- **WHEN** a worktree fails several rules, for example `in-progress` with uncommitted changes
- **THEN** the reason given is the first failing rule in the order above (here the status)

#### Scenario: Fetch or lookup fails
- **WHEN** `git fetch origin`, `gh repo view`, `orca-ide worktree list` or a rule's `gh` or git call fails
- **THEN** cleanup exits 1 before removing anything
