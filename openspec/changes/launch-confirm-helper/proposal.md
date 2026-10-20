## Why

Orca sometimes silently drops a launch prompt: the agent starts but sits idle at an empty input. It happened to the Codex judge on PR #4 during the `adopt-sdd-loop` run and was caught only because the operator read the terminal. `docs/dev-loop.md` describes the recovery by hand; the loop should not depend on someone remembering to look. See issue #7.

## What Changes

- Add `scripts/loop-launch.sh`: launches an Orca worker from a prompt file with `orca-ide worktree create ... --json`, takes the terminal handle from the result, confirms that a turn started, and if not resends the prompt once with `orca-ide terminal send ... --enter --wait-submit 20 --json`, requiring the `turn_started` stage. It exits non-zero if the second attempt also fails.
- Plain bash plus `python3` for JSON, matching `scripts/spec-lock.sh`; no new dependencies.
- `docs/dev-loop.md` and `.agents/loop/README.md` use the helper in their launch examples; the manual fallback stays documented.
- The reuse checklist lists the helper among files to copy.
- Every `orca-ide` flag the script uses is verified with `--help` and recorded in the implementation PR evidence.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `development-loop`: the portable loop kit gains the launch helper (modified requirement "Loop kit is portable"), and a new requirement defines launch confirmation behavior.

## Impact

- New file `scripts/loop-launch.sh`; edits to `docs/dev-loop.md` and `.agents/loop/README.md`.
- No change to `scripts/spec-lock.sh`, `.github/`, tests configuration or product code. Orca itself is unchanged.
- Out of scope: changing Orca; supervising workers after launch (Orca orchestration covers fan-out).

## Open questions

1. **How is "a turn has started" observed after `worktree create`?** The `--help` for `worktree create` documents `result.launch` (`launch.outcome.kind`, `launch.outcome.handle`, `launch.receipt.detail`) but not a `turn_started` stage; `terminal send --help` says only that its result "separates input acceptance from observed submission and turn start". The exact JSON field names and values are not documented in `--help`. The design assumes the implementer captures real `--json` output from a real launch and bases the check on it; the check after create may need `terminal read --screen` or `terminal show` if `worktree create` reports no stage. Not resolved here because no worker was launched during proposal.
2. **How long to wait before declaring the first launch idle?** Issue gives `--wait-submit 20` for the resend only. The design proposes a configurable wait with a 20 s default for the first check; the operator may prefer another value.
3. **`shellcheck` availability.** The acceptance hint requires it clean, but it is not installed in this worktree. If still absent at implementation time, the PR must state it was not run, not claim it.
4. **Collision with parallel change #6.** Both changes are deltas against `development-loop`. This one modifies only "Loop kit is portable" and adds one requirement; if #6 also modifies "Loop kit is portable", whichever merges second must re-base its delta on the merged requirement text.
5. **Handle for a second launch kind.** Whether the helper should also support launching into an existing worktree (`orca agent launch`) is not answered; the design limits it to `worktree create`.
