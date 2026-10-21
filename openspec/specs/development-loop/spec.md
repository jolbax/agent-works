# development-loop Specification

## Purpose
Defines the spec-driven loop by which changes to this repository are proposed, approved, implemented, judged, shipped and archived, and the portable kit that lets another Orca-hosted project adopt it. It governs development of the repository, not the product's own change lifecycle.

## Requirements

### Requirement: Approval is the merge of a spec-only pull request
A change's proposal, design and specs SHALL count as approved only when its spec-only pull request, touching `openspec/changes/<name>/` and nothing else, is merged by the operator, or merged by `scripts/loop-merge.sh` on the operator's approval of that PR's exact head. Elapsed time, agent output, a passing check or a judge verdict SHALL NOT approve a spec.

#### Scenario: Propose worker stops at a draft spec PR
- **WHEN** a propose worker finishes a change
- **THEN** it has opened a draft pull request whose diff is limited to `openspec/changes/<name>/`, has set its Orca worktree to `in-review` with the PR linked, and has not started implementation

#### Scenario: Unresolved decision is surfaced
- **WHEN** the propose worker meets a decision the intake issue or brief does not answer
- **THEN** it records it under "Open questions" in `proposal.md` and does not ask a question mid-run

### Requirement: Implementation branches from the merged base
Implementation SHALL run on a new branch created from `origin/main` after the spec PR is merged, not on a rebase of the spec branch. Parallel workers SHALL be used only when task groups touch disjoint files, at most three at once.

#### Scenario: Implementation after approval
- **WHEN** the spec PR is merged and implementation starts
- **THEN** the implementation branch's base is `origin/main` containing the merged change

#### Scenario: Overlapping task groups
- **WHEN** two task groups touch the same file
- **THEN** one worker performs both

### Requirement: Spec lock protects approved specs
An implementation pull request SHALL NOT edit the approved proposal, design, delta specs or `openspec/specs/`; it MAY tick `tasks.md`. CI SHALL run the lock from the base branch's copy of `scripts/spec-lock.sh`. A PR confined to `openspec/` is not blocked.

#### Scenario: Spec-only PR passes
- **WHEN** a PR changes only files under `openspec/changes/<name>/`
- **THEN** the spec lock passes

#### Scenario: Ticking tasks passes
- **WHEN** a PR changes code and only ticks `tasks.md`
- **THEN** the spec lock passes

#### Scenario: Editing the proposal fails
- **WHEN** a PR changes code and edits `proposal.md` of a change
- **THEN** the spec lock fails

#### Scenario: Editing a delta spec fails
- **WHEN** a PR changes code and edits a delta spec under `openspec/changes/`
- **THEN** the spec lock fails

#### Scenario: Editing a main spec fails
- **WHEN** a PR changes code and edits a file under `openspec/specs/`
- **THEN** the spec lock fails

#### Scenario: Placeholder files are ignored
- **WHEN** a PR changes code and adds or edits only a `.gitkeep` under `openspec/`
- **THEN** the spec lock passes

### Requirement: Tooling and test configuration changes are surfaced
A PR that changes lint, formatting, TypeScript, test or Node-version configuration, `package.json` or `.github/` SHALL have those files listed by the spec lock without failing it. No test SHALL be deleted or weakened and no such configuration changed unless the approved change names it; the judge SHALL justify each listed file.

#### Scenario: Config change is noted
- **WHEN** a PR changes a file such as `tsconfig.json` or `.github/pull_request_template.md`
- **THEN** the spec lock prints a NOTE listing that file and still passes if no locked spec file was edited

#### Scenario: Unjustified change is blocking
- **WHEN** the judge finds a listed configuration change the approved change does not name
- **THEN** it reports that finding as blocking

### Requirement: Judge is independent and re-runs checks
The judge SHALL be a different model from the builder, SHALL take the approved change at `origin/main` and the PR diff as input, and SHALL re-run the check commands itself. The builder's evidence SHALL be treated as a claim. The judge SHALL report pass or fail per scenario with evidence. Its verdict line SHALL name the PR head it judged.

#### Scenario: Judge verdict per scenario
- **WHEN** the judge reviews an implementation PR
- **THEN** its comment lists each scenario of the change as pass or fail with command output

#### Scenario: Findings are classified
- **WHEN** the judge cannot decide whether a finding is a defect
- **THEN** it classifies that finding as blocking

