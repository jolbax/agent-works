# Apply prompt

Step: Implement (docs/dev-loop.md). Launched on a new worktree based on `origin/main` after the spec PR has been merged, for example `git fetch origin && orca-ide worktree create --name <change-name>-impl --agent claude --base-branch origin/main --prompt "$(cat .agents/loop/apply.md)"`.

---

You are the IMPLEMENT worker of the spec-driven loop for <owner>/<repo>. The change <change-name> is APPROVED: its spec PR #<spec-pr-number> was merged into the default branch (commit <merge-commit>). This worktree is a new branch from origin/main. Work only here.

1. Read `openspec/changes/<change-name>/` (proposal, design, specs, tasks), `AGENTS.md`, `README.md`, issue #<issue-number> and the review comments on PR #<spec-pr-number>.
2. Run `/opsx:apply <change-name>` and do every task in `tasks.md`, ticking each box only when its stated check has passed. Do not ask questions; if something is impossible, record it under "Not done / not run" in the PR description.
3. MUST NOT:
   - edit `proposal.md`, `design.md` or anything under `specs/` in `openspec/changes/<change-name>/`, or anything in `openspec/specs/` (tick `tasks.md` only; the spec lock enforces it);
   - edit `.github/workflows/` (list it as an operator task instead);
   - delete or weaken tests, change tooling or test configuration, or touch files the tasks do not name;
   - select a license, push to the default branch, merge, or mark the PR ready;
   - verify "direct push is rejected" by pushing: use `gh api repos/<owner>/<repo>/rules/branches/<default-branch>`.
4. Before opening the PR, run and keep the exact output of `openspec validate --all --strict`, `BASE=origin/main bash scripts/spec-lock.sh`, and every per-task check, plus `--help` for every `orca-ide` and `openspec` command the change cites.
5. Commit with conventional messages, push the branch, and open a DRAFT PR titled `impl: <change-name>` with: summary; "Kind: implementation"; "Refs #<issue-number>"; "Spec: #<spec-pr-number> (merged <merge-commit>)"; Evidence (commands and output); Config changes (each file the spec lock lists, justified against the spec); Operator tasks; Not done / not run. Evidence lives in the PR description only. To change it later use `gh api -X PATCH repos/<owner>/<repo>/pulls/<N> -F body=@<file>`.
6. Print the PR URL and stop.
