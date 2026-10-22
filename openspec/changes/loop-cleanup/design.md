## Context

`scripts/loop-start.sh` already launches every loop step and has a read-only `status`. It reads the repository's Orca worktrees with `orca-ide worktree list --repo path:<main worktree> --limit 1000 --json` (refusing a truncated list), takes a worktree's name from the last segment of its path, and reads `gh` and git through the `GH`, `GIT` and `ORCA_IDE` variables so that `scripts/test-loop-start.sh` can stub them. Each row of `worktree list` carries `path`, `branch` (`refs/heads/…`), `isMainWorktree`, `workspaceStatus`, `comment` and `linkedPR` (a number or null; judges have none). `orca-ide worktree rm --worktree <selector> [--force] --json` removes a worktree from Orca and git and "attempts to delete the checked-out local branch", keeping branches Orca cannot prove merged. `orca-ide terminal list --json` lists live terminals with `handle` and `worktreePath`. See proposal.md (Why) for the motivation.

## Goals / Non-Goals

**Goals:**
- One command lists what would be removed and why everything else stays; the same command, without `--dry-run`, removes exactly what the rules allow at that moment.
- Every removal is proven safe from the record (GitHub and git), not from Orca status alone.
- After a removal, what is left behind (branch, terminals) is visible.

**Non-Goals:**
- Closing terminals, deleting branches, deleting remote branches or forcing a removal.
- Cleaning other repositories, or worktrees not registered in Orca.
- Changing how workers set their status.

## Decisions

1. **Verb and usage.** `cleanup` takes no positional argument; `--dry-run` is accepted before the verb (as for the other verbs) or after it (`cleanup --dry-run`, as the brief writes it). `--force` and any other argument are usage errors (exit 2). Alternative: a `--yes` flag for the real run. Rejected: the confirmation belongs to the operator in the skill agent's terminal, and a flag an agent can pass is no confirmation.

2. **Rules, in order; the first failure is the keep reason.**

   | # | Rule | Keep reason printed |
   | --- | --- | --- |
   | 1 | not `isMainWorktree`, and not the worktree the script runs in (`git rev-parse --show-toplevel`) | `main worktree` / `current worktree` |
   | 2 | `workspaceStatus` is `completed` | `status <status>, not completed` |
   | 3 | name is `<change>`, `<change>-impl`, `<change>-judge`, `<change>-judge-<N>` (N ≥ 2) or `<change>-archive`, for a `<change>` with `openspec/changes/<change>/` or `openspec/changes/archive/<YYYY-MM-DD>-<change>/` on `origin/<default>` (`git ls-tree`) | `not a loop worker name` |
   | 4 | `git -C <path> rev-parse HEAD` is an ancestor of `origin/<default>` (`git merge-base --is-ancestor`) | `HEAD <sha7> not merged into origin/<default>` |
   | 5 | if `linkedPR` is set, `gh pr view <N> --json state` is `MERGED` or `CLOSED` | `linked PR #<N> is <state>` |
   | 6 | `git -C <path> status --porcelain` prints nothing | `uncommitted changes` |

   The default branch comes from `gh repo view --json defaultBranchRef`, after `git fetch origin`, as for the launch verbs. Rules 4–6 run only when 1–3 pass, so no git or `gh` call is made for a worktree already kept. A failing call in rules 3–6 (other than the expected non-zero exit of `merge-base --is-ancestor`) is exit 1 before any removal, not a keep reason, so a broken environment never looks like a decision. Rule 3 uses the change directories rather than PR titles because it is one `git ls-tree` call and covers judge worktrees, which have no PR of their own. Rule 4 covers what rule 5 cannot: judge worktrees and any worker whose `linkedPR` is null.

3. **Output.** One line per worktree in `worktree list` order: `<name>  remove` or `<name>  keep: <reason>`, then a summary `<n> to remove, <m> kept`. The dry run stops there and prints `dry run: nothing removed`. The real run prints the same list, then removes in list order.

4. **Removal and report.** For each `remove` row: `orca-ide worktree rm --worktree path:<path> --json` (no `--force`, no `--run-hooks`). Then one fresh `worktree list` (path still present?), `git show-ref --verify --quiet <branch>` on the row's `branch`, and `orca-ide terminal list --json` filtered on `worktreePath` equal to the path. It prints `removed <name>: branch <branch> deleted|kept; terminals: none|<handle>, …`. A kept branch or a remaining terminal is reported, not an error. Alternative: close terminals and delete the branch with `git branch -d`. Rejected: out of the brief's scope, and Orca already decides which branches it can prove merged.

5. **Stop on the first failed removal.** `worktree rm` exiting non-zero, its JSON not `ok: true`, or the path still listed afterwards is a failed removal: print `cleanup: removal of <name> failed: <message>; <k> removed, not attempted: <names>` and exit 8. No retry, no `--force`.

6. **Status: one action for both lines.** For an `in-review` worktree whose comment matches `type: approve <sha7>`, the PR is the worktree's `linkedPR`, else the `PR #<N>` in its comment. When that PR is an open `spec:` or `archive:` PR whose head starts with `<sha7>`, both lines print `ACT: type approve <sha7> in the terminal of <worktree>` if the required check is green on the head, and otherwise `ACT: wait for CI (<check>: <state> on <head7>), then type approve <sha7> in the terminal of <worktree>`. Green means the latest run of the check on the head concluded `SUCCESS` (the condition `loop-merge.sh` checks for exit 5). The worktree line for any other `in-review` comment, and the `impl:` PR lines, keep their existing text. Status therefore needs each open loop PR's CI state before it prints the worktree lines; the PR data is already fetched before printing, so only the print order of the computation changes.

7. **Skill flow.** `cleanup` in the skill: run `bash scripts/loop-start.sh cleanup --dry-run`, show its output unchanged, and ask the operator to type `yes, clean up` to proceed. Only that whole message from the operator in this agent's terminal runs `bash scripts/loop-start.sh cleanup`; anything else ends the verb with nothing removed. The skill keeps its other MUST-NOTs and gains: never pass `--force`, never run `orca-ide worktree rm` or delete branches directly, never run the real cleanup without a dry run shown in the same exchange.

8. **Tests.** The stubs in `test-loop-start.sh` gain `orca-ide worktree rm` (success, failure, or "ok but still listed"), `orca-ide terminal list`, and git `ls-tree`, `rev-parse`, `merge-base --is-ancestor`, `status --porcelain` and `show-ref` per stub worktree, driven by fixture files. Each rule gets a scenario where only that rule fails and the worktree is kept with that reason; guards are shown by removing each rule's check and seeing the test fail.

## Risks / Trade-offs

- [The real run recomputes the list, so a worktree that became removable after the dry run is removed too] → it still meets every rule at that moment; the real run prints its list before removing, and the skill shows that output. The opposite case (a worktree no longer removable) is kept.
- [Orca deletes the local branch of a merged worker] → the work is on `origin/<default>` (rule 4); the remote branch is left to GitHub's delete-branch-on-merge.
- [A removed worktree's terminal stays open as an idle agent] → reported by handle; closing it is the operator's choice in Orca.
- [Rule 3 misreads a change whose directory was deleted without archive] → its worktrees are kept (`not a loop worker name`); keeping is the safe default.
- [`git fetch origin` fails] → exit 1 before any decision; rule 4 never runs against a stale `origin/<default>`.

## Migration Plan

Additive: a new verb, a status message change, doc sections. Rollback is reverting the implementation PR; removed worktrees are not restored by a rollback, but their work is merged and their branches are on GitHub until delete-branch-on-merge removed them.