#### Scenario: Verdict posted as a comment
- **WHEN** the judge reports
- **THEN** it posts with `gh pr comment`, not an approve or request-changes review, and the comment begins with `Verdict: PASS at <sha>` or `Verdict: BLOCKING (<n> findings) at <sha>`, where `<sha>` is a prefix of at least 7 characters of the head it judged

#### Scenario: Verdict reaches the builder's worktree
- **WHEN** the judge has posted its verdict
- **THEN** it sets the builder's Orca worktree to `in-review` with the verdict line as the comment, selected as `branch:<head-branch>` with the full branch name, and sets its own worktree to `completed`. If an update fails, it says so in its output, and the PR comment still stands

#### Scenario: Judge never merges or types into terminals
- **WHEN** the judge runs
- **THEN** it does not run `scripts/loop-merge.sh`, does not merge, and does not send text to any terminal

### Requirement: Claims need command output
A pull request SHALL carry, in its description, the exact commands run and their output as evidence, and SHALL NOT claim a check that has no such output. Evidence SHALL live in the PR description only, not in repository files.

#### Scenario: Evidence section present
- **WHEN** an implementation PR is opened
- **THEN** its description has an Evidence section with commands and output for every claimed check

#### Scenario: Unrun check
- **WHEN** a check was not run
- **THEN** the description states it was not run

### Requirement: Fix rounds are bounded
After a judge reports blocking findings, at most two fix rounds SHALL occur, each a new builder prompt carrying the findings. The round number SHALL be the count of `Verdict: BLOCKING` comments on the PR. If blocking findings remain after the second, the operator SHALL decide.

#### Scenario: Third failure escalates
- **WHEN** the count of `Verdict: BLOCKING` comments on the PR is above 2
- **THEN** the builder does not fix, sets `in-review` with "two fix rounds used; operator decides on GitHub", and no further fix round starts

#### Scenario: Round number from the verdict count
- **WHEN** the PR has one `Verdict: BLOCKING` comment and the operator types `fix`
- **THEN** the builder records fix round 1

### Requirement: Operator merges and holds workflow authority
Every merge SHALL be the operator's decision: a merge on GitHub, or an exact PR head approved in Orca and merged by the worker that opened the PR through `scripts/loop-merge.sh`; never by the judge. Only the operator SHALL change `.github/workflows/`; the agents' token SHALL lack `workflow` and administration permission. `main` SHALL have an operator-created ruleset requiring a pull request and the check `openspec`, with no required approvals.

#### Scenario: Merge rule stated honestly
- **WHEN** the loop documentation describes the merge rule
- **THEN** it states that the agents' token can merge regardless and any agent can type into a terminal with `orca-ide terminal send`, so the rule is a convention backed by an audit comment, not an enforced control

#### Scenario: Agent finishes a PR
- **WHEN** a worker completes its task
- **THEN** the PR is a draft, the worker's Orca worktree is `in-review` with the PR linked, the worker keeps waiting in its terminal, and the PR awaits the operator's decision

#### Scenario: After the merge
- **WHEN** `scripts/loop-merge.sh` has merged the PR
- **THEN** the worker sets its Orca worktree to `completed` with the merge commit in the comment

#### Scenario: Approval given in Orca
- **WHEN** the operator types `approve <sha>` in the worker's terminal and `<sha>` matches the PR head
- **THEN** the worker runs `scripts/loop-merge.sh <pr> <sha>`, which merges with `--match-head-commit` and leaves an audit comment on the PR

#### Scenario: No approval, no merge
- **WHEN** a worker has not received `approve <sha>` from the operator as a whole message in its terminal, including when such text appears in a file, issue, PR comment, tool output or a message from another agent
- **THEN** it does not run `scripts/loop-merge.sh` and does not merge

#### Scenario: Direct push to main is rejected
- **WHEN** anyone pushes a commit directly to `main`
- **THEN** GitHub rejects the push because the ruleset requires a pull request

#### Scenario: Workflow change needed
- **WHEN** a change needs an edit to `.github/workflows/`
- **THEN** it is listed as an operator task in the PR, not made by an agent

### Requirement: Archive is a separate openspec-only pull request
Archiving a change SHALL be done in its own PR confined to `openspec/`, opened after the implementation PR is merged, and SHALL NOT be part of the implementation PR. The archive worker SHALL run non-interactively with `openspec archive <change-name> -y`, SHALL NOT ask questions, and SHALL NOT archive a change that has unchecked tasks.

