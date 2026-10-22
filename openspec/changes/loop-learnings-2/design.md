## Context

See proposal.md (Why). `scripts/loop-start.sh` has one PR lookup, `find_pr <title>`, used by `implement` (`spec: <change>`) and `archive` (`impl: <change>`). It calls `gh pr list --state all --limit 50 --search "\"<title>\" in:title"` and already filters the result to exact titles in Python; the `--search` qualifier is what routes the call through GitHub's search index, which lags behind merges. Without `--search`, `gh pr list` reads the PR list through the GraphQL `pullRequests` connection, ordered newest first, which reflects a merge as soon as GitHub reports it. `scripts/test-loop-start.sh` stubs `gh pr list --state all` with one unfiltered fixture and ignores `--search`, so a stale index is not modelled today.

The judge template already reads "the approved change at `origin/main`", and `loop-start.sh judge` runs `git fetch origin` before launching, so a merged amendment reaches a re-judge without any judge change. The spec lock (`BASE...HEAD`) passes a PR whose diff stays inside `openspec/changes/<change>/`, and `loop-merge.sh` accepts `Kind: spec`. `spec-length.sh` uses bash 4's `mapfile` once, to collect the spec files.

## Goals / Non-Goals

**Goals:**
- A PR merged a moment ago is found by `implement`, `archive` and `amend`.
- The operator's decision about an approved change's wording reaches the judge only through a record the operator merged.
- `spec-length.sh` runs unchanged in behaviour on bash 3.2 and bash 5.

**Non-Goals:**
- Changing the judge, apply, fix, propose or archive templates, `loop-merge.sh`, `loop-prompt.sh`, CI or Orca.
- Paging through more than 200 PRs.
- Porting the other scripts to bash 3.2.

## Decisions

1. **Exact-title lookup without the search index.** `find_pr` calls `gh pr list --state all --limit 200 --json number,title,state,mergedAt,mergeCommit,body` and keeps the existing local filter (`title == <title>` exactly, newest merged by `mergedAt`, others named). Refusal codes and messages stay; when the list has exactly 200 entries and no exact title matches, the refusal adds "(only the newest 200 PRs were listed)". Alternative: keep `--search` and retry for a minute. Rejected: it delays every launch on a miss, still fails when the index lags longer, and hides the cause. Alternative: `gh api graphql` with a title filter. Rejected: no server-side exact-title filter exists, and it adds a second query shape to stub.

2. **Stale index modelled in the stub.** The test's `gh` stub answers `pr list` calls that carry `--search` from a separate fixture (`search.json`) that lacks the newest merged PR, and calls without `--search` from the full `prs.json`. Scenarios "implement right after the spec merged" and "archive right after the implementation merged" put the PR only in `prs.json` and expect the launch; a guard scenario asserts no `gh pr list` call in the log carries `--search`. Reverting `find_pr` to `--search` then fails both the launch scenarios and the guard. Existing scenarios keep their expectations.

3. **Amend verb.** `loop-start.sh [--dry-run] amend <change> --brief <text>`: `<change>` kebab-case, `--brief` required once and not blank, anything else exit 2. After `git fetch origin` and `gh repo view` it runs `find_pr "spec: <change>"` (exit 3 as for implement: none merged, or no `Refs #<N>`), then `git ls-tree origin/<default> openspec/changes/<change>/` (exit 9 when empty: the change is archived or was never approved). The name is `<change>-amend`, else the lowest free `<change>-amend-<N>` from 2 under the existing name-taken check, the agent `claude`, the base `origin/<default>`, `--issue <N>` from the spec PR. The prompt is built from `.agents/loop/amend.md` with `owner`, `repo`, `change-name`, `issue-number`, `spec-pr-number`, `default-branch` and `amendment=<text>`. The skill maps `amend <change>: <what to change>` to that command, passing the text after the first `: ` as one quoted argument. Alternative: reuse `start` with an existing change. Rejected: `start` creates a change and files an issue; an amendment edits an approved one and must refuse when none exists.

