# Development loop

This document describes how this repository is *developed*: how a change moves from an idea to a merged, archived change using Orca worktrees, OpenSpec and GitHub. It is separate from the product's lifecycle contracts in [architecture.md](architecture.md), where "change", "stage attempt" and "approval" mean the factory's own records. Nothing here is a product design, and nothing here is part of the product's runtime.

The loop is a portable kit: this file, the prompt templates in [`.agents/loop/`](../.agents/loop/README.md), the issue and pull request templates in `.github/`, the spec lock ([`scripts/spec-lock.sh`](../scripts/spec-lock.sh)) and its regression script ([`scripts/test-spec-lock.sh`](../scripts/test-spec-lock.sh)). The spec is the `development-loop` capability of the change `adopt-sdd-loop`.

The rules that agents must follow are repeated in [AGENTS.md](../AGENTS.md), which agents load automatically. This file is not loaded automatically.

## Roles

| Role | Who | Does |
| --- | --- | --- |
| Operator | the human owner | writes intake issues, reviews and merges every PR, creates the ruleset on `main`, edits `.github/workflows/` |
| Propose worker | Claude agent | writes OpenSpec artifacts, opens a spec-only draft PR, stops |
| Builder | Claude agent | implements an approved change, opens a draft PR with evidence |
| Judge | Codex agent (a different model from the builder) | re-runs the checks, posts a verdict comment |
| CI | GitHub Actions workflow `openspec` | validates OpenSpec, runs the spec lock from the base branch |

## Rules

1. Approval is the merge of the spec-only pull request.
2. An implementation PR never edits the approved proposal, design or specs; it may tick `tasks.md` (spec lock).
3. No test is deleted or weakened and no lint, TypeScript, test or Node-version configuration, `package.json` or `.github/` file changes unless the approved change names it. The lock lists such files; the judge justifies each.
4. The judge is a different model and re-runs the checks; the builder's evidence is a claim.
5. Nothing is claimed without command output in the PR description. Evidence lives in the PR description only, never in repository files.
6. At most two fix rounds, then the operator decides.
7. The operator merges every PR.
8. The agents' GitHub token has no `workflow` or administration permission; only the operator changes `.github/workflows/`.

Which mechanism enforces what:

| Rule | Enforced by |
| --- | --- |
| 2 | `scripts/spec-lock.sh` in CI, read from the base branch |
| 7, nothing on `main` without a PR | the operator's ruleset on `main` (see below), plus the token's permissions |
| 8 | token scope |
| 1, 3 (judgement part), 4, 5, 6 | the judge's checklist and the operator; no mechanism |

Protection of `main` is an operator-created GitHub ruleset: pull request required, required status check `openspec`, no required approvals (every PR is authored by the operator's account, and GitHub does not let an author approve their own PR). Rulesets are enforced on public repositories and, for private repositories, only on paid plans. Verify the ruleset through the API, never by pushing to `main`:

```bash
gh api repos/<owner>/<repo>/rules/branches/main
```

The output must contain a `pull_request` rule and a `required_status_checks` rule whose context is `openspec`. An empty list `[]` means nothing is enforced.

## The loop, step by step

### 0. Setup, once per project

```bash
openspec init --tools claude,codex
```

Then add `scripts/spec-lock.sh`, a CI workflow that runs `openspec validate --all --strict` and the lock from the base commit, an `AGENTS.md` section with the rules, and the ruleset on `main`. See the reuse checklist below.

### 1. Intake (operator)

Open a GitHub issue from the change issue template with the decisions answered up front. Agents do not wait for answers mid-run.

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

The operator reviews and merges the spec PR. The merge commit approves that exact tree; elapsed time, agent output, a passing check or a judge verdict never approve a spec.

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

The prompt comes from [`.agents/loop/judge.md`](../.agents/loop/judge.md); its first step confirms `git rev-parse HEAD` equals the PR's `headRefOid` and stops with a blocking finding if not. The judge reads the approved change at `origin/main` and `gh pr diff <N>`, re-runs the check commands itself, and reports pass or fail for every scenario with command output. Each finding is blocking or advisory; one the judge cannot decide counts as blocking. It posts with `gh pr comment <N> --body-file <file>`, not an approve or request-changes review.

### 6. Fix rounds

For blocking findings, start a new builder prompt carrying them ([`.agents/loop/fix.md`](../.agents/loop/fix.md)), then judge again. After the second fix round, if blocking findings remain, no further round starts and the operator decides.

### 7. Ship (CI and operator)

The operator marks the draft ready, waits for CI, and merges.

### 8. Archive (Claude worker)

After the implementation PR merges, a separate PR confined to `openspec/` archives the change and syncs specs ([`.agents/loop/archive.md`](../.agents/loop/archive.md)); the worker runs `openspec archive <name> -y` headless and asks no questions. `openspec archive -y` does not refuse open tasks, so the worker first checks `tasks.md` for unchecked boxes (`grep -nE '^\s*- \[ \]'`); if any exist it does not archive, lists them under "Not done" in the PR description and stops for the operator to decide. It is not part of the implementation PR, which would sync specs for unmerged work.

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
