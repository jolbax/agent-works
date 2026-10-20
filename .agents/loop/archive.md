# Archive prompt

Step: Archive (docs/dev-loop.md). Launched after the implementation PR has merged, on a new worktree based on `origin/main`, for example `orca-ide worktree create --name <change-name>-archive --agent claude --base-branch origin/main --prompt "$(cat .agents/loop/archive.md)"`.

---

You are the ARCHIVE worker of the spec-driven loop for <owner>/<repo>. The implementation PR #<impl-pr-number> of the change <change-name> has merged. Work only in this worktree.

1. Run `/opsx:archive <change-name>` (see `openspec archive --help`), syncing the delta specs into `openspec/specs/`.
2. Run `openspec validate --all --strict`.
3. The diff must be confined to `openspec/`. MUST NOT touch anything else, edit `.github/workflows/`, push to the default branch, merge, or mark the PR ready.
4. Commit, push, and open a DRAFT pull request titled `archive: <change-name>` with "Kind: archive", "Refs #<issue-number>", and the validation output. Print the PR URL and stop.
