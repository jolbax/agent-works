## Context

See proposal.md. Templates in `.agents/loop/` currently mix `<placeholders>` for launch values with ones the worker resolves while running, and each builds its own `in-review` line. `loop-status.sh`, `loop-merge.sh` and `loop-launch.sh` stay unchanged.

## Goals / Non-Goals

- Goal: one mechanical way to fill a template; one place that builds the `in-review` hand-off line.
- Non-goal: changing the three existing helpers, or Orca's unread behaviour.

## Decisions

1. **Two placeholder syntaxes.** `<name>` is launch-time, `{name}` is runtime. After the conversion no runtime value uses angle brackets, so "any `<[a-z][a-z0-9-]*>` left in the body" is exactly "launch-time placeholder unfilled" and the check needs no per-template list. Alternative: a per-template key list in the script, rejected as it drifts from the templates.
2. **`loop-prompt.sh` is plain bash/sed.** Body = lines after the first line that is exactly `---`. Each `key=value` replaces `<key>` literally (no regex or `&` interpretation in values). Intake: keep `Intake: issue #<issue-number>.` when `issue-number` is given and `Intake: brief: <brief>` when `brief` is given; drop the other; neither or both given is an error. Unfilled tokens are listed on stderr, exit 1; usage errors exit 2.
3. **`loop-await.sh` owns the hand-off line.** It polls `gh pr view <pr> --json headRefOid` up to 60 s (interval configurable by env for tests) until it equals `git rev-parse HEAD`; otherwise exit 1 without touching Orca. It then calls `loop-status.sh in-review "<line>" --pr <pr>` and prints the line. A `loop-status.sh` failure exits 1 after printing nothing misleading. Modes: `approve` ("review, then type: approve <sha7>") and `judge` ("ready for the judge (launch it, then wait for its verdict)"). Alternatives: letting templates keep the line, rejected as that caused defects 3 to 5.
4. **Template use.** propose and archive end with `approve`; apply and fix end with `judge`, after their last push. The judge's verdict line remains the only "type: approve" for an implementation PR.
5. **Fix rounds.** On `fix`, the builder counts `Verdict: BLOCKING` comments (`gh pr view --json comments`, bodies starting with the line). That number is the round (`{round}`). Above 2 it sets `in-review` "two fix rounds used; operator decides on GitHub" and does not fix. If the newest verdict is not BLOCKING at the current head, there is nothing to fix and it says so.
6. **Tests** follow `test-loop-status.sh`: stub `gh`, `git` state and `loop-status.sh` path via env, one PASS/FAIL line per scenario.

## Risks / Trade-offs

- [A literal `<word>` in prose is flagged as unfilled] → templates rewrite such uses; the all-templates check in tasks catches them.
- [`{name}` collides with shell braces in templates] → templates contain none outside runtime placeholders; verified by the all-templates check.
- [60 s poll delays a builder if GitHub lags] → bounded, then exit 1 and the builder reports it.
