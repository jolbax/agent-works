# Development loop

This document describes how this repository is *developed*: how a change moves from an idea to a merged, archived change using Orca worktrees, OpenSpec and GitHub. GitHub is the record and the enforcement layer: issues, pull requests, evidence, verdicts, CI, the spec lock and the ruleset. Orca is where the operator works: each worker reports its state on its worktree, and the operator answers in the worker's terminal. It is separate from the product's lifecycle contracts in [architecture.md](architecture.md), where "change", "stage attempt" and "approval" mean the factory's own records. Nothing here is a product design, and nothing here is part of the product's runtime.

The loop is a portable kit: this file, the prompt templates in [`.agents/loop/`](../.agents/loop/README.md), the issue and pull request templates in `.github/`, the spec lock ([`scripts/spec-lock.sh`](../scripts/spec-lock.sh)) and its regression script ([`scripts/test-spec-lock.sh`](../scripts/test-spec-lock.sh)), and the operator helpers [`scripts/loop-status.sh`](../scripts/loop-status.sh) and [`scripts/loop-merge.sh`](../scripts/loop-merge.sh) with their simulation tests. The spec is the `development-loop` capability of the change `adopt-sdd-loop`.

The rules that agents must follow are repeated in [AGENTS.md](../AGENTS.md), which agents load automatically. This file is not loaded automatically.

## Roles

