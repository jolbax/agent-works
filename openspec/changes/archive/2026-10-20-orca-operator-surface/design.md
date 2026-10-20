## Context

See proposal.md for motivation. The loop's records live on GitHub: issues, pull requests, evidence in PR descriptions, judge verdicts as PR comments, and merges. Orca already holds every worker's worktree and terminal. `orca-ide worktree set` (1.4.230) can set a board status (`--workspace-status`, default ids `todo`, `in-progress`, `in-review`, `completed`), a comment, a linked PR and the unread dot. `gh pr merge` (2.102) has `--match-head-commit <sha>`, so GitHub refuses the merge if the head moved. `scripts/spec-lock.sh` and `scripts/loop-launch.sh` set the style: bash plus `python3` for JSON, external commands overridable by environment variable so a stub test can drive them.

## Goals / Non-Goals

**Goals:**
- The operator can run a whole change from Orca: start it, see which worker waits on them, read the verdict, approve and ship, without opening GitHub.
- An approval given in Orca is bound to an exact PR head, has passed the same checks the ruleset requires, and leaves an audit comment on the PR.
- GitHub stays the single record. Nothing that matters exists only in Orca metadata.

**Non-Goals:**
- Enforcing who typed an approval. Every agent holds the operator's token, which can already merge.
- Orca orchestration gates or a coordinator agent.
- Changing Orca, the GitHub ruleset or `.github/`.

## Decisions

1. **Orca metadata is a notification, never a record.** Status and comment on a worktree tell the operator where to look; the PR and its comments remain the evidence. Consequently `loop-status.sh` failing never blocks a worker's GitHub step; the worker states the failure under "Not done / not run" and in its final line.
2. **`scripts/loop-status.sh <status> <message> [--pr <N>] [--issue <N>] [--worktree <selector>]`.** `<status>` must be one of the four default ids, which catches typos before Orca does. The default worktree is `path:<git toplevel of $PWD>`, which names the worker's own worktree. The `current`/`active` selector is not used, because `--help` does not say whether it means the worktree of the calling process or the one active in the Orca window. `branch:` takes the full branch name, with or without `refs/heads/`. A suffix does not resolve (`selector_not_found`), and `branch:main` is ambiguous across repos (`selector_ambiguous`); both come back as `"ok": false`. `in-review` adds `--unread`; any other status adds `--read`. It sends one `worktree set ... --json` call and checks for `"ok": true`. Exit codes: 0 set; 1 the call failed or its result could not be read; 2 usage. Alternative: call `orca-ide` directly from each template. Rejected because five templates would each repeat the flags and validation.
3. **Approval phrase `approve <sha>`, typed by the operator in the terminal of the worker that opened the PR.** The worker accepts it only as a whole message in its terminal. Text in a file, PR comment, issue, tool output or another agent's message does not count. The SHA is the PR head the operator saw, at least 7 hex characters. Workers put that head into their Orca comment, `PR #<N> at <sha7>: review, then type: approve <sha7>`, so the operator never needs GitHub to find it. Claude Code and Codex stay at their input prompt after finishing a turn: PR #11's evidence shows `❯` after `●`. So the operator can type the approval later. The judge never runs the helper and never types into a terminal. After a judge PASS, the operator approves in the **builder's** terminal, which the judge has marked unread. Alternative: an Orca gate. Rejected because gates belong to orchestration runs with a waiting coordinator, which the loop dropped earlier.
4. **`scripts/loop-merge.sh <pr> <sha> [--dry-run]` checks everything, then merges once.** It makes one `gh pr view <pr> --json state,isDraft,baseRefName,headRefOid,body,statusCheckRollup,comments`, and exits 1 if that call fails.
   - **Checks:** a real rollup entry looks like `{"__typename":"CheckRun","name":"openspec","status":"COMPLETED","conclusion":"SUCCESS",…}`. A commit-status entry is `{"__typename":"StatusContext","context":…,"state":…}`. The helper takes the entries whose `name` or `context` is the required check and uses the latest one, by `completedAt` or `startedAt`, so a successful re-run counts. That entry is green only if it is `COMPLETED` with `SUCCESS`, or for a `StatusContext`, `SUCCESS`.
   - **Comments:** they come oldest first, each with `author`, `body` and `createdAt`; `gh` returns at most the first 100, which is enough here. The verdict is the last comment whose body matches `Verdict: … at <sha>`. A legacy `Verdict: PASS` without `at` names no head and counts as missing.

   It refuses with a distinct exit code in this order:
   - exit 2: usage, or `<sha>` is not hex of length 7 to 40;
   - exit 3: the PR is not open, its base is not `$LOOP_BASE` (default `main`), or the body has no `Kind: spec|implementation|archive`;
   - exit 4: `headRefOid` does not start with `<sha>`, so the operator must approve again;
   - exit 5: the check `$LOOP_REQUIRED_CHECK` (default `openspec`) is missing from the rollup or did not succeed;
   - exit 6: for `Kind: implementation`, the newest PR comment that starts with `Verdict:` is not `Verdict: PASS at <prefix of head>`.

   With `--dry-run` it prints `would merge #<pr> at <head>` and exits 0. Otherwise it runs `gh pr ready` if the PR is a draft, then posts the audit comment `Operator approved head <head> in Orca (approve <sha>); scripts/loop-merge.sh is merging at this head.`. That comment is true when posted and does not claim a merge. Then it runs `gh pr merge <pr> --merge --match-head-commit <full head>`. `gh pr merge` prints no SHA, so the helper reads the merge commit with `gh pr view <pr> --json mergeCommit` and prints it. Any `gh` failure after the checks exits 1 and names the step that failed. If `gh pr ready` succeeded and the merge then failed, the PR stays ready; the helper does not undo that. The script does not retry, because a merge whose outcome is unknown stays unknown until someone looks (AGENTS.md).
   - **Why read the check rollup when the ruleset already requires it:** the ruleset would block the merge, but a dry run should give the operator the same answer the merge would get.
   - **Why the verdict must name the head:** a PASS on an older head says nothing about the commits that came after it.
