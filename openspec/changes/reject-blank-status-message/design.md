## Context

`loop-status.sh` validates its message with `[ -n "$message" ]`, which passes `"   "`. The validation runs after the status check and before any `orca-ide` call, so a new check at the same place keeps the "calls nothing" guarantee.

## Goals / Non-Goals

- Goal: empty or whitespace-only message exits 2 with no `orca-ide` call.
- Goal: a valid message reaches `orca-ide` byte for byte.
- Non-goal: any other `loop-status.sh` behaviour, `loop-merge.sh`, templates.

## Decisions

1. **Replace the `-n` check with a pure-bash test `[[ "$message" =~ [^[:space:]] ]]`.** The message is only tested, never trimmed or reassigned, so valid messages are unaltered. No new dependency. Alternative: trim into a variable and test it, rejected because it risks altering the stored message.
2. **Exit code 2 and the same style of stderr message** as the empty case, reworded to "must not be empty or only whitespace".
3. **Add one scenario to `scripts/test-loop-status.sh`** next to the empty-message one: message `"   "` expects exit 2 and no call. A second case with a message that has surrounding spaces expects exit 0 and the exact message passed, covering "not trimmed".

## Risks / Trade-offs

- [Unicode-only whitespace is accepted] → Out of the stated scope; recorded in Open questions.
