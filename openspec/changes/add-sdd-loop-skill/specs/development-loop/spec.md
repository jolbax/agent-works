## ADDED Requirements

### Requirement: Operator starts loop steps through the sdd-loop skill
The repository SHALL provide a skill named `sdd-loop` with identical content at `.claude/skills/sdd-loop/SKILL.md` and `.agents/skills/sdd-loop/SKILL.md`. It SHALL accept a plain request or `/sdd-loop` with the verbs `start`, `implement`, `judge`, `archive` and `status`, and SHALL run each through `scripts/loop-start.sh` rather than deriving values or launching itself.

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

### Requirement: Launcher derives launch-time values from GitHub
`scripts/loop-start.sh` SHALL run `git fetch origin` and derive every launch-time value with `gh` and git: owner, repository and default branch; for `implement` the spec PR, its merge commit and the issue; for `judge` the change and head branch of the PR; for `archive` the implementation PR and the issue. It SHALL build the prompt with `scripts/loop-prompt.sh` and launch with `scripts/loop-launch.sh`.

#### Scenario: Implement derives the spec PR
- **WHEN** `loop-start.sh implement add-foo` runs and the merged PR titled exactly `spec: add-foo` has body line `Refs #31` and merge commit `abc1234…`
- **THEN** the apply prompt is built with `spec-pr-number`, `spec-merge-commit` set to that full commit, `issue-number=31` and `default-branch` from GitHub

#### Scenario: Archive derives the implementation PR
- **WHEN** `loop-start.sh archive add-foo` runs and the PR titled exactly `impl: add-foo` is merged with body line `Refs #31`
- **THEN** the archive prompt is built with that PR as `impl-pr-number` and `issue-number=31`

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
`scripts/loop-start.sh` SHALL launch propose as `<change>`, implement as `<change>-impl`, judge as `<change>-judge` or else `<change>-judge-<N>` with the lowest free N from 2, and archive as `<change>-archive`. The agent SHALL be `claude`, or `codex` for judge. The base branch SHALL be `origin/<default branch>`, or `origin/<PR head branch>` for judge.

#### Scenario: Launch arguments per verb
- **WHEN** each verb runs with derivable values
- **THEN** `loop-launch.sh` is called with the name, agent and `--base-branch` above, plus `--issue <N>` when the issue is known

#### Scenario: Next free judge number
- **WHEN** worktrees `add-foo-judge` and `add-foo-judge-2` exist and `judge` runs for an `add-foo` PR
- **THEN** the judge is launched as `add-foo-judge-3`

#### Scenario: Output after launch
- **WHEN** `loop-launch.sh` exits zero
- **THEN** `loop-start.sh` prints the worker name, the terminal handle and the operator's next action, and exits zero

#### Scenario: Launch fails after the worktree exists
- **WHEN** `loop-launch.sh` exits non-zero
- **THEN** `loop-start.sh` exits 1, prints that output and the manual read-and-resend fallback, and neither retries nor removes the worktree

### Requirement: Launcher refuses what it cannot derive
`scripts/loop-start.sh` SHALL exit with a distinct code, launching nothing and creating no worktree, when a required value cannot be derived or the worker's name is taken: 3 no merged spec PR (implement); 4 no open implementation PR (judge); 5 implementation PR not merged (archive); 6 worktree or branch of that name present; 7 intake issue missing or closed. It SHALL exit 2 on usage and 1 if a `gh`, git or Orca call fails.

#### Scenario: Implement before the spec merged
- **WHEN** `implement add-foo` runs and no merged PR is titled `spec: add-foo`, including when one is open
- **THEN** it exits 3 and names what it looked for

#### Scenario: Judge on a PR that is not an open implementation PR
- **WHEN** `judge 40` runs and PR #40 is closed, merged, missing, or not titled `impl: <change>`
- **THEN** it exits 4

#### Scenario: Archive before the implementation merged
- **WHEN** `archive add-foo` runs and the PR titled `impl: add-foo` is open, closed unmerged, or absent
- **THEN** it exits 5

#### Scenario: Merged PR without an issue reference
- **WHEN** the merged `spec:` (implement) or `impl:` (archive) PR has no `Refs #<N>` line
- **THEN** it exits 3 (implement) or 5 (archive) and says the `Refs` line is missing

