# Design

## Context

See proposal.md for motivation. Observed in the repo: `scripts/spec-lock.sh` (PR #1) fails a PR that changes anything outside `openspec/` and also edits locked files under `openspec/changes|specs/` other than `tasks.md` and `.gitkeep`; it lists tooling config and `.github/` changes as a NOTE. `.github/workflows/ci.yml` validates `openspec validate --all --strict` and runs the lock taken from the base commit. `AGENTS.md` carries a short workflow paragraph with the rules; agents load it automatically but not `docs/dev-loop.md`. The repository is now public, while `AGENTS.md` and `README.md` still say private. `openspec/specs/` is empty.

Tool facts the kit must respect: `gh` on orca-box is 2.46 and `gh pr edit` fails (retired Projects-classic API), so PRs are edited with `gh api -X PATCH repos/<owner>/<repo>/pulls/<N> -F body=@file`; Orca can silently drop a launch prompt, so a launch is confirmed with `orca-ide terminal read` and resent with `orca-ide terminal send --terminal <handle> --text … --enter` when the agent sits at an empty input; Orca runs Claude Code with `--dangerously-skip-permissions`, so authority comes from the git token and branch rule, not agent prompts.

## Goals / Non-Goals

**Goals:**
- One place (`docs/dev-loop.md`) that states the loop, roles, rules and commands, and templates that can be copied unchanged except placeholders.
- Rules enforced by a mechanism where one exists (spec lock, branch rule, token scope), otherwise by the judge's checklist.

**Non-Goals:**
- Changing CI, the lock script, or `openspec/config.yaml`.
- Any product code, product design, or a decision on D1–D6.
- A template repository, hooks, boards, hash-bound approvals, or a coordinator agent.

## Decisions

- **Approval is a merge, not a record.** The merge commit of the spec PR approves that exact tree. Alternative: hash-bound approval files; rejected as more machinery than one operator needs, and the lock already prevents later edits.
- **Implementation branches from `origin/main`.** Rebasing the spec branch would carry unmerged state; branching from main proves the approved spec is what is built.
- **Judge on a different model, posting comments.** Codex judges Claude's work and re-runs checks. GitHub rejects approve/request-changes on one's own PR and all PRs are authored by the operator's account, so `gh pr comment` is the channel. Alternative: multi-reviewer fan-out; rejected for cost without demonstrated need.
- **Uncertain means blocking; two fix rounds.** Bounds loops and cost while keeping the operator as tie-breaker.
- **Archive in a separate PR.** Archiving inside the implementation PR would sync specs for unmerged work.
- **Rules stay in `AGENTS.md`.** It is the file agents load automatically; the doc holds the detail. Alternative: move everything to `docs/dev-loop.md`; rejected because the rules would not reach agents.
- **Evidence only in the PR description.** Repository files would go stale and could be mistaken for product documentation.
- **Templates are prose with `<placeholders>`.** No generator or dependency; copying files is the install step.
- **`scripts/test-spec-lock.sh` builds a temp repo** (`git init`, a base commit, one branch per scenario, `BASE` set to the base commit) and compares exit code and key output lines per scenario. Alternative: a test framework; rejected, the repo has no toolchain (D1 open) and bash matches the lock.
- **Commands are cited only after `--help` verification.** Verified for this proposal: `orca-ide worktree create` (`--name --issue --agent --prompt --base-branch --model --effort`), `orca-ide orchestration worker-start` (`--worktree new-child --base-branch --agent --spec`), `orca-ide terminal read` (`--terminal --screen --cursor`), `orca-ide terminal send` (`--terminal --text --enter`), `openspec init --tools`, `openspec validate --all --strict`, `openspec new change`, `openspec status`, `openspec instructions`, `openspec archive`. The implementation PR repeats this for any further command it cites.

## Risks / Trade-offs

- [Docs drift from `scripts/spec-lock.sh`] → `scripts/test-spec-lock.sh` encodes the scenarios; the operator may wire it into CI.
- [`.github/` templates trip the lock's config NOTE] → expected; the judge justifies them against this change.
- [Judge and builder share blind spots] → different models plus the judge re-running checks; residual risk accepted.
- [Agents bypass the protection of `main`] → enforced by an operator-created GitHub ruleset (pull request required, required status check `openspec`, no required approvals since every PR is authored by the operator's account); the agents' token lacks administration permission. Rulesets are enforced on public repositories and, for private ones, only on paid plans, so a reused private project on a free plan has no enforcement and the checklist says so.
- [Rules live only in `docs/dev-loop.md` and agents never read them] → `AGENTS.md` keeps the rule sentences and points to the doc.
- [Dropped launch prompts leave a worker idle] → documented confirm-and-resend step.
