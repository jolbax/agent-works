## 1. Prompt helper

- [x] 1.1 Add `scripts/loop-prompt.sh` per the "Launch prompts are built by a helper" requirement. Check: `bash scripts/loop-prompt.sh .agents/loop/propose.md /tmp/p.md owner=o repo=r change-name=c issue-number=1` exits 0 and `/tmp/p.md` has no `<name>` token.
- [x] 1.2 Add `scripts/test-loop-prompt.sh` covering filled, unfilled, Intake selection and runtime-value-untouched scenarios. Check: `bash scripts/test-loop-prompt.sh` exits 0 with a PASS line per scenario.
- [x] 1.3 Confirm the test guards the unfilled-placeholder check. Check: with that check temporarily removed, `bash scripts/test-loop-prompt.sh` exits non-zero; restore afterwards.

## 2. Await helper

- [x] 2.1 Add `scripts/loop-await.sh` per "Workers announce only a confirmed head". Check: `bash scripts/test-loop-await.sh` exits 0.
- [x] 2.2 Add `scripts/test-loop-await.sh` with stub `gh`, `git` and `loop-status.sh` covering head match, head mismatch after the poll limit, both modes and the exact lines. Check: it prints a PASS line per scenario.
- [x] 2.3 Confirm the test guards the head check. Check: with the head comparison temporarily removed, `bash scripts/test-loop-await.sh` exits non-zero; restore afterwards.

## 3. Templates

- [x] 3.1 In every `.agents/loop/*.md`, rename runtime placeholders to `{name}` and keep launch-time ones as `<name>`. Check: `bash scripts/loop-prompt.sh` on every template with its documented keys leaves no `<name>` token and keeps `{merge-commit}` in apply, propose, archive and fix.
- [x] 3.2 Replace each template's own in-review line with `scripts/loop-await.sh {N} approve` (propose, archive) or `judge` (apply, fix). Check: `grep -rn "type: approve" .agents/loop` matches only `judge.md` and wording about the operator's reply.
- [x] 3.3 In apply.md and fix.md, set the round from the count of `Verdict: BLOCKING` comments and stop above 2 with "two fix rounds used; operator decides on GitHub". Check: both files contain the count command and the stop text.

- [x] 3.4 In propose.md, apply.md and archive.md, add the change-request step (make the changes within the MUST-NOT limits, push, run `loop-await.sh {N}` again with the template's mode). Check: `grep -c "loop-await.sh" .agents/loop/{propose,apply,archive}.md` shows at least 2 in each.

- [x] 3.5 In propose.md, tell the worker to keep every requirement text under 500 characters and run `bash scripts/spec-length.sh openspec/changes/{change-name}`. Check: `grep -n "spec-length.sh" .agents/loop/propose.md` matches.
- [x] 3.6 In archive.md, add the shorten-after-sync step (meaning unchanged, diff in `openspec/`, recorded in the PR description). Check: `grep -n "500" .agents/loop/archive.md` matches.

## 3a. Length check

- [x] 3a.1 Add `scripts/spec-length.sh` and `scripts/test-spec-length.sh` (stub change dir: one requirement at 500 characters passes, one at 501, including MODIFIED, fails and is named). Check: `bash scripts/test-spec-length.sh` exits 0; `bash scripts/spec-length.sh openspec/changes/harden-loop-handoffs` exits 0.
- [x] 3a.2 Confirm the test guards the limit. Check: with the comparison removed, `bash scripts/test-spec-length.sh` exits non-zero; restore afterwards.

## 4. Documentation

- [x] 4.1 Update `docs/dev-loop.md` and `.agents/loop/README.md`: loop-prompt.sh usage and documented keys per template, the placeholder convention, loop-await.sh, the round count, the change-request step, spec-length.sh, and the note on Orca's unread marking. Check: `grep -n "loop-prompt.sh\|loop-await.sh" docs/dev-loop.md .agents/loop/README.md` matches both files.

## 5. Verification

- [x] 5.1 Run every `scripts/test-*.sh`. Check: all exit 0.
- [x] 5.2 Run `openspec validate --all --strict`. Check: exits zero.
- [x] 5.3 Run `BASE=origin/main bash scripts/spec-lock.sh`. Check: exits zero.
- [x] 5.4 Record in the PR description each command run with its output, and state any check not run. Check: Evidence section present.
