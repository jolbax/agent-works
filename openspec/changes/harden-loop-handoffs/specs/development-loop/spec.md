## ADDED Requirements

### Requirement: Launch prompts are built by a helper
`scripts/loop-prompt.sh <template> <out> key=value...` SHALL write to `<out>` the template text after its first `---` line with each `<key>` replaced by its value. It SHALL exit non-zero, naming each, when a launch-time placeholder remains.

#### Scenario: Template filled
- **WHEN** the helper is run on any template with all of its documented keys
- **THEN** the output contains no `<name>` placeholder, still contains every `{name}`, and exits zero

#### Scenario: Placeholder left unfilled
- **WHEN** a key the template needs is not given
- **THEN** the helper exits non-zero and names the unfilled placeholder

### Requirement: Launch-time and runtime placeholders are distinct
In every template, `<name>` SHALL mean a launch-time placeholder and `{name}` a value the worker resolves while running. The prompt helper SHALL NOT replace `{name}`.

#### Scenario: Runtime value untouched
- **WHEN** a key named like a runtime value (for example `merge-commit=abc`) is given
- **THEN** `{merge-commit}` in the output is unchanged

### Requirement: Prompt helper selects the intake line
For a template with "Intake:" lines, the helper SHALL keep the line matching the given `issue-number` or `brief` and drop the other, and SHALL exit non-zero when neither or both are given.

#### Scenario: Issue given
- **WHEN** `issue-number` is given and `brief` is not
- **THEN** only the issue Intake line remains

#### Scenario: Both or neither given
- **WHEN** both or neither of `issue-number` and `brief` are given
- **THEN** the helper exits non-zero

### Requirement: Workers announce only a confirmed head
`scripts/loop-await.sh <pr> approve|judge` SHALL confirm that the PR's head equals the local `HEAD`, polling for at most 60 seconds, and exit 1 without changing Orca if it does not. It SHALL then set `in-review` with the PR linked and print the same comment line.

#### Scenario: Head matches
- **WHEN** the PR head equals the local `HEAD`
- **THEN** the status is set with a line naming that head's first 7 characters and the line is printed

#### Scenario: Head behind local commits
- **WHEN** the PR head still differs from `HEAD` after 60 seconds
- **THEN** the helper exits 1 and sets no status

### Requirement: Hand-off line says who acts next
With `approve` the line SHALL be `PR #<pr> at <sha7>: review, then type: approve <sha7>`; with `judge` it SHALL be `PR #<pr> at <sha7>: ready for the judge (launch it, then wait for its verdict)`. Every template SHALL use the helper instead of building the line: propose and archive SHALL use `approve`, apply and fix SHALL use `judge`. Only the judge's verdict line SHALL tell the operator to approve an implementation PR.

#### Scenario: Implementation builder before the judge
- **WHEN** an apply or fix worker stops after pushing
- **THEN** its comment says it is ready for the judge and does not contain `type: approve`

## MODIFIED Requirements

### Requirement: Workers report their state in Orca
`scripts/loop-status.sh <status> <message> [--pr <N>] [--issue <N>] [--worktree <selector>]` SHALL set a worktree's Orca status, comment and links, defaulting to the worktree containing the current directory. `<status>` SHALL be a default id (`todo`, `in-progress`, `in-review`, `completed`); only `in-review` marks it unread. Every worker except the judge SHALL set `in-progress` when it starts and `in-review` when it stops to wait for the operator.

#### Scenario: Worker waits for the operator
- **WHEN** a propose or archive worker stops after opening or updating its PR
- **THEN** its Orca worktree shows `in-review`, unread, the PR linked, and a comment naming the PR, its head and the reply that approves it, for example `PR #14 at a1b2c3d: review, then type: approve a1b2c3d`; the worker's last terminal line says the same

#### Scenario: Unknown status rejected
- **WHEN** `loop-status.sh` is called with a status other than the four default ids
- **THEN** it exits with code 2 and calls nothing

### Requirement: Fix rounds are bounded
After a judge reports blocking findings, at most two fix rounds SHALL occur, each a new builder prompt carrying the findings. The round number SHALL be the count of `Verdict: BLOCKING` comments on the PR. If blocking findings remain after the second, the operator SHALL decide.

#### Scenario: Third failure escalates
- **WHEN** the count of `Verdict: BLOCKING` comments on the PR is above 2
- **THEN** the builder does not fix, sets `in-review` with "two fix rounds used; operator decides on GitHub", and no further fix round starts

#### Scenario: Round number from the verdict count
- **WHEN** the PR has one `Verdict: BLOCKING` comment and the operator types `fix`
- **THEN** the builder records fix round 1

### Requirement: Fix rounds start in Orca
After a blocking verdict, the operator SHALL be able to start a fix round by typing `fix` in the builder's terminal. The builder SHALL then read the newest `Verdict:` comment of its PR itself and follow the fix prompt, without the operator copying findings. If that verdict is not blocking, the builder SHALL not claim a fix and SHALL not announce approval.

#### Scenario: Operator starts a fix round
- **WHEN** the builder's worktree shows a blocking verdict and the operator types `fix` in its terminal
- **THEN** the builder fetches the newest verdict comment, fixes only its blocking findings within the fix round limit, and stops at `in-review` ready for the judge at the new head

#### Scenario: Fix round without a new commit
- **WHEN** a fix round ends with no new commit and the newest verdict at the head is BLOCKING
- **THEN** the builder's comment does not say `type: approve`

### Requirement: Operator helpers are reproducible
`scripts/test-loop-status.sh`, `scripts/test-loop-merge.sh`, `scripts/test-loop-prompt.sh` and `scripts/test-loop-await.sh` SHALL drive the helpers through stub `orca-ide` and `gh` commands. The scripts SHALL cover every scenario of the status, merge, prompt and await helper requirements and SHALL exit non-zero if a helper behaves wrongly. Their results SHALL be reported as simulations, separately from any run against real Orca or GitHub.

#### Scenario: All helper scenarios behave
- **WHEN** the four regression scripts are run against the helpers as shipped
- **THEN** they report every scenario as passing and exit zero

#### Scenario: Broken helper detected
- **WHEN** a helper is altered so that it merges despite a head mismatch, sets a status without validating it, leaves a launch-time placeholder unreported, or announces a head it did not confirm
- **THEN** the corresponding regression script exits non-zero