#### Scenario: Name already taken
- **WHEN** an Orca worktree of the repository already has the worker's name, or a branch named `<name>` or ending in `/<name>` exists locally or on `origin`
- **THEN** it exits 6

#### Scenario: Issue not usable
- **WHEN** `start add-foo --issue 31` runs and issue #31 does not exist or is closed
- **THEN** it exits 7

#### Scenario: Usage errors
- **WHEN** the verb is unknown, an argument is missing, both or neither of `--brief` and `--issue` are given, the change name is not kebab-case, or the PR is not a number
- **THEN** it exits 2 and calls nothing

### Requirement: Launcher dry run launches nothing
With `--dry-run`, `scripts/loop-start.sh` SHALL fetch, derive, run every refusal check and build the prompt, then print the filled prompt's path and the exact launch command, and exit zero. It SHALL NOT call `loop-launch.sh` or any command that creates a worktree or changes GitHub.

#### Scenario: Dry run of implement
- **WHEN** `loop-start.sh --dry-run implement add-foo` runs with a merged spec PR
- **THEN** it prints the prompt file path and the `loop-launch.sh` command, the prompt file has no `<name>` token, and no worktree is created

#### Scenario: Dry run still refuses
- **WHEN** `--dry-run` is given and a refusal condition holds
- **THEN** it exits with that refusal's code

### Requirement: Status names where the operator acts
`scripts/loop-start.sh status` SHALL list the repository's loop worktrees with Orca status and comment, and the open PRs titled `spec: `, `impl: ` or `archive: ` with the `openspec` check state and the newest `Verdict:` line, and for each item SHALL state whether the operator must act and where. It SHALL change nothing.

#### Scenario: Worker waits for the operator
- **WHEN** a worktree is `in-review` with comment `PR #14 at a1b2c3d: review, then type: approve a1b2c3d`
- **THEN** status shows that worktree as needing the operator, with that comment as the reply to type in that worktree's terminal

#### Scenario: Implementation PR without a verdict at its head
- **WHEN** an open `impl:` PR's newest verdict is missing or names another head
- **THEN** status suggests `judge <PR>`

#### Scenario: Read only
- **WHEN** status runs
- **THEN** it calls no `orca-ide` command other than list and read commands and no `gh` command that changes GitHub

### Requirement: Launcher holds no merge or approval authority
The skill and `scripts/loop-start.sh` SHALL NOT approve, merge, run `loop-merge.sh`, send text to an existing terminal, set another worktree's status, or edit repository files. Each reply after a launch or status SHALL tell the operator that `approve <sha>` and `fix` are typed in the worker's own terminal.

#### Scenario: Operator asks the skill to approve
- **WHEN** the operator asks the skill agent to approve or merge a PR
- **THEN** it declines and names the worker terminal where the operator types `approve <sha>`

#### Scenario: No forbidden calls
- **WHEN** `scripts/loop-start.sh` is searched for `loop-merge.sh`, `gh pr merge`, `gh pr ready`, `terminal send` and `worktree set`
- **THEN** none appears

### Requirement: Launcher is reproducible
`scripts/test-loop-start.sh` SHALL drive `loop-start.sh` through stub `gh`, `git`, `orca-ide` and launch commands, covering every verb, the dry run and every refusal code, and SHALL exit non-zero if a derivation or refusal check is removed. Its results SHALL be reported as simulations.

#### Scenario: All launcher scenarios behave
- **WHEN** `bash scripts/test-loop-start.sh` runs against `loop-start.sh` as shipped
- **THEN** it prints a PASS line per scenario and exits zero

#### Scenario: Removed check detected
- **WHEN** the merged-state check for implement, or the name-taken check, is removed from `loop-start.sh`
- **THEN** `bash scripts/test-loop-start.sh` exits non-zero

### Requirement: Loop documentation starts steps through the skill
`docs/dev-loop.md` and `.agents/loop/README.md` SHALL present the `sdd-loop` skill as the normal way to start each step and `loop-start.sh` as its script, SHALL keep the manual `loop-prompt.sh` and `loop-launch.sh` commands as the fallback, and the reuse checklist SHALL list the skill files, `loop-start.sh` and its test.

#### Scenario: Skill first, manual fallback kept
- **WHEN** both documents are read after the change
- **THEN** each step's start names the skill verb first and the manual commands remain, labelled as the fallback
