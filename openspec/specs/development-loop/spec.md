# development-loop Specification

## Purpose
Defines the spec-driven loop by which changes to this repository are proposed, approved, implemented, judged, shipped and archived, and the portable kit that lets another Orca-hosted project adopt it. It governs development of the repository, not the product's own change lifecycle.

## Requirements

### Requirement: Approval is the merge of a spec-only pull request
A change's proposal, design and specs SHALL count as approved only when its spec-only pull request, touching `openspec/changes/<name>/` and nothing else, is merged by the operator. Elapsed time, agent output, a passing check or a judge verdict SHALL NOT approve a spec.

#### Scenario: Propose worker stops at a draft spec PR
- **WHEN** a propose worker finishes a change
- **THEN** it has opened a draft pull request whose diff is limited to `openspec/changes/<name>/` and has not started implementation

#### Scenario: Unresolved decision is surfaced
- **WHEN** the propose worker meets a decision the intake issue does not answer
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
The judge SHALL be a different model from the builder, SHALL take the approved change at `origin/main` and the PR diff as input, and SHALL re-run the check commands itself. The builder's evidence SHALL be treated as a claim. The judge SHALL report pass or fail per scenario with evidence.

#### Scenario: Judge verdict per scenario
- **WHEN** the judge reviews an implementation PR
- **THEN** its comment lists each scenario of the change as pass or fail with command output

#### Scenario: Findings are classified
- **WHEN** the judge cannot decide whether a finding is a defect
- **THEN** it classifies that finding as blocking

#### Scenario: Verdict posted as a comment
- **WHEN** the judge reports
- **THEN** it posts with `gh pr comment`, not an approve or request-changes review

### Requirement: Claims need command output
A pull request SHALL carry, in its description, the exact commands run and their output as evidence, and SHALL NOT claim a check that has no such output. Evidence SHALL live in the PR description only, not in repository files.

#### Scenario: Evidence section present
- **WHEN** an implementation PR is opened
- **THEN** its description has an Evidence section with commands and output for every claimed check

#### Scenario: Unrun check
- **WHEN** a check was not run
- **THEN** the description states it was not run

### Requirement: Fix rounds are bounded
After a judge reports blocking findings, at most two fix rounds SHALL occur, each a new builder prompt carrying the findings. If blocking findings remain after the second, the operator SHALL decide.

#### Scenario: Third failure escalates
- **WHEN** blocking findings remain after two fix rounds
- **THEN** no further fix round starts and the operator is asked to decide

### Requirement: Operator merges and holds workflow authority
Only the operator SHALL merge pull requests and change `.github/workflows/`. Agents SHALL push branches and open draft PRs only; their token SHALL lack `workflow` and administration permission. `main` SHALL be protected by an operator-created GitHub ruleset requiring a pull request and the status check `openspec`, with no required approvals.

#### Scenario: Agent finishes a PR
- **WHEN** a worker completes its task
- **THEN** the PR is a draft and awaits the operator to mark it ready and merge it

#### Scenario: Direct push to main is rejected
- **WHEN** anyone pushes a commit directly to `main`
- **THEN** GitHub rejects the push because the ruleset requires a pull request

#### Scenario: Workflow change needed
- **WHEN** a change needs an edit to `.github/workflows/`
- **THEN** it is listed as an operator task in the PR, not made by an agent

### Requirement: Archive is a separate openspec-only pull request
Archiving a change SHALL be done in its own PR confined to `openspec/`, opened after the implementation PR is merged, and SHALL NOT be part of the implementation PR.

#### Scenario: Archive after merge
- **WHEN** the implementation PR has merged
- **THEN** a separate openspec-only PR archives the change and syncs specs

### Requirement: Loop kit is portable
The repository SHALL provide `docs/dev-loop.md`, project-agnostic prompt templates in `.agents/loop/` with `<placeholders>`, issue and PR templates, and `scripts/test-spec-lock.sh`. `docs/dev-loop.md` SHALL include a "Reuse in another Orca project" checklist covering what to copy, what to adapt and what the operator does in the GitHub UI, including creating the ruleset and the caveat that rulesets are enforced on public repositories and, for private ones, only on paid plans.

#### Scenario: Reuse checklist content
- **WHEN** an operator reads the checklist
- **THEN** it names the files to copy, the items to adapt (`openspec/config.yaml` context, the `AGENTS.md` section, token scope, the ruleset on `main`), the GitHub UI steps and the plan caveat

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
