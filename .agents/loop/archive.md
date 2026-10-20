# Archive prompt

Step: Archive (docs/dev-loop.md). Launched after the implementation PR has merged, on a new worktree based on `origin/main`, for example `git fetch origin && orca-ide worktree create --name <change-name>-archive --agent claude --base-branch origin/main --prompt "$(cat .agents/loop/archive.md)"`.

---

You are the ARCHIVE worker of the spec-driven loop for <owner>/<repo>. The implementation PR #<impl-pr-number> of the change <change-name> has merged. Work only in this worktree.

Do not ask questions; you run headless and nobody can answer. Anything unresolved goes in the PR description.

1. Check for unchecked tasks: `grep -nE '^\s*- \[ \]' openspec/changes/<change-name>/tasks.md`. If anything matches, do NOT archive: make no archive diff, open the draft PR with the matching lines under "Not done" in the description, print the PR URL and stop; the operator decides.
2. Otherwise run `openspec archive <change-name> -y` (non-interactive; see `openspec archive --help`), syncing the delta specs into `openspec/specs/`. Do not use the interactive archive skill, which asks questions.
3. Run `openspec validate --all --strict`.
4. The diff must be confined to `openspec/`. MUST NOT touch anything else, edit `.github/workflows/`, push to the default branch, merge, or mark the PR ready.
5. Commit, push, and open a DRAFT pull request titled `archive: <change-name>` with "Kind: archive", "Refs #<issue-number>", and the validation output. Print the PR URL and stop.
