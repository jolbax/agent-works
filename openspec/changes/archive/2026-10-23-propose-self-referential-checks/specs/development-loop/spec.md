## ADDED Requirements

### Requirement: Task checks account for the change's own workers
The propose prompt SHALL tell the worker that a task check running a loop launcher or cleanup for real either names the expected refusal caused by the change's own workers, targets state the change does not create, or is covered by a stub simulation instead, and that an exact list of worktrees, PRs or branches states whether the change's own appear in it. `docs/dev-loop.md` SHALL state the same rule under the propose step. The judge SHALL keep treating an unmet task as blocking.

#### Scenario: Real dry run of the change's own next step
- **WHEN** a task's check runs `loop-start.sh --dry-run implement <change>` for real for the change being built, whose builder worktree `<change>-impl` exists
- **THEN** the check expects exit 6 naming `<change>-impl`, or targets a change whose workers do not exist, or the check is a stub scenario instead

#### Scenario: Exact list of worktrees
- **WHEN** a task's check requires the real cleanup dry run to list exactly some worktrees
- **THEN** the check states whether the change's own worktrees (for example its completed propose worktree) are in that list

#### Scenario: Rule covers every launcher and cleanup verb
- **WHEN** the propose prompt is read
- **THEN** it names `loop-start.sh` implement, judge, archive, amend and cleanup and `loop-launch.sh` as runs the rule applies to

#### Scenario: Template stays portable and fillable
- **WHEN** `loop-prompt.sh` builds the propose prompt with its documented keys
- **THEN** it exits 0, the rule names the change's workers by the filled change name, and the template cites no project PR

#### Scenario: Documentation cites the examples
- **WHEN** the propose step in `docs/dev-loop.md` is read
- **THEN** it states the rule and cites PR #33 (an "exactly" list missing the change's own propose worktree) and PR #37 (a real dry run refused with exit 6 by the change's own builder worktree)

#### Scenario: Unmet task stays blocking
- **WHEN** an approved task's check cannot be met
- **THEN** the judge reports it as blocking, and the operator settles it with amend
