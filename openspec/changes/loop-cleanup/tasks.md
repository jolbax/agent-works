## 1. Cleanup verb

- [x] 1.1 Add usage for `cleanup` to `scripts/loop-start.sh` (header comment, `usage`, `--dry-run` before or after the verb, any other argument including `--force` exits 2) and exit code 8 to the header. Check: `bash scripts/loop-start.sh cleanup --force` and `bash scripts/loop-start.sh cleanup extra` exit 2; a test scenario asserts both with no stub call logged.
- [x] 1.2 Implement the six rules of design decision 2, in that order, with the keep reasons of its table, after `git fetch origin` and `gh repo view`; a failing call exits 1 before any removal. Check: `bash scripts/test-loop-start.sh` has one scenario per rule (main, current worktree, each non-`completed` status, non-loop name such as `jlb-ideation-phase`, HEAD not on `origin/main`, linked PR OPEN, uncommitted and untracked files), each keeping the worktree with that reason, plus "first failing rule is the reason", "loop worker names" and "fetch or lookup fails", all PASS.
- [x] 1.3 Implement the dry-run listing of design decision 3. Check: test scenario "dry-run listing" PASSes and "nothing changed" asserts the stub log has no `worktree rm`, `git branch`, `git push` or changing `gh` call.
- [x] 1.4 Implement removal and the per-worktree report of design decision 4 (`orca-ide worktree rm --worktree path:<path> --json`, never `--force`; branch deleted or kept; remaining terminals by handle). Check: test scenarios "finished worker removed" and "branch kept and terminal left behind" PASS; `grep -n -- '--force\|git push\|push origin' scripts/loop-start.sh` shows no use in cleanup other than the usage refusal.
- [x] 1.5 Implement stop-on-first-failure with exit 8 (design decision 5). Check: test scenarios "second removal fails" and "removal reported but still listed" PASS with exit 8 and the third worktree not attempted.
- [x] 1.6 Confirm the new checks are guarded. Check: with each of the six rule checks, the still-listed check, and the stop-on-failure removed in turn from `loop-start.sh`, `bash scripts/test-loop-start.sh` exits non-zero; restore after each; record the eight runs in the PR description.

## 2. Status action for spec and archive PRs

- [x] 2.1 Change `status` per design decision 6: the `in-review` "type: approve <sha7>" worktree and its open `spec:`/`archive:` PR both print `ACT: type approve <sha7> in the terminal of <worktree>` when the required check is green on the head, else the "wait for CI" action; a comment sha that is not a prefix of the head leaves the PR line at "no action". Update the existing assertion of "worker waits for the operator" in `scripts/test-loop-start.sh` (it expects the old `ACT in the terminal of add-foo: …` text) to the new text; this is the only existing assertion changed. Check: test scenarios "spec or archive PR awaiting approval, CI green", "… CI not green" (missing, pending and failed), "announced head is not the PR head", and the existing status scenarios PASS; "status is read only" still PASSes.
- [x] 2.2 Confirm the status checks are guarded. Check: with the PR-line action removed, and separately with the CI-green condition removed, `bash scripts/test-loop-start.sh` exits non-zero; restore; record both runs.

## 3. Skill

- [x] 3.1 Add the `cleanup` verb to `.claude/skills/sdd-loop/SKILL.md` per design decision 7 (description triggers on cleanup requests; dry run first, output shown, real run only after the operator's whole message `yes, clean up` in this terminal; never on its own initiative, never `--force`, never `orca-ide worktree rm` or branch deletion directly; exit code 8 listed), and copy it to `.agents/skills/sdd-loop/SKILL.md`. Check: `cmp .claude/skills/sdd-loop/SKILL.md .agents/skills/sdd-loop/SKILL.md` exits 0; `grep -n "cleanup --dry-run\|yes, clean up" .claude/skills/sdd-loop/SKILL.md` matches both; `grep -n -- "--force" .claude/skills/sdd-loop/SKILL.md` matches only the prohibition.

## 4. Documentation

- [x] 4.1 Update `docs/dev-loop.md`: a cleanup step after archive with the skill verb, `loop-start.sh cleanup [--dry-run]`, the rules, the `yes, clean up` confirmation, the per-worktree report, exit code 8, and that remote branches are left to the repository's delete-branch-on-merge setting; add `cleanup` to the skill's request table. Check: `grep -n "cleanup" docs/dev-loop.md` matches in the skill table and in a section after the archive step; `grep -n "delete-branch-on-merge" docs/dev-loop.md` matches.
- [x] 4.2 Update `.agents/loop/README.md` with the same cleanup step after archive, in project-agnostic words. Check: `grep -n "cleanup\|delete-branch-on-merge" .agents/loop/README.md` matches; `grep -rn "agent-works" .agents/loop/*.md` prints nothing.

## 5. Verification

- [x] 5.1 Run every `scripts/test-*.sh`. Check: all exit 0; output in the PR description labelled as simulations.
- [ ] 5.2 Run a REAL `bash scripts/loop-start.sh cleanup --dry-run` from an Orca-registered worktree of the repository, and a real `bash scripts/loop-start.sh status`. Check: the dry run exits 0, lists as `remove` exactly the `completed` loop worktrees of reject-blank-status-message, harden-loop-handoffs and add-sdd-loop-skill, and keeps `main`, `jlb-ideation-phase` and every open worker (including this change's); both outputs are in the PR description, labelled as real runs. The real cleanup is not run.
- [x] 5.3 Run `openspec validate --all --strict`, `bash scripts/spec-length.sh openspec/changes/loop-cleanup` and `BASE=origin/main bash scripts/spec-lock.sh`. Check: all exit 0.
- [x] 5.4 Record in the PR description each command run with its output, the `--help` output of `orca-ide worktree rm` and `orca-ide terminal list`, and any check not run. Check: Evidence and "Not done / not run" sections present.

## Workflow follow-up

- After this change's archive PR is merged, the operator may run the real cleanup through the skill (`/sdd-loop cleanup`, then `yes, clean up`). It is not a task of this change, so the judge can re-run every check above.
