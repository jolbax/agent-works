## Why

Every step where the operator acts in the loop happens on GitHub: filing the intake issue, reviewing and merging the spec PR, reading the judge's verdict, merging the implementation PR and merging the archive PR. The operator works in Orca, so each change means switching to GitHub four or five times. GitHub should stay the record and the enforcement layer (pull requests, CI, the spec lock and the ruleset), but the operator should be able to see and act on the loop from Orca. See issue #13.

## What Changes

- **Workers report their state on their Orca worktree.** A new helper, `scripts/loop-status.sh`, wraps `orca-ide worktree set --workspace-status <id> --comment <text> [--pr <N>] [--unread]`. Every worker calls it when it starts and when it stops. `in-review` means "waiting for the operator" and sets the unread dot. The judge also writes its verdict line onto the builder's worktree.
- **Approval in Orca, bound to the PR head.** The operator types `approve <sha>` in the stopped worker's Orca terminal. The worker then runs the new helper `scripts/loop-merge.sh <pr> <sha>`. It refuses to merge unless:
  - the PR is open against the default branch and declares a `Kind:`;
  - its head matches the approved SHA;
  - the required check `openspec` succeeded on that head;
  - for `Kind: implementation`, the latest judge verdict is `Verdict: PASS at <sha>` for that head.

  Only the worker that opened the PR runs it, never the judge. It then marks the PR ready, posts an audit comment and merges with `gh pr merge --merge --match-head-commit <sha>`. `--dry-run` runs every check without changing anything.
- **The judge's verdict line names the head:** `Verdict: PASS at <sha>` or `Verdict: BLOCKING (<n> findings) at <sha>`.
- **Fix rounds start in Orca.** The operator types `fix` in the builder's terminal. The builder reads the newest verdict comment itself, so nobody copies findings from GitHub.
- **Intake can start in Orca.** The propose prompt accepts a brief instead of an issue number; in that case the worker files the issue itself with `gh issue create`. Intake through GitHub issues, for example from a phone, still works.
- **The merge rule is restated honestly.** "Only the operator merges" becomes "every merge is the operator's decision". The operator either merges on GitHub, or approves an exact head in Orca and the worker runs `loop-merge.sh`. The docs say plainly that the agents' token can merge either way, so this was and remains a convention backed by an audit trail, not an enforced control.
- Templates in `.agents/loop/`, `docs/dev-loop.md` and `AGENTS.md` are updated to match. Both helpers get stub-driven regression scripts, `scripts/test-loop-status.sh` and `scripts/test-loop-merge.sh`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `development-loop`: two requirements are modified: "Approval is the merge of a spec-only pull request" and "Operator merges and holds workflow authority". The judge requirement is modified so the verdict names the head. New requirements cover Orca status reporting, head-bound merges from Orca, Orca intake and the helpers' regression scripts.

## Impact

- New files: `scripts/loop-status.sh`, `scripts/loop-merge.sh`, `scripts/test-loop-status.sh`, `scripts/test-loop-merge.sh`.
- Edited files: `.agents/loop/propose.md`, `apply.md`, `judge.md`, `fix.md`, `archive.md` and `README.md`; `docs/dev-loop.md`; `AGENTS.md`.
- No change to `scripts/spec-lock.sh`, `.github/`, the ruleset, test configuration or product code. Orca and GitHub settings are unchanged.
- Out of scope: Orca orchestration gates and a coordinator agent; Linear; Orca Mobile flows; enforcing who typed an approval, which a shared token cannot do.

## Open questions

1. **Overlap with `launch-confirm-helper` (PR #11).** Both changes edit `docs/dev-loop.md` and `.agents/loop/README.md`. Their deltas touch different requirements: #11 modifies "Loop kit is portable", which this change leaves alone. Whichever implementation merges second rebases its text edits onto the other's.
2. **The `branch:` worktree selector (answered during review).** `orca-ide worktree show` on 1.4.230 resolves `branch:jolbax/launch-confirm-helper-impl` and `branch:refs/heads/jolbax/launch-confirm-helper-impl`. The bare suffix `branch:launch-confirm-helper-impl` gives `selector_not_found`, and `branch:main` gives `selector_ambiguous` because three repos have a `main`. The judge therefore passes the full head branch name.
3. **"Loop kit is portable".** PR #11 modifies this requirement, and this change lists four more scripts in the reuse checklist without modifying it again. Whichever archive runs second re-syncs that paragraph instead of adding a second MODIFIED.
