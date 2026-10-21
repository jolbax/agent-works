## MODIFIED Requirements

### Requirement: Workers report their state in Orca
`scripts/loop-status.sh <status> <message> [--pr <N>] [--issue <N>] [--worktree <selector>]` SHALL set a worktree's Orca status, comment and links, defaulting to the worktree containing the current directory. `<status>` SHALL be a default id (`todo`, `in-progress`, `in-review`, `completed`); only `in-review` marks it unread. `<message>` SHALL contain at least one non-whitespace character and SHALL be passed to Orca unaltered. Every worker except the judge SHALL set `in-progress` when it starts and `in-review` when it stops to wait for the operator.

#### Scenario: Worker waits for the operator
- **WHEN** a worker stops after opening or updating its PR
- **THEN** its Orca worktree shows `in-review`, unread, the PR linked, and a comment naming the PR, its head and the reply that approves it, for example `PR #14 at a1b2c3d: review, then type: approve a1b2c3d`; the worker's last terminal line says the same

#### Scenario: Unknown status rejected
- **WHEN** `loop-status.sh` is called with a status other than the four default ids
- **THEN** it exits with code 2 and calls nothing

#### Scenario: Blank message rejected
- **WHEN** `loop-status.sh` is called with a message that is empty or only whitespace, for example `"   "`
- **THEN** it exits with code 2 and calls nothing

#### Scenario: Valid message not altered
- **WHEN** `loop-status.sh` is called with a message that has leading or trailing whitespace and a non-whitespace character
- **THEN** the message is passed to Orca exactly as given
