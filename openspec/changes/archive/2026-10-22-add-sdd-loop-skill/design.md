## Context

The loop already has deterministic helpers: `loop-prompt.sh` fills a template, `loop-launch.sh` creates an Orca worktree and confirms the prompt arrived, `loop-status.sh`, `loop-await.sh` and `loop-merge.sh` serve the workers. What is missing is the step before them: deciding the worktree name, agent and base branch, and looking up the issue, PRs and merge commit. See proposal.md (Why) for the errors this caused. Orca opens Claude Code and Codex agents in a worktree; Claude Code loads project skills from `.claude/skills/`, Codex from `.agents/skills/` (where the OpenSpec skills already live).

## Goals / Non-Goals

**Goals:**
- One script call per step, from any worktree of the repository, with no value typed by the operator except the change name, brief, issue number or PR number.
- A refusal says which value is missing, before any worktree exists.
- The skill text is a thin mapping from requests to `loop-start.sh` invocations, so the same file serves both agents and the behaviour is tested in the script.

**Non-Goals:**
- Running fix rounds, approvals or merges from the skill (the operator answers in the worker's own terminal).
- Parallel task-group workers (`worktree-start --worktree new-child`); they stay manual.
- Any change to the templates, other helpers, CI or Orca.

## Decisions

1. **Script owns behaviour, skill owns phrasing.** `scripts/loop-start.sh [--dry-run] <verb> <args>` with verbs `start <change> (--brief <text> | --issue <N>)`, `implement <change>`, `judge <pr>`, `archive <change>`, `status`. The SKILL.md maps a request to one command, prints its output, and adds the reminder that `approve <sha>` and `fix` go into the worker's terminal. Alternative: put the logic in the SKILL.md as instructions for the agent. Rejected: an agent filling values is what failed in the first run, and it cannot be regression-tested.

2. **Derivation from GitHub, matched on the titles the templates prescribe.** Owner/repo and default branch come from `gh repo view --json nameWithOwner,defaultBranchRef` run in the repository. PRs are found with `gh pr list --state all --search '"<title>" in:title' --json number,title,state,mergedAt,mergeCommit,headRefName,body` and filtered to an exact title match (search is fuzzy). The issue is the first `Refs #<N>` line of the PR body. For `judge`, `gh pr view <pr>` gives state, title and head branch, and the change name is the title after `impl: `. Alternative: read values from Orca worktree metadata (linked issue/PR). Rejected: Orca metadata is a notification only (existing requirement), GitHub is the record.

3. **Layout table in one place.** The verb determines template, worktree name, agent, base branch and template keys:

   | Verb | Template | Name | Agent | Base | Keys beyond owner, repo, change-name |
   | --- | --- | --- | --- | --- | --- |
   | start | propose.md | `<change>` | claude | `origin/<default>` | `brief` or `issue-number` |
   | implement | apply.md | `<change>-impl` | claude | `origin/<default>` | `issue-number`, `spec-pr-number`, `spec-merge-commit`, `default-branch` |
   | judge | judge.md | `<change>-judge[-N]` | codex | `origin/<head branch>` | `pr-number` |
   | archive | archive.md | `<change>-archive` | claude | `origin/<default>` | `issue-number`, `impl-pr-number` |

   `--issue <N>` is passed to `loop-launch.sh` whenever the issue is known (as the templates' launch examples do).

4. **Name-taken check.** Orca's `worktree list --repo path:<repo toplevel> --json` gives each worktree's path; the name is the last path segment. Also `git for-each-ref refs/heads refs/remotes/origin` for a branch equal to or ending in `/<name>`. For judge, the first free of `<change>-judge`, `<change>-judge-2`, … is chosen before this check, so the check is the guard against races only.

5. **Exit codes.** 0 launched or dry run done; 1 a `gh`, git, Orca, `loop-prompt.sh` or `loop-launch.sh` call failed; 2 usage; 3 no merged spec PR; 4 no open implementation PR; 5 implementation PR not merged; 6 name taken; 7 intake issue missing or closed. Kept distinct from `loop-launch.sh`'s codes, whose code is printed in the message instead of passed through, because a launch failure after create needs a different operator action from a refusal.

6. **Prompt file location.** The filled prompt goes to a new file under `${TMPDIR:-/tmp}` (`mktemp`), never inside the repository, so the script edits no repository file. The path is printed in both modes so the operator can inspect it.

7. **Status.** One `orca-ide worktree list` call, one `gh pr list --state open` call, and per open loop PR one `gh pr view --json headRefOid,statusCheckRollup,comments`. The newest comment beginning `Verdict:` is shown with whether its `at <sha7>` matches the head. "Where the operator acts": an `in-review` worktree → its comment, in that worktree's terminal; an open `impl:` PR without a verdict at its head and no `in-progress` judge worktree for it → `judge <PR>`. Merged PRs are not listed, so a step that is due but not started (implement after a spec merge, archive after an implementation merge) is not suggested. Everything else: no action.

8. **Testability.** `loop-start.sh` reads `GH`, `GIT`, `ORCA_IDE`, `LOOP_PROMPT` and `LOOP_LAUNCH` from the environment, defaulting to the real commands, the same pattern as `ORCA_IDE` in the existing helpers. `test-loop-start.sh` puts stubs on those variables, records their calls, and asserts the launch arguments, prompt keys and exit codes per scenario.

## Risks / Trade-offs

- [Fuzzy GitHub search misses a PR, e.g. in a very large repository] → exact title filter after a search limited to 50 results per title; a miss gives a refusal, never a wrong launch.
- [A PR body without `Refs #<N>`] → the issue is omitted from `--issue`; for `implement` and `archive` the template needs `issue-number`, so `loop-start.sh` refuses with exit 3 or 5 and says the `Refs` line is missing; for `judge` the issue is not needed.
- [The operator's agent might still run `loop-merge.sh` on request] → the skill text forbids it and the spec's reply rule names the worker terminal; as with Rule 7, this is a convention, not an enforced control, and the docs say so.
- [Launch succeeded in Orca but `loop-launch.sh` reports failure] → no retry and no cleanup; the printed fallback tells the operator to read the terminal.

## Migration Plan

Additive: new files and doc sections. Rollback is deleting the skill files and the script; the manual commands keep working throughout.
