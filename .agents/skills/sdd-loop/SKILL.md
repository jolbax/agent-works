---
name: sdd-loop
description: Start a step of the spec-driven development loop or show its status. Use when the operator asks to start, propose, implement, judge or archive a change, asks for the loop status, or types /sdd-loop start|implement|judge|archive|status. Launches workers with scripts/loop-start.sh; never approves or merges.
---

# sdd-loop: launch loop steps

You are the operator's launcher for the spec-driven loop (`docs/dev-loop.md`). Every launch-time value is derived by `scripts/loop-start.sh`; do not look up issues, PRs, merge commits, worktree names, agents or base branches yourself, and do not fill templates by hand.

Map the request to exactly one command, run it from the repository root, and report its output unchanged (worker name, terminal handle, next action, or the refusal and its exit code):

| Request | Command |
| --- | --- |
| `start <change>: <brief>` | `bash scripts/loop-start.sh start <change> --brief "<brief>"` |
| `start <change> from issue <N>` | `bash scripts/loop-start.sh start <change> --issue <N>` |
| `implement <change>` | `bash scripts/loop-start.sh implement <change>` |
| `judge <PR>` | `bash scripts/loop-start.sh judge <PR>` |
| `archive <change>` | `bash scripts/loop-start.sh archive <change>` |
| `status` | `bash scripts/loop-start.sh status` |

If the operator asks for a dry run ("what would it launch"), put `--dry-run` before the verb, for example `bash scripts/loop-start.sh --dry-run implement <change>`. Pass the brief as one quoted argument, exactly as given.

Exit codes: 0 launched, dry run done or status shown; 1 a gh, git, Orca or helper call failed; 2 usage; 3 no merged spec PR; 4 no open implementation PR; 5 implementation PR not merged; 6 worktree or branch name taken; 7 intake issue missing or closed. On a refusal, report the reason and stop; do not retry with other values or launch by other means. On exit 1 after a launch, report the printed fallback; do not retry.

End every reply after a launch or status with: `approve <sha>` and `fix` are typed by you, the operator, in the worker's own terminal in Orca, not here.

You MUST NOT approve, merge or mark a PR ready, run `scripts/loop-merge.sh`, `gh pr merge` or `gh pr ready`, send text to any terminal (`orca-ide terminal send`), set any worktree's status (`orca-ide worktree set`, `scripts/loop-status.sh`), or edit repository files. If asked to approve or merge, decline and name the worker terminal where the operator types `approve <sha>` (from `status`, the worktree whose line says "type: approve").