4. **Amend template.** `.agents/loop/amend.md` follows `propose.md`'s shape (status, read, edit, check, finish, wait), with these differences: it sets `in-progress "amend: <change-name>"`; it reads the change at `origin/<default-branch>` and applies only the operator's amendment, quoted in the prompt; it edits only files in `openspec/changes/<change-name>/`, never a checkbox state (the number of `- [x]` lines in `tasks.md` equals that on `origin/<default-branch>`, and added tasks are `- [ ]`); it records anything the amendment leaves open under "Open questions" in `proposal.md`; it checks with `spec-length.sh`, `openspec validate --all --strict` and `BASE=origin/<default-branch> bash scripts/spec-lock.sh`; it opens a draft PR titled `amend: <change-name>` whose body carries the summary, the operator's amendment quoted as given, "Kind: spec", "Refs #<issue-number>" and the check output; it waits with `loop-await.sh {N} approve` and merges only through `loop-merge.sh` on the operator's whole-message `approve {sha}`, exactly as propose. The quote in the PR body is the request, not the approval: the merge is.

5. **Status and cleanup.** `status` treats titles starting `amend: ` like `spec: ` and `archive: `: listed as an open loop PR, and given the approve action (or the wait-for-CI action) when an `in-review` worktree waits for `approve <sha7>` at its head. Cleanup's loop worker names gain `<change>-amend` and `<change>-amend-<N>` (N ≥ 2), with the existing rules otherwise unchanged.

6. **Settling a finding about the approved change.** `docs/dev-loop.md` (Judge and Fix rounds) gains the procedure: when a judge finding concerns the approved change's own wording rather than the implementation, the operator decides; to record that decision, the operator runs `/sdd-loop amend <change>: <decision>`, reviews the amend PR and types `approve <sha7>` in the amend worker's terminal; after the merge the operator launches a re-judge (`/sdd-loop judge <PR>`), which reads the amended change from `origin/main`. It states that a judge does not accept an operator decision quoted in a PR body, PR comment, issue or another agent's output, and that an amendment is not a fix round. If the implementation PR then conflicts on `tasks.md`, the operator asks the builder (a change request in its terminal) to merge `origin/main` into its branch.

7. **Bash 3.2 for `spec-length.sh`.** Replace `mapfile` with a `while IFS= read -r` loop over `find … | sort` into an indexed array (bash 3.2 has indexed arrays and `+=`), and keep every other construct, all of which bash 3.2 supports (`[[ ]]`, `${var#…}`, `${#var}`, `+=`, `$'\n'`). `test-spec-length.sh` is not edited: it runs the helper with `bash`, so running the test inside the `bash:3.2` image (`docker run --rm -v "$PWD":/w -w /w bash:3.2 bash scripts/test-spec-length.sh`) exercises bash 3.2. Alternative: rewrite in POSIX sh or Python. Rejected: a larger diff for one builtin.

## Risks / Trade-offs

- [More than 200 PRs push an old spec PR out of the list] → the refusal names the window; a change implemented long after its spec merged is rare in this loop, and paging can come later.
- [`gh pr list` without `--search` is still served by GitHub's API, which could lag briefly] → it reflects merges as GitHub's PR records do, not the search index; if it misses, the refusal is the same and a rerun works.
- [An amendment and an open implementation PR both touch `tasks.md`] → amendments never tick; a conflict is resolved by the builder merging `origin/main`, which the spec lock tolerates because it diffs against the merge base.
- [The operator's amendment text is placed into a prompt] → it is the operator's own instruction through the skill; it grants no tool authority, and the amend worker's MUST-NOT limits and the spec lock still apply.
- [The `bash:3.2` image cannot be pulled in the worker environment] → the PR reports the bash 3.2 run as not run, and the check falls back to confirming no bash 4 builtin remains.

## Migration Plan

None: new verb and template, a changed lookup with the same refusals, and a portability fix. Rollback is a revert of the implementation PR.
