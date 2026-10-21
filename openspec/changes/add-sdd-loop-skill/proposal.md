## Why

Starting each loop step needs the operator to fill a template with `scripts/loop-prompt.sh`, look up the issue, spec PR and merge commit, and call `scripts/loop-launch.sh` with the right worktree name, agent and base branch. In the first end-to-end run this was done from outside Orca, and filling values and arguments was the main source of errors (issue #26). The operator should be able to start a step by asking an agent in the Orca UI, with every launch-time value derived from GitHub.

## What Changes

- New project skill `sdd-loop`, installed with identical content at `.claude/skills/sdd-loop/SKILL.md` (Claude Code) and `.agents/skills/sdd-loop/SKILL.md` (Codex). It is not named `loop` because Claude Code ships a built-in `/loop`. It is triggered by a plain request or `/sdd-loop <verb>`:
  - `start <change>: <brief>` or `start <change> from issue <N>`: propose;
  - `implement <change>`: apply, deriving the issue, spec PR and spec merge commit;
  - `judge <PR>`: judge (Codex), based on the PR's head branch;
  - `archive <change>`: archive, deriving the implementation PR and issue;
  - `status`: the loop worktrees with Orca status and comment, the open loop PRs with CI and newest verdict, and for each where the operator must act.
- New `scripts/loop-start.sh [--dry-run] <verb> <args>` holds the deterministic part: it fetches `origin`, derives every launch-time value with `gh`, builds the prompt with `loop-prompt.sh`, and launches with `loop-launch.sh` using the documented worktree name, agent and base branch. It prints the worker name, terminal handle and the operator's next action. It refuses with a distinct exit code, launching nothing, when a value cannot be derived or the worktree name is taken. `--dry-run` prints the filled prompt path and the launch command without launching. The SKILL.md stays short and calls the script.
- The skill only launches workers and reports status. It never approves, merges, types into another worker's terminal, or edits repository files; its replies tell the operator that `approve <sha>` and `fix` are typed in the worker's own terminal.
- New `scripts/test-loop-start.sh` drives `loop-start.sh` through stub `gh`, `orca-ide` and launch commands for every verb and every refusal, and fails when a derivation or refusal check is removed.
- `docs/dev-loop.md` and `.agents/loop/README.md` present the skill as the normal way to start each step and keep the manual `loop-prompt.sh` / `loop-launch.sh` commands as the fallback, and the reuse checklist lists the new files.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `development-loop`: new requirements "Operator starts loop steps through the sdd-loop skill", "Launcher derives launch-time values from GitHub", "Launcher uses the documented worker layout", "Launcher refuses what it cannot derive", "Launcher dry run launches nothing", "Status names where the operator acts", "Launcher holds no merge or approval authority", "Launcher is reproducible" and "Loop documentation starts steps through the skill". No existing requirement text changes, so this change does not conflict with the unarchived `harden-loop-handoffs`, which modifies "Operator helpers are reproducible".

## Impact

- New (implementation PR): `.claude/skills/sdd-loop/SKILL.md`, `.agents/skills/sdd-loop/SKILL.md`, `scripts/loop-start.sh`, `scripts/test-loop-start.sh`.
- Changed (implementation PR): `docs/dev-loop.md`, `.agents/loop/README.md`.
- `openspec/specs/development-loop/spec.md` at archive time.
- Out of scope: the templates' worker behaviour, `loop-merge.sh`, `loop-status.sh`, `loop-await.sh`, `loop-launch.sh`, `loop-prompt.sh`, CI, and Orca itself.

## Open questions

- **Finding PRs by title.** The brief does not say how `implement`, `judge` and `archive` find PRs. This change uses the titles the templates already prescribe (`spec: <change>`, `impl: <change>`) with an exact title match, and the issue from the PR body's `Refs #<N>` line. If several PRs match, the newest merged (or open) one is used and the others are named in the output.
- **Spec PR merged on GitHub vs. through `loop-merge.sh`.** Either counts: `implement` only requires the spec PR's state to be merged and reads its merge commit.
- **Worktree name taken.** The brief names a "worktree of that name already present". This change checks Orca's worktree list for the repository (by name, which is the worktree directory's last path segment) and also refuses if a local or `origin` branch named `<name>` or ending in `/<name>` exists, because Orca prefixes branch names (for example `jolbax/<name>`) and the prefix is not read from a documented setting.
- **Judge numbering.** `<change>-judge` is used first; then `<change>-judge-2`, `-3`, … with the lowest number not already present.
- **Where the skill runs.** The brief says the agent is opened in the agent-works main worktree. `loop-start.sh` runs from any worktree of the repository and does not require the main one; it never changes files in the worktree it runs in.
- **Status scope.** "Open loop PRs" means open PRs whose title starts with `spec: `, `impl: ` or `archive: `. "Loop worktrees" are the repository's Orca worktrees other than the main worktree, listed newest activity first; `completed` worktrees are counted but not listed one by one.
- **Launch failure after create.** If `loop-launch.sh` fails after the worktree was created, the worker may exist without a confirmed prompt. `loop-start.sh` then exits 1, prints `loop-launch.sh`'s output and the manual read-and-resend fallback, and does not retry or remove the worktree.
- **Real dry run of `implement`.** Every change with a merged spec PR already has its `<change>-impl` worktree, so a real `--dry-run implement` refuses with exit 6. The real dry-run evidence therefore uses `start` with an unused name (exit 0) and `implement harden-loop-handoffs` (exit 6); `implement` reaching exit 0 is shown by the simulation test only.