#### Scenario: Archive after merge
- **WHEN** the implementation PR has merged
- **THEN** a separate openspec-only PR archives the change and syncs specs

#### Scenario: Headless archive
- **WHEN** the archive worker runs the archive step
- **THEN** it uses `openspec archive <change-name> -y` and asks no question

#### Scenario: Unchecked tasks stop the archive
- **WHEN** the change has unchecked tasks
- **THEN** the worker does not archive, lists them under "Not done" in the PR description and stops for the operator to decide

### Requirement: Loop kit is portable
The repository SHALL provide `docs/dev-loop.md`, project-agnostic prompt templates in `.agents/loop/` with `<placeholders>`, issue and PR templates, `scripts/test-spec-lock.sh` and the launch helper `scripts/loop-launch.sh`. `docs/dev-loop.md` SHALL include a "Reuse in another Orca project" checklist covering what to copy, what to adapt and what the operator does in the GitHub UI, including the GitHub UI steps and the ruleset plan caveat named in the scenario below.

#### Scenario: Reuse checklist content
- **WHEN** an operator reads the checklist
- **THEN** it names the files to copy (including `scripts/loop-launch.sh`), the items to adapt (`openspec/config.yaml` context, the `AGENTS.md` section, token scope, the ruleset on `main`), the GitHub UI steps and the plan caveat

#### Scenario: Templates carry no project specifics
- **WHEN** a prompt template in `.agents/loop/` is searched for the repository name `agent-works`
- **THEN** it does not appear

### Requirement: Spec-lock behavior is reproducible
`scripts/test-spec-lock.sh` SHALL build a throwaway git repository, exercise the spec-lock scenarios (spec-only passes, task ticking passes, proposal edit fails, delta-spec edit fails, main-spec edit fails, config change passes with a NOTE, `.gitkeep` ignored) and exit non-zero if any behaves wrongly.

#### Scenario: All scenarios behave
- **WHEN** `bash scripts/test-spec-lock.sh` runs against a correct `scripts/spec-lock.sh`
- **THEN** it exits zero after reporting each scenario

#### Scenario: Broken lock detected
- **WHEN** the lock allows a `proposal.md` edit alongside code
- **THEN** the test script exits non-zero and names the failing scenario

### Requirement: AGENTS.md keeps the rules and points to the loop
`AGENTS.md` SHALL keep the rule sentences that implementation PRs may only tick `tasks.md` and that tests are not deleted or weakened, nor tooling or test configuration changed, unless the approved change names it, and SHALL add a pointer to `docs/dev-loop.md`. Agents load `AGENTS.md` automatically, not the doc.

#### Scenario: Rules still present
- **WHEN** `AGENTS.md` is read after the change
- **THEN** both rule sentences are present and a link to `docs/dev-loop.md` exists

### Requirement: Repository visibility is stated accurately
`AGENTS.md` and `README.md` SHALL describe `jolbax/agent-works` as public wherever they referred to it as private, and SHALL NOT select a license; licensing remains an open operator decision.

#### Scenario: No stale private wording
- **WHEN** `AGENTS.md` and `README.md` are searched for the word "private" in reference to the repository
- **THEN** no such reference remains and no license is named

### Requirement: Loop documentation stays separate and honest
`docs/dev-loop.md` SHALL state that it describes repository development, not the product lifecycle, SHALL NOT claim a command or check was run without retained evidence, and SHALL cite only `orca-ide` and `openspec` commands verified with `--help`.

#### Scenario: Not mistaken for product design
- **WHEN** a reader opens `docs/dev-loop.md`
- **THEN** its opening states it is separate from the lifecycle contracts in `docs/architecture.md`

#### Scenario: Command verification recorded
- **WHEN** the implementation PR is opened
- **THEN** its description lists each `orca-ide` command used in the docs and templates with the `--help` check that verified it

### Requirement: Launch helper confirms the prompt arrived
`scripts/loop-launch.sh` SHALL launch an Orca worker from a prompt file, take the terminal handle from the launch result, and confirm that a turn started. If no turn started, it SHALL resend the prompt exactly once with a submission wait and SHALL require the `turn_started` stage in the result.

#### Scenario: Prompt delivered first time
- **WHEN** the launch result shows a turn started
- **THEN** the helper prints the handle and the observed stage, sends nothing further and exits zero

