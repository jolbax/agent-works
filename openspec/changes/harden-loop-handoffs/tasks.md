## 1. Prompt helper

- [ ] 1.1 Add `scripts/loop-prompt.sh` per the "Launch prompts are built by a helper" requirement. Check: `bash scripts/loop-prompt.sh .agents/loop/propose.md /tmp/p.md owner=o repo=r change-name=c issue-number=1` exits 0 and `/tmp/p.md` has no `<name>` token.
- [ ] 1.2 Add `scripts/test-loop-prompt.sh` covering filled, unfilled, Intake selection and runtime-value-untouched scenarios. Check: `bash scripts/test-loop-prompt.sh` exits 0 with a PASS line per scenario.
- [ ] 1.3 Confirm the test guards the unfilled-placeholder check. Check: with that check temporarily removed, `bash scripts/test-loop-prompt.sh` exits non-zero; restore afterwards.

## 2. Await helper

- [ ] 2.1 Add `scripts/loop-await.sh` per "Workers announce only a confirmed head". Check: `bash scripts/test-loop-await.sh` exits 0.
- [ ] 2.2 Add `scripts/test-loop-await.sh` with stub `gh`, `git` and `loop-status.sh` covering head match, head mismatch after the poll limit, both modes and the exact lines. Check: it prints a PASS line per scenario.
- [ ] 2.3 Confirm the test guards the head check. Check: with the head comparison temporarily removed, `bash scripts/test-loop-await.sh` exits non-zero; restore afterwards.

## 3. Templates

- [ ] 3.1 In every `.agents/loop/*.md`, rename runtime placeholders to `{name}` and keep launch-time ones as `<name>`. Check: `bash scripts/loop-prompt.sh` on every template with its documented keys leaves no `<name>` token and keeps `{merge-commit}` in apply, propose, archive and fix.
- [ ] 3.2 Replace each template's own in-review line with `scripts/loop-await.sh {N} approve` (propose, archive) or `judge` (apply, fix). Check: `grep -rn "type: approve" .agents/loop` matches only `judge.md` and wording about the operator's reply.
- [ ] 3.3 In apply.md and fix.md, set the round from the count of `Verdict: BLOCKING` comments and stop above 2 with "two fix rounds used; operator decides on GitHub". Check: both files contain the count command and the stop text.

## 4. Documentation

- [ ] 4.1 Update `docs/dev-loop.md` and `.agents/loop/README.md`: loop-prompt.sh usage and documented keys per template, the placeholder convention, loop-await.sh, the round count, and the note on Orca's unread marking. Check: `grep -n "loop-prompt.sh\|loop-await.sh" docs/dev-loop.md .agents/loop/README.md` matches both files.

## 5. Verification

- [ ] 5.1 Run every `scripts/test-*.sh`. Check: all exit 0.
- [ ] 5.2 Run `openspec validate --all --strict`. Check: exits zero.
- [ ] 5.3 Run `BASE=origin/main bash scripts/spec-lock.sh`. Check: exits zero.
- [ ] 5.4 Record in the PR description each command run with its output, and state any check not run. Check: Evidence section present.
