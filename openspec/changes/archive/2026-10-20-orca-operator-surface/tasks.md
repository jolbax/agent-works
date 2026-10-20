## 1. Verify the interface

- [x] 1.1 Run `--help` for `orca-ide worktree set`, `orca-ide worktree show`, `gh pr view`, `gh pr ready`, `gh pr comment`, `gh pr merge` and `gh issue create`. Check: every flag the helpers and templates use appears in the output, and the PR description contains these commands and their output.
- [x] 1.2 Capture the real `--json` output of one `orca-ide worktree set` call, and the real `gh pr view --json state,isDraft,baseRefName,headRefOid,body,statusCheckRollup` output for one open PR. Check: the PR description shows both outputs with credentials redacted, and that the `statusCheckRollup` and `comments` field names the helper reads appear in the real output.

## 2. Status helper

- [x] 2.1 Write `scripts/loop-status.sh` as in design decision 2 (bash and `python3`, `orca-ide` overridable through `ORCA_IDE`). Check: `bash -n scripts/loop-status.sh` exits 0.
- [x] 2.2 Write `scripts/test-loop-status.sh` with a stub `orca-ide` covering: `in-review` sets unread and links the PR; `--issue` links the issue; another status sets read; an unknown status exits 2 with no call; a non-numeric `--pr` or `--issue` exits 2 with no call; a failed call exits 1; a result without `"ok": true` (for example `selector_ambiguous`) exits 1; a run without `--worktree` defaults to `path:<toplevel>`. Check: `bash scripts/test-loop-status.sh` exits 0, and exits non-zero when the helper's status validation is removed. The PR shows the output of both runs and labels them as simulations.
- [x] 2.3 Run `loop-status.sh` once against a real Orca worktree, then restore its previous status. Check: the PR shows the command, its output, and the worktree's status before and after, from `orca-ide worktree list --json`. If this was not run, the PR says so.

## 3. Merge helper

- [x] 3.1 Write `scripts/loop-merge.sh` as in design decisions 4 and 5 (`gh` overridable through `GH`; `LOOP_BASE` and `LOOP_REQUIRED_CHECK` with the stated defaults). Check: `bash -n scripts/loop-merge.sh` exits 0.
- [x] 3.2 Write `scripts/test-loop-merge.sh` with a stub `gh` that records every call. It must cover:
  - a merge at the approved head (ready, comment and merge are called in that order, with `--match-head-commit <full head>`);
  - a head mismatch (exit 4);
  - a pending and a failed `openspec` check (exit 5);
  - a missing check (exit 5);
  - a `StatusContext` entry for the check (merges);
  - a failed run followed by a successful re-run (merges), and the reverse (exit 5);
  - an implementation PR with no verdict, a BLOCKING verdict, a PASS for another head, and a legacy `Verdict: PASS` without `at` (each exit 6);
  - a failing `gh pr view` (exit 1, no other call);
  - an implementation PR with a PASS at the head;
  - a closed PR, a wrong base and a missing `Kind:` (each exit 3);
  - a bad SHA (exit 2);
  - a dry run (exit 0, and no ready, comment or merge call);
  - a failing merge call (exit 1, no retry);
  - an audit comment that does not claim the merge happened.

  Check: `bash scripts/test-loop-merge.sh` exits 0, and exits non-zero when the head comparison is removed from the helper. The PR shows the output of both runs and labels them as simulations.
- [x] 3.3 Run `loop-merge.sh <pr> <head> --dry-run` against a real open PR. Check: the PR shows the output, and `gh pr view <pr> --json state,isDraft` is unchanged afterwards. If this was not run, the PR says so.
- [x] 3.4 Merge this change's own implementation PR with `loop-merge.sh`, but only after the operator types `approve <sha>`. Check: a PR comment added after the merge shows the helper's output and the merge commit. Otherwise, the PR says the ready and merge path is verified by stub only.

## 4. Templates and documentation

- [x] 4.1 Update the templates:
  - `.agents/loop/propose.md`: issue number or brief (`gh issue create --body-file`, then link it with `loop-status.sh --issue`); `in-progress` on start and `in-review` on stop, with the PR, the head and the approval reply in the comment; keep waiting; on `approve <sha>`, run `loop-merge.sh`, then set `completed`.
  - `apply.md`, `fix.md` and `archive.md`: the same status and approval handling. `apply.md` also handles a typed `fix` by fetching the newest verdict comment and following `fix.md`.
  - The MUST-NOT lists of propose, apply, fix and archive: replace "merge, or mark the PR ready" with "merge or mark the PR ready except through `scripts/loop-merge.sh` after the operator typed `approve <sha>` in this terminal".
  - `judge.md`: the verdict line with `at <sha>`; status onto the builder's worktree by full branch name; its own worktree set to `completed`; MUST NOT run `loop-merge.sh` or send terminal text.
  - `README.md` to match. Check: `grep -n "loop-status.sh" .agents/loop/*.md` lists every template except `README.md`; `grep -n "loop-merge.sh" .agents/loop/{propose,apply,fix,archive}.md` lists all four; `grep -n "at <" .agents/loop/judge.md` shows the verdict format.
- [x] 4.2 Update `docs/dev-loop.md`: the operator's role in Orca, rule 7 and the enforcement table, steps 1, 3, 5, 7 and 8, the honesty note about the token, failure handling for exits 4, 5 and 6, and the four scripts in the reuse checklist. Check: `grep -nE "loop-(status|merge)\.sh" docs/dev-loop.md` shows all of them, and `grep -n "convention" docs/dev-loop.md` shows the honesty note.
- [x] 4.3 Update the merge sentence in `AGENTS.md` to say every merge is the operator's decision, either on GitHub or through `scripts/loop-merge.sh` on an `approve <sha>` the operator typed in the terminal. Check: `grep -n "loop-merge.sh" AGENTS.md` shows it.
- [x] 4.4 Confirm the templates carry no project specifics. Check: `grep -rn agent-works .agents/loop/` prints nothing.

## 5. Validation

- [x] 5.1 Run `openspec validate --all --strict`. Check: it exits 0, and its output is in the PR description.
- [x] 5.2 Run `BASE=origin/main bash scripts/spec-lock.sh`. Check: it exits 0, its output is in the PR description, and only `scripts/`, `.agents/loop/`, `docs/`, `AGENTS.md` and the `tasks.md` ticks changed.
- [x] 5.3 Re-run `bash scripts/test-spec-lock.sh`. Check: it exits 0, and its output is in the PR description.
