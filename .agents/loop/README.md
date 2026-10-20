# Loop prompt templates

Project-agnostic prompts for the spec-driven loop described in [docs/dev-loop.md](../../docs/dev-loop.md). Copy them unchanged and replace the `<placeholders>` (`<owner>`, `<repo>`, `<change-name>`, `<issue-number>`, `<pr-number>`, and so on) when launching. Models and effort levels are left to the operator's defaults (`--model`, `--effort`).

| Template | Step | Launched with |
| --- | --- | --- |
| [propose.md](propose.md) | Propose | `git fetch origin && orca-ide worktree create --name <name> --issue <N> --agent claude --prompt …` |
| [apply.md](apply.md) | Implement | `git fetch origin && orca-ide worktree create --name <name>-impl --agent claude --base-branch origin/main --prompt …`; parallel groups with `git fetch origin && orca-ide orchestration worker-start --worktree new-child --base-branch origin/main …` |
| [judge.md](judge.md) | Judge | `git fetch origin && orca-ide worktree create --name <name>-judge --agent codex --base-branch "origin/$(gh pr view <pr-number> --repo <owner>/<repo> --json headRefName -q .headRefName)" --prompt …` (based on the PR head, not `origin/main`) |
| [fix.md](fix.md) | Fix round (at most two) | a new prompt to the builder, via `orca-ide terminal send --terminal <handle> --text … --enter` |
| [archive.md](archive.md) | Archive | `git fetch origin && orca-ide worktree create --name <name>-archive --agent claude --base-branch origin/main --prompt …` |

After launching, confirm the agent is working with `orca-ide terminal read --terminal <handle> --screen`; if it sits at an empty input, resend the prompt with `orca-ide terminal send`.
