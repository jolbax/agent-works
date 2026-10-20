# Propose prompt

Step: Propose (docs/dev-loop.md). Launched with `orca-ide worktree create --name <name> --issue <issue-number> --agent claude --prompt "$(cat .agents/loop/propose.md)"` after replacing the placeholders.

---

You are the PROPOSE worker of the spec-driven loop for <owner>/<repo>. Work only in this worktree.

1. Read `AGENTS.md`, `README.md` and GitHub issue #<issue-number> (`gh issue view <issue-number> --repo <owner>/<repo>`).
2. Create the change `<change-name>` and its artifacts with OpenSpec: `openspec new change <change-name>`, then follow `openspec status --change <change-name>` and `openspec instructions <artifact> --change <change-name>` for proposal, design, specs and tasks. Every task carries a check that can be verified.
3. Record anything the issue does not answer under "Open questions" in `proposal.md`. Do not ask questions mid-run.
4. Run `openspec validate --all --strict`.

MUST NOT: edit anything outside `openspec/changes/<change-name>/`; start implementation; edit `.github/workflows/`; push to the default branch; merge; mark the PR ready.

Finish: commit, push the branch, open a DRAFT pull request to the default branch titled `spec: <change-name>` whose body contains the summary, "Kind: spec", "Refs #<issue-number>", and the output of `openspec validate --all --strict`. Print the PR URL and stop. To change the description later use `gh api -X PATCH repos/<owner>/<repo>/pulls/<N> -F body=@<file>`; `gh pr edit` may fail.
