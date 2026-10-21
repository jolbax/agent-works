## Why

`scripts/loop-status.sh` rejects an empty message (exit 2) but accepts a whitespace-only one such as `"   "`, which leaves a blank comment on the Orca worktree. See issue #18.

## What Changes

- `loop-status.sh` exits 2, without calling `orca-ide`, when the message is empty or only whitespace.
- A valid message is passed through unchanged (not trimmed).
- `scripts/test-loop-status.sh` gains a scenario for a whitespace-only message.
- The `development-loop` requirement "Workers report their state in Orca" gains a scenario for the blank message.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `development-loop`: only the requirement "Workers report their state in Orca" changes.

## Impact

- `scripts/loop-status.sh` and `scripts/test-loop-status.sh` (implementation PR, not this spec PR).
- `openspec/specs/development-loop/spec.md` at archive time.
- Out of scope: any other `loop-status.sh` behaviour, `loop-merge.sh`, templates.

## Open questions

- **Which characters count as whitespace.** The issue says "only whitespace" without a definition. This change proposes POSIX blank/space characters (`[[:space:]]`: space, tab, newline, carriage return, form feed, vertical tab). Unicode-only spaces such as U+00A0 are not covered.
