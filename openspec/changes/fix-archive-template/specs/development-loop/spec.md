## MODIFIED Requirements

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