5. **Repository selection.** `gh` resolves the repository from the worktree's `origin`, so the script names no repository and stays project-agnostic.
6. **Judge verdict carries the head and reaches the builder's worktree.** The verdict line becomes `Verdict: PASS at <sha7>` or `Verdict: BLOCKING (<n> findings) at <sha7>`. After posting it, the judge runs `loop-status.sh in-review "<verdict line>; type: approve <sha7> | fix" --pr <N> --worktree branch:<head-branch>`, then sets its own worktree to `completed`.
7. **Intake by brief.** `propose.md` takes either `<issue-number>` or `<brief>`. With a brief, the worker's first step is `gh issue create` from the change template's headings, filled from the brief. It then proceeds as before against the new issue.
8. **Fix rounds from Orca.** The operator types `fix` in the builder's terminal. The builder runs `gh pr view <N> --json comments` and takes the newest `Verdict:` comment as its findings. It then follows `.agents/loop/fix.md` and stops at `in-review` with the new head. A third round is not offered; the comment then says the operator decides on GitHub.
9. **When the operator merges on GitHub instead.** Workers that are still running cannot see that merge, so the next step's launch is unchanged. The operator launches it from Orca, as before.

## Risks / Trade-offs

- [An agent fabricates an approval, either from text in an issue or by typing into another worker's terminal with `orca-ide terminal send`] → the templates accept `approve <sha>` only as a whole terminal message, and the judge must never send terminal text. A shared token cannot tell those apart, which is why this stays a convention. The audit comment makes every helper merge visible. The token could merge regardless, which is the status quo, and the docs say so.
- [The approval goes stale while the operator reads] → `--match-head-commit` and exit 4 make the operator approve again.
- [CI is still running when the operator approves] → exit 5. The operator approves again after CI is green. The helper does not use `--auto`, so nothing merges later unattended.
- [The `branch:` selector does not resolve (proposal open question 2)] → the verdict is still on the PR, and the judge reports the failed status update in its comment.
- [Testing a merge helper without merging] → the stub `gh` covers every exit path. Real runs: `--dry-run` against an open PR, and the real merge of this change's own implementation PR on the operator's approval. Both are reported separately from the stub results; if the real merge is not run, the PR says the ready and merge path is verified by stub only.

## Migration Plan

Additive for workers. The rule text changes from "only the operator merges" to "every merge is the operator's decision". The GitHub path still works. Rollback: revert the templates, docs and `AGENTS.md`, and delete the four scripts.
