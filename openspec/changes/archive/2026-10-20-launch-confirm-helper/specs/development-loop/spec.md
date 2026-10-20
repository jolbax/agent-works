## MODIFIED Requirements

### Requirement: Loop kit is portable
The repository SHALL provide `docs/dev-loop.md`, project-agnostic prompt templates in `.agents/loop/` with `<placeholders>`, issue and PR templates, `scripts/test-spec-lock.sh` and the launch helper `scripts/loop-launch.sh`. `docs/dev-loop.md` SHALL include a "Reuse in another Orca project" checklist covering what to copy, what to adapt and what the operator does in the GitHub UI, including the GitHub UI steps and the ruleset plan caveat named in the scenario below.

#### Scenario: Reuse checklist content
- **WHEN** an operator reads the checklist
- **THEN** it names the files to copy (including `scripts/loop-launch.sh`), the items to adapt (`openspec/config.yaml` context, the `AGENTS.md` section, token scope, the ruleset on `main`), the GitHub UI steps and the plan caveat

#### Scenario: Templates carry no project specifics
- **WHEN** a prompt template in `.agents/loop/` is searched for the repository name `agent-works`
- **THEN** it does not appear

## ADDED Requirements

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