| Role | Who | Does |
| --- | --- | --- |
| Operator | the human owner | starts changes (a brief in Orca or a GitHub issue), reviews in Orca, decides every merge (`approve <sha>` in the worker's terminal, or a merge on GitHub), creates the ruleset on `main`, edits `.github/workflows/` |
| Propose worker | Claude agent | writes OpenSpec artifacts, opens a spec-only draft PR, stops |
| Builder | Claude agent | implements an approved change, opens a draft PR with evidence |
| Judge | Codex agent (a different model from the builder) | re-runs the checks, posts a verdict comment naming the head, writes the verdict onto the builder's Orca worktree; never merges, never types into a terminal |
| CI | GitHub Actions workflow `openspec` | validates OpenSpec, runs the spec lock from the base branch |

## Rules

1. Approval is the merge of the spec-only pull request.
2. An implementation PR never edits the approved proposal, design or specs; it may tick `tasks.md` (spec lock).
3. No test is deleted or weakened and no lint, TypeScript, test or Node-version configuration, `package.json` or `.github/` file changes unless the approved change names it. The lock lists such files; the judge justifies each.
4. The judge is a different model and re-runs the checks; the builder's evidence is a claim.
5. Nothing is claimed without command output in the PR description. Evidence lives in the PR description only, never in repository files.
6. At most two fix rounds, then the operator decides.
7. Every merge is the operator's decision: a merge on GitHub, or `approve <sha>` typed in the terminal of the worker that opened the PR, after which that worker runs `scripts/loop-merge.sh`.
8. The agents' GitHub token has no `workflow` or administration permission; only the operator changes `.github/workflows/`.

Which mechanism enforces what:

| Rule | Enforced by |
| --- | --- |
| 2 | `scripts/spec-lock.sh` in CI, read from the base branch |
| nothing on `main` without a PR | the operator's ruleset on `main` (see below), plus the token's permissions |
| 7 | a convention, backed by `scripts/loop-merge.sh` (head-bound, audit comment) and the templates; see below |
| 8 | token scope |
| 1, 3 (judgement part), 4, 5, 6 | the judge's checklist and the operator; no mechanism |

Protection of `main` is an operator-created GitHub ruleset: pull request required, required status check `openspec`, no required approvals (every PR is authored by the operator's account, and GitHub does not let an author approve their own PR). Rulesets are enforced on public repositories and, for private repositories, only on paid plans. Verify the ruleset through the API, never by pushing to `main`:

```bash
gh api repos/<owner>/<repo>/rules/branches/main
```

The output must contain a `pull_request` rule and a `required_status_checks` rule whose context is `openspec`. An empty list `[]` means nothing is enforced.

**Rule 7 is a convention, not an enforced control.** Every agent holds the operator's token, which can merge, and any agent can type into another worker's terminal with `orca-ide terminal send`. This was already true when the rule read "only the operator merges". `scripts/loop-merge.sh` does not change it. What the helper does is make each approval explicit and bound to a head:
- it merges only at the head the operator approved (`gh pr merge --match-head-commit`), only with the `openspec` check green on that head, and, for implementation PRs, only with `Verdict: PASS at <sha>` for that head;
- it posts an audit comment before merging.

The templates accept `approve <sha>` only as the operator's own terminal message.

## The operator in Orca

Every worker except the judge sets its worktree's board status with `scripts/loop-status.sh`: `in-progress` when it starts, `in-review` (unread) when it waits for the operator, `completed` after its merge. Orca metadata is a notification only: if setting it fails, the worker carries on and says so in the PR.

| Orca shows on the worktree | The operator |
| --- | --- |
| `PR #<N> at <sha7>: review, then type: approve <sha7>` | reviews the diff in Orca (for example `orca-ide file open-changed --mode diff --worktree <selector>`), then types `approve <sha7>` in that worker's terminal |
| `Verdict: PASS at <sha7>; type: approve <sha7>` (builder) | types `approve <sha7>` in the builder's terminal |
| `Verdict: BLOCKING (<n> findings) at <sha7>; type: fix` (builder) | types `fix` in the builder's terminal, then launches the re-judge |
| a `loop-merge.sh` refusal | follows the reason (approve the new head, wait for CI, re-judge) |
| `two fix rounds used; operator decides on GitHub` | decides on GitHub |

The worker keeps waiting at its prompt after it stops, so the reply can come later. `scripts/loop-merge.sh <pr> <sha> [--dry-run]` exit codes: 0 merged (or would merge); 1 a `gh` call failed (never retried); 2 usage; 3 PR not open, wrong base or no `Kind:`; 4 the head moved since the approval; 5 the `openspec` check is missing, pending or failed; 6 implementation PR without `Verdict: PASS at <sha>` for the head.

## The loop, step by step

### 0. Setup, once per project

```bash
openspec init --tools claude,codex
```

Then add `scripts/spec-lock.sh`, a CI workflow that runs `openspec validate --all --strict` and the lock from the base commit, an `AGENTS.md` section with the rules, and the ruleset on `main`. See the reuse checklist below.

### 1. Intake (operator)

Either open a GitHub issue from the change issue template (for example from a phone), or launch the propose worker from Orca with a `<brief>` instead of an issue number; the worker then files the issue itself with `gh issue create`. Either way the decisions are answered up front. Agents do not wait for answers mid-run.

### 2. Propose (Claude worker)

```bash
bash scripts/loop-launch.sh <name> claude <propose-prompt-file> --issue <N>
```

The prompt comes from [`.agents/loop/propose.md`](../.agents/loop/propose.md). The worker uses OpenSpec to create the change and stops at a **draft** pull request whose diff is limited to `openspec/changes/<name>/`:

```bash
openspec new change <name>
openspec status --change <name>
openspec instructions <artifact> --change <name>
openspec validate --all --strict
```

Anything the issue does not answer goes under "Open questions" in `proposal.md`.

### 3. Approve (operator and CI)

The operator reviews the spec in Orca and types `approve <sha7>` in the propose worker's terminal, which merges it through `scripts/loop-merge.sh`. Merging on GitHub is equivalent. The merge commit approves that exact tree; elapsed time, agent output, a passing check or a judge verdict never approve a spec.

### 4. Implement (Claude worker)

Fetch, then create a new branch from `origin/main` after the merge; do not rebase the spec branch, and never pass a bare `main` as the base:

```bash
git fetch origin
bash scripts/loop-launch.sh <name>-impl claude <apply-prompt-file> --base-branch origin/main
```

The prompt comes from [`.agents/loop/apply.md`](../.agents/loop/apply.md) and carries the MUST-NOT list. The worker runs `/opsx:apply <name>`, ticks each task only after its stated check has passed, and opens a draft PR whose description holds the evidence.

Use parallel workers only when task groups touch disjoint files, at most three at once; if two groups touch the same file, one worker does both:

```bash
git fetch origin
orca-ide orchestration worker-start --worktree new-child --base-branch origin/main --agent claude --spec "<task group prompt>"
```

### 5. Judge (Codex worker)

```bash
git fetch origin
bash scripts/loop-launch.sh <name>-judge codex <judge-prompt-file> --base-branch "origin/$(gh pr view <N> --repo <owner>/<repo> --json headRefName -q .headRefName)"
```

The judge's worktree is based on the PR's head branch, so that re-running checks tests the PR and not `main`. Before a re-judge, the judge's worktree is reset to the new PR head.

The prompt comes from [`.agents/loop/judge.md`](../.agents/loop/judge.md); its first step confirms `git rev-parse HEAD` equals the PR's `headRefOid` and stops with a blocking finding if not. The judge reads the approved change at `origin/main` and `gh pr diff <N>`, re-runs the check commands itself, and reports pass or fail for every scenario with command output. Each finding is blocking or advisory; one the judge cannot decide counts as blocking. It posts with `gh pr comment <N> --body-file <file>`, not an approve or request-changes review. The comment begins `Verdict: PASS at <sha7>` or `Verdict: BLOCKING (<n> findings) at <sha7>`. The judge then writes the verdict line onto the builder's worktree (`--worktree branch:<full head branch>`) and marks its own worktree `completed`.

### 6. Fix rounds

For blocking findings, the operator types `fix` in the builder's terminal. The builder reads the newest verdict itself and follows [`.agents/loop/fix.md`](../.agents/loop/fix.md); a new builder prompt carrying the findings also works. Then judge again. After the second fix round, if blocking findings remain, no further round starts and the operator decides.

### 7. Ship (CI and operator)

The operator types `approve <sha7>` in the builder's terminal once the verdict is `PASS` at that head. `scripts/loop-merge.sh` checks CI and the verdict, marks the draft ready, comments and merges. Merging on GitHub is equivalent.

### 8. Archive (Claude worker)

After the implementation PR merges, a separate PR confined to `openspec/` archives the change and syncs specs ([`.agents/loop/archive.md`](../.agents/loop/archive.md)); the worker runs `openspec archive <name> -y` headless and asks no questions. `openspec archive -y` does not refuse open tasks, so the worker first checks `tasks.md` for unchecked boxes (`grep -nE '^\s*- \[ \]'`); if any exist it does not archive, lists them under "Not done" in the PR description and stops for the operator to decide. It is not part of the implementation PR, which would sync specs for unmerged work. Like every other PR, the archive PR waits at `in-review` in Orca and merges on the operator's `approve <sha7>` in the archive worker's terminal.

## Failure handling

- **`gh pr edit` fails.** On `gh` 2.46 it calls GitHub's retired Projects-classic API. Edit a description with:
  ```bash
  gh api -X PATCH repos/<owner>/<repo>/pulls/<N> -F body=@<file>.md
  ```
- **Orca silently drops a launch prompt.** `scripts/loop-launch.sh` detects this: it reads the terminal until the agent shows activity, resends the prompt once with `--wait-submit`, and exits non-zero if no turn started. If you launched without the helper, or the helper failed, read the terminal yourself; if the agent sits at an empty input, resend:
  ```bash
  orca-ide terminal read --terminal <handle> --screen
  orca-ide terminal send --terminal <handle> --text "<prompt>" --enter
  ```
- **The spec lock fails.** The PR mixes code with spec edits. Split it: spec changes go in a spec PR, and an implementation PR only ticks `tasks.md`.
- **`loop-merge.sh` refuses.** Exit 4: the head moved; review the new head and approve it. Exit 5: CI has not passed on the head; approve again when it has. Exit 6: judge again at the current head. Exit 1 after `gh pr ready`: the PR stays ready, and nothing is retried; check the PR before acting.
- **`loop-status.sh` fails.** Nothing on GitHub depends on it. The worker reports it, and the operator finds the PR from the worker's last terminal line.
- **A check cannot be run.** State under "Not done / not run" in the PR description; do not claim it.
- **A workflow edit is needed.** List it as an operator task in the PR; agents cannot make it.
- Orca runs Claude Code with `--dangerously-skip-permissions`, so authority comes from the git token and the ruleset, not from agent prompts.

## What has been verified

This file claims no execution of its own. Evidence for the checks that back it (the spec-lock regression script, `openspec validate`, and the `--help` output of every cited command) is retained in the description of the implementation pull request #4 (exact commands and complete output), not in this repository. The loop itself has not yet been run end to end by this document's authors beyond that change.

## Reuse in another Orca project

**Copy unchanged:**
- `docs/dev-loop.md`
- `.agents/loop/` (all templates and its `README.md`)
- `.github/ISSUE_TEMPLATE/change.md` and `.github/pull_request_template.md`
- `scripts/spec-lock.sh` and `scripts/test-spec-lock.sh`
- `scripts/loop-launch.sh` and `scripts/test-loop-launch.sh` (launch helper and its simulation test)
- `scripts/loop-status.sh` and `scripts/test-loop-status.sh` (Orca status helper and its simulation test)
- `scripts/loop-merge.sh` and `scripts/test-loop-merge.sh` (head-bound merge helper and its simulation test)
- the CI workflow `openspec` (validate, then the lock read from the base commit)

**Adapt:**
- `openspec/config.yaml` `context:` (project description, authoritative docs, constraints)
- the `AGENTS.md` section: keep the rule sentences (only tick `tasks.md`; no deleting or weakening tests or changing tooling or test configuration unless the approved change names it) and the pointer to `docs/dev-loop.md`; agents load `AGENTS.md`, not this doc
- token scope: the agents' token needs `contents` and `pull requests` write, and must lack `workflow` and administration permission
- the ruleset on `main`
- the tooling-config patterns in `scripts/spec-lock.sh` if the stack differs
- the repository name wherever `<placeholders>` ask for it

**Operator, in the GitHub UI:**
1. Settings → Rules → Rulesets → New branch ruleset targeting the default branch.
2. Require a pull request before merging, with zero required approvals.
3. Require status check `openspec`.
4. Create the fine-grained token for agents with the scope above.
5. Verify with `gh api repos/<owner>/<repo>/rules/branches/main`.

**Plan caveat:** rulesets are enforced on public repositories and, for private repositories, only on paid plans. A private repository on a free plan has no enforcement of "nothing reaches `main` without a PR"; the spec lock still runs in CI but does not block a direct push.
