# Loop prompt templates

Project-agnostic prompts for the spec-driven loop described in [docs/dev-loop.md](../../docs/dev-loop.md). Copy them unchanged. Models and effort levels are left to the operator's defaults (`--model`, `--effort`).

**Placeholders.** `<name>` is a launch-time placeholder, filled when the prompt is built. `{name}` is a runtime value the worker resolves itself while running (for example `{N}` its PR number, `{sha}` the head the operator approves, `{merge-commit}` the merge commit `loop-merge.sh` printed, `{round}` the fix round). Never replace a `{name}` by hand.

**Building a prompt.** Run from the repository root:

```bash
bash scripts/loop-prompt.sh .agents/loop/<template>.md <prompt-file> key=value...
```

It writes the text after the template's first `---` line, with each `<key>` replaced literally by its value, to `<prompt-file>`, and keeps every `{name}`. It exits 1 naming each launch-time placeholder left unfilled (nothing is written), and 2 on usage errors. For a template with "Intake:" lines give exactly one of `issue-number` and `brief`; the other Intake line is dropped.

| Template | Step | Documented keys (all also take `owner`, `repo`, `change-name`) | Launched with |
| --- | --- | --- | --- |
| [propose.md](propose.md) | Propose | `issue-number` or `brief` | `bash scripts/loop-launch.sh <name> claude <prompt-file> --issue <N>`, or without `--issue` with `brief=` |
| [apply.md](apply.md) | Implement | `issue-number`, `spec-pr-number`, `spec-merge-commit`, `default-branch` | `git fetch origin && bash scripts/loop-launch.sh <name>-impl claude <prompt-file> --base-branch origin/main`; parallel groups with `git fetch origin && orca-ide orchestration worker-start --worktree new-child --base-branch origin/main …` |
| [judge.md](judge.md) | Judge | `pr-number` | `git fetch origin && bash scripts/loop-launch.sh <name>-judge codex <prompt-file> --base-branch "origin/$(gh pr view <pr-number> --repo <owner>/<repo> --json headRefName -q .headRefName)"` (based on the PR head, not `origin/main`) |
| [fix.md](fix.md) | Fix round (at most two) | none further | the operator types `fix` in the builder's terminal; the builder counts the round and reads the newest verdict itself. Or a built prompt sent to the builder via `orca-ide terminal send --terminal <handle> --text … --enter` |
| [archive.md](archive.md) | Archive | `issue-number`, `impl-pr-number` | `git fetch origin && bash scripts/loop-launch.sh <name>-archive claude <prompt-file> --base-branch origin/main` |

`scripts/loop-launch.sh <name> <agent> <prompt-file> [worktree-create args]` confirms the agent started working and resends the prompt once if not (exit non-zero if that fails too). Every worker except the judge reports its state on its Orca worktree with `scripts/loop-status.sh`.

**Hand-off.** A worker that stops for the operator runs `bash scripts/loop-await.sh {N} approve|judge` instead of building the line. The helper waits up to 60 s until GitHub shows the head the worker pushed (exit 1 without touching Orca if not), sets `in-review` with the PR linked and prints the line. Propose and archive use `approve` (`PR #<N> at <sha7>: review, then type: approve <sha7>`); apply and fix use `judge` (`PR #<N> at <sha7>: ready for the judge (launch it, then wait for its verdict)`). Only the judge's verdict line asks for approval of an implementation PR; the operator then answers in the builder's terminal, and the worker merges with `scripts/loop-merge.sh <N> <sha>`.

**Change requests.** Any message other than the exact `approve <sha>` (and `fix` for a builder) is a change request: the propose, apply or archive worker makes the changes within its MUST-NOT limits, pushes, and runs `loop-await.sh` again with its mode.

**Fix rounds.** The round is the count of comments on the PR that begin with `Verdict: BLOCKING`. Above 2, the builder does not fix and sets `in-review` with "two fix rounds used; operator decides on GitHub".

**Requirement length.** Propose keeps every requirement text under 500 characters and checks it with `bash scripts/spec-length.sh openspec/changes/<change-name>` (`openspec validate` does not measure MODIFIED requirements). If strict validation fails after the archive sync on a requirement over 500 characters, the archive worker shortens it without changing its meaning, inside `openspec/`, and records it in the PR description.

Note: Orca marks a worktree unread when its agent finishes a turn, which can override the read mark that `loop-status.sh` sets.

Manual fallback: confirm with `orca-ide terminal read --terminal <handle> --screen`; if the agent sits at an empty input, resend the prompt with `orca-ide terminal send --terminal <handle> --text … --enter --wait-submit 20`.
