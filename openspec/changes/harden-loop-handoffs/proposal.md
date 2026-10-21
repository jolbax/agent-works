## Why

The first end-to-end loop run with Orca workers (change `reject-blank-status-message`, PRs #19 and #20) exposed five handoff defects: templates are filled by hand and a placeholder is reused at runtime, and builders announced a stale head, a premature "type: approve", an approval after a BLOCKING verdict, and a wrong fix-round count. See issue #21.

## What Changes

- New `scripts/loop-prompt.sh <template> <out> key=value...` builds a launch prompt: it takes the text after the first `---` line, replaces the given launch-time placeholders, drops the "Intake:" line that does not apply, and exits non-zero naming any launch-time placeholder left unfilled.
- Placeholder convention in every template: launch-time values stay `<name>`; runtime values the worker fills itself become `{name}` (for example `{N}`, `{sha7}`, `{merge-commit}`). `loop-prompt.sh` never replaces `{name}`. This ends `<merge-commit>` meaning two things in `apply.md`.
- New `scripts/loop-await.sh <pr> approve|judge` confirms the PR head equals the local `HEAD` (polling up to 60 s, exit 1 if not), sets `in-review` through `loop-status.sh` and prints the line. All templates use it instead of building the line: propose and archive use `approve`; apply and fix use `judge`. Only the judge's own verdict line tells the operator to approve an implementation PR.
- The fix round number is the count of `Verdict: BLOCKING` comments on the PR. Above 2 the builder does not fix and sets `in-review` "two fix rounds used; operator decides on GitHub".
- When the operator asks for changes in a worker's terminal instead of approving, the propose, apply and archive templates have the worker make them within its MUST-NOT limits, push, and announce the new head again with `loop-await.sh`.
- The MODIFIED "Workers report their state in Orca" carries the two scenarios ("Blank message rejected", "Valid message not altered") added by `reject-blank-status-message` (#19) word for word, so archiving both changes drops neither.
- Simulation tests `scripts/test-loop-prompt.sh` and `scripts/test-loop-await.sh`, each failing when its key check is removed.
- `docs/dev-loop.md` and `.agents/loop/README.md` describe the above. Note only: Orca marks a worktree unread when its agent finishes a turn, which can override `loop-status.sh --read`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `development-loop`: requirements "Workers report their state in Orca", "Fix rounds are bounded", "Fix rounds start in Orca", "Operator helpers are reproducible" change; new requirements "Launch prompts are built by a helper", "Launch-time and runtime placeholders are distinct", "Prompt helper selects the intake line", "Workers announce only a confirmed head" "Hand-off line says who acts next" and "Requested changes are made and re-announced".

## Impact

- New: `scripts/loop-prompt.sh`, `scripts/loop-await.sh`, `scripts/test-loop-prompt.sh`, `scripts/test-loop-await.sh`.
- Changed: `.agents/loop/*.md`, `.agents/loop/README.md`, `docs/dev-loop.md` (implementation PR, not this spec PR); `openspec/specs/development-loop/spec.md` at archive time.
- Out of scope: behaviour of `loop-merge.sh`, `loop-status.sh`, `loop-launch.sh`; Orca itself.

## Open questions

- **Runtime placeholder braces.** The issue suggests `{sha7}`, `{merge-commit}`, `{N}`. This change adopts `{name}` for every runtime value and treats any remaining `<name>` token in the prompt body as launch-time.
- **Unread flag.** Orca's own unread marking after an agent turn can override `loop-status.sh --read`; not addressable here, documented only.
- **Counting rounds.** "Count of `Verdict: BLOCKING` comments" counts comments whose body begins with that line (as `loop-merge.sh` reads verdicts), regardless of head.
