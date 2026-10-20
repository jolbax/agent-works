# Loop prompt templates

Project-agnostic prompts for the spec-driven loop described in [docs/dev-loop.md](../../docs/dev-loop.md). Copy them unchanged and replace the `<placeholders>` (`<owner>`, `<repo>`, `<change-name>`, `<issue-number>`, `<pr-number>`, and so on) when launching. Models and effort levels are left to the operator's defaults (`--model`, `--effort`).

| Template | Step | Launched with |
| --- | --- | --- |
| [propose.md](propose.md) | Propose | `bash scripts/loop-launch.sh <name> claude .agents/loop/propose.md --issue <N>`, or without `--issue` with a `<brief>` typed in Orca |
| [apply.md](apply.md) | Implement | `git fetch origin && bash scripts/loop-launch.sh <name>-impl claude .agents/loop/apply.md --base-branch origin/main`; parallel groups with `git fetch origin && orca-ide orchestration worker-start --worktree new-child --base-branch origin/main …` |
| [judge.md](judge.md) | Judge | `git fetch origin && bash scripts/loop-launch.sh <name>-judge codex .agents/loop/judge.md --base-branch "origin/$(gh pr view <pr-number> --repo <owner>/<repo> --json headRefName -q .headRefName)"` (based on the PR head, not `origin/main`) |
| [fix.md](fix.md) | Fix round (at most two) | the operator types `fix` in the builder's terminal; the builder reads the newest verdict itself. Or a new prompt to the builder via `orca-ide terminal send --terminal <handle> --text … --enter` |
| [archive.md](archive.md) | Archive | `git fetch origin && bash scripts/loop-launch.sh <name>-archive claude .agents/loop/archive.md --base-branch origin/main` |

Run from the repository root, with the template's `<placeholders>` replaced in a copy of the prompt file. `scripts/loop-launch.sh <name> <agent> <prompt-file> [worktree-create args]` confirms the agent started working and resends the prompt once if not (exit non-zero if that fails too). Every worker except the judge reports its state on its Orca worktree with `scripts/loop-status.sh`. When it stops at `in-review`, its comment names the PR, the head and the reply: `PR #<N> at <sha7>: review, then type: approve <sha7>`. The operator answers in that worker's terminal, and the worker merges with `scripts/loop-merge.sh <N> <sha>`. The judge only writes its verdict onto the builder's worktree; after a PASS, approve in the builder's terminal.

Manual fallback: confirm with `orca-ide terminal read --terminal <handle> --screen`; if the agent sits at an empty input, resend the prompt with `orca-ide terminal send --terminal <handle> --text … --enter --wait-submit 20`.