#### Scenario: Dropped prompt is resent once
- **WHEN** the agent started but no turn began after the launch
- **THEN** the helper resends the prompt once and exits zero only if the result reports the `turn_started` stage

#### Scenario: Second attempt fails
- **WHEN** the resend does not reach `turn_started`
- **THEN** the helper exits non-zero, prints the terminal handle and does not send a third time

#### Scenario: No terminal handle
- **WHEN** the launch result contains no terminal handle
- **THEN** the helper exits non-zero without sending anything

### Requirement: Launch helper fails closed
`scripts/loop-launch.sh` SHALL exit non-zero, naming the terminal handle when one exists, if the second attempt does not reach `turn_started`, if no terminal handle is available, or if a result cannot be interpreted. It SHALL NOT resend a new payload after an ambiguous transport failure. It SHALL need only bash and `python3`.

#### Scenario: Uninterpretable result
- **WHEN** a launch or send result cannot be parsed
- **THEN** the helper exits non-zero and sends nothing further

### Requirement: Loop documentation uses the launch helper
`docs/dev-loop.md` and `.agents/loop/README.md` SHALL use `scripts/loop-launch.sh` in their launch examples and SHALL keep the manual read-and-resend fallback documented. Every `orca-ide` flag used by the helper SHALL be verified with `--help`, with that evidence in the implementation PR description.

#### Scenario: Docs show the helper and the fallback
- **WHEN** `docs/dev-loop.md` and `.agents/loop/README.md` are read after the change
- **THEN** their launch examples call `scripts/loop-launch.sh` and `docs/dev-loop.md` still documents the manual fallback

#### Scenario: Flag verification recorded
- **WHEN** the implementation PR is opened
- **THEN** its description lists each `orca-ide` flag the helper uses with the `--help` check that verified it

### Requirement: Workers report their state in Orca
`scripts/loop-status.sh <status> <message> [--pr <N>] [--issue <N>] [--worktree <selector>]` SHALL set a worktree's Orca status, comment and links, defaulting to the worktree containing the current directory. `<status>` SHALL be a default id (`todo`, `in-progress`, `in-review`, `completed`); only `in-review` marks it unread. Every worker except the judge SHALL set `in-progress` when it starts and `in-review` when it stops to wait for the operator.

#### Scenario: Worker waits for the operator
- **WHEN** a propose or archive worker stops after opening or updating its PR
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

### Requirement: Orca metadata is a notification only
GitHub SHALL remain the record of the loop. A failed status update SHALL NOT stop a worker's GitHub step, and the worker SHALL report the failure under "Not done / not run" in the PR description.

#### Scenario: Orca call fails
- **WHEN** the `orca-ide worktree set` call fails or its result does not report success
- **THEN** `loop-status.sh` exits with code 1, and the worker carries on with its GitHub step and reports the failure

### Requirement: Merges from Orca are bound to the approved head
`scripts/loop-merge.sh <pr> <sha> [--dry-run]` SHALL merge only after checking that:
- the PR is open, against the default branch, and declares a `Kind:`;
- its head starts with `<sha>`;
- the latest `openspec` check on that head completed with success;
- for `Kind: implementation`, the newest verdict is `Verdict: PASS at <sha>` for that head.

Each unmet condition SHALL give a distinct non-zero exit code and change nothing.

#### Scenario: Head moved after approval
- **WHEN** the PR head no longer starts with the approved `<sha>`
- **THEN** the helper exits with code 4, changes nothing, and tells the operator to approve the new head

#### Scenario: Checks not green
- **WHEN** the `openspec` check on the head is missing, pending or failed
- **THEN** the helper exits with code 5 and changes nothing

#### Scenario: Implementation without a passing verdict at the head
- **WHEN** a `Kind: implementation` PR's newest `Verdict:` comment is missing, blocking, names a different head, or names no head
- **THEN** the helper exits with code 6 and changes nothing

### Requirement: Merge helper merges once at the head
When every check passes, `scripts/loop-merge.sh` SHALL mark a draft PR ready, post an audit comment that states the approved head and that the helper is merging at it, and merge with `gh pr merge --merge --match-head-commit <head>`. The audit comment SHALL NOT claim the merge happened. It SHALL NOT retry a failed merge. `--dry-run` SHALL run every check and change nothing.

#### Scenario: Approved head merges
- **WHEN** every condition holds and `--dry-run` is not given
- **THEN** the helper marks a draft PR ready, posts the audit comment, merges at the approved head and prints the merge commit

#### Scenario: Merge call fails
- **WHEN** the `gh pr merge` call fails
- **THEN** the helper exits with code 1, names the failed step and does not call it again; a PR it already marked ready stays ready

#### Scenario: Dry run
- **WHEN** `--dry-run` is given and every condition holds
- **THEN** the helper prints that it would merge the PR at its head, exits zero, and calls no command that changes GitHub

### Requirement: Fix rounds start in Orca
After a blocking verdict, the operator SHALL be able to start a fix round by typing `fix` in the builder's terminal. The builder SHALL then read the newest `Verdict:` comment of its PR itself and follow the fix prompt, without the operator copying findings. If that verdict is not blocking, the builder SHALL not claim a fix and SHALL not announce approval.

#### Scenario: Operator starts a fix round
- **WHEN** the builder's worktree shows a blocking verdict and the operator types `fix` in its terminal
- **THEN** the builder fetches the newest verdict comment, fixes only its blocking findings within the fix round limit, and stops at `in-review` ready for the judge at the new head

#### Scenario: Fix round without a new commit
- **WHEN** a fix round ends with no new commit and the newest verdict at the head is BLOCKING
- **THEN** the builder's comment does not say `type: approve`

### Requirement: Intake can start in Orca
The propose prompt SHALL accept either an issue number or a brief. Given a brief, the propose worker SHALL first file the intake issue with `gh issue create`, using the change issue template's headings filled from the brief, and SHALL then link the issue to its worktree and proceed against that issue.

#### Scenario: Change started from a brief
- **WHEN** the operator launches a propose worker from Orca with a brief and no issue number
- **THEN** a new GitHub issue holds the brief, and the spec PR refers to it with `Refs #<issue>`

### Requirement: Operator helpers are reproducible
`scripts/test-loop-status.sh`, `scripts/test-loop-merge.sh`, `scripts/test-loop-prompt.sh` and `scripts/test-loop-await.sh` SHALL drive the helpers through stub `orca-ide` and `gh` commands. The scripts SHALL cover every scenario of the status, merge, prompt and await helper requirements and SHALL exit non-zero if a helper behaves wrongly. Their results SHALL be reported as simulations, separately from any run against real Orca or GitHub.

#### Scenario: All helper scenarios behave
- **WHEN** the four regression scripts are run against the helpers as shipped
- **THEN** they report every scenario as passing and exit zero

#### Scenario: Broken helper detected
- **WHEN** a helper is altered so that it merges despite a head mismatch, sets a status without validating it, leaves a launch-time placeholder unreported, or announces a head it did not confirm
- **THEN** the corresponding regression script exits non-zero

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

### Requirement: Requested changes are made and re-announced
When the operator asks for changes in a worker's terminal instead of approving, the propose, implement and archive worker SHALL make them within its MUST-NOT limits, push, and announce the new head again with `scripts/loop-await.sh` (`approve` for propose and archive, `judge` for implement). It SHALL NOT treat the request as an approval.

#### Scenario: Operator asks for changes
- **WHEN** the operator types a change request in the worker's terminal after the worker reached `in-review`
- **THEN** the worker edits within its limits, pushes, and sets `in-review` again with the new head through `loop-await.sh`

### Requirement: Spec requirement text stays under 500 characters
The propose prompt SHALL tell the worker to keep every requirement text, including MODIFIED ones, under 500 characters and to check it with `scripts/spec-length.sh`, which SHALL list each requirement over the limit in the change's delta specs and exit non-zero.

#### Scenario: Overlong MODIFIED requirement
- **WHEN** a delta spec's MODIFIED requirement text exceeds 500 characters
- **THEN** `scripts/spec-length.sh` names it and exits non-zero, although `openspec validate` does not

### Requirement: Archive shortens overlong synced requirements
If strict validation fails after the archive sync because a synced requirement is too long, the archive worker SHALL shorten it without changing its meaning, keep the diff inside `openspec/`, and record that in the PR description.

#### Scenario: Sync produces an overlong requirement
- **WHEN** `openspec validate --all --strict` fails after the sync on a requirement over 500 characters
- **THEN** the worker shortens that requirement, the diff stays in `openspec/`, and the PR description records the shortening
