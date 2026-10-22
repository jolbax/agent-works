## 1. Launcher script

- [x] 1.1 Add `scripts/loop-start.sh` with usage parsing, `git fetch origin`, owner/repo/default-branch derivation and the layout table of design decision 3 for `start`, `implement`, `judge` and `archive`, building the prompt with `loop-prompt.sh` into a `mktemp` file and launching with `loop-launch.sh`. Check: `bash scripts/loop-start.sh` with no arguments exits 2; `bash scripts/loop-start.sh --dry-run start dry-run-probe --brief "probe"` exits 0 and prints a prompt path outside the repository and a `loop-launch.sh dry-run-probe claude … --base-branch origin/main` command, and no `dry-run-probe` worktree or branch exists afterwards.
- [x] 1.2 Add the refusal checks with exit codes 3–7 per "Launcher refuses what it cannot derive", each before any launch. Check: `bash scripts/loop-start.sh --dry-run implement no-such-change` exits 3; `bash scripts/loop-start.sh --dry-run archive add-sdd-loop-skill` exits 5; `bash scripts/loop-start.sh --dry-run implement harden-loop-handoffs` exits 6 (spec PR #22 is merged, and the `harden-loop-handoffs-impl` worktree exists).
- [x] 1.3 Add the next-free judge number and the name-taken check against `orca-ide worktree list` and local and `origin` branches. Check: covered by 2.1 scenarios "Next free judge number" and "Name already taken".
- [x] 1.4 Add `status` per "Status names where the operator acts", read-only. Check: `bash scripts/loop-start.sh status` exits 0 and lists every non-main agent-works worktree that is not `completed`, and every open loop PR; its output is in the PR description.
- [x] 1.5 Confirm the script holds no merge or approval authority. Check: `grep -nE 'loop-merge.sh|gh pr merge|gh pr ready|terminal send|worktree set' scripts/loop-start.sh` prints nothing.

## 2. Launcher test

- [x] 2.1 Add `scripts/test-loop-start.sh` with stub `gh`, `git`, `orca-ide`, `loop-prompt.sh` and `loop-launch.sh`, covering every scenario of "Launcher derives launch-time values from GitHub", "Launcher uses the documented worker layout", "Launcher refuses what it cannot derive", "Launcher dry run launches nothing" and "Status names where the operator acts". Check: `bash scripts/test-loop-start.sh` exits 0 with a PASS line per scenario.
- [x] 2.2 Confirm the test guards the checks. Check: with the merged-state check for `implement` temporarily removed, and separately with the name-taken check removed, `bash scripts/test-loop-start.sh` exits non-zero; restore afterwards and record both runs.

## 3. Skill

- [x] 3.1 Add `.claude/skills/sdd-loop/SKILL.md` (name `sdd-loop`, a description that triggers on start/implement/judge/archive/status requests) mapping each verb to one `loop-start.sh` command, telling the agent to report the script's output, to remind the operator that `approve <sha>` and `fix` are typed in the worker's own terminal, and never to approve, merge, run `loop-merge.sh`, send to a terminal or edit files. Check: `grep -c "loop-start.sh" .claude/skills/sdd-loop/SKILL.md` is at least 5 and `grep -n "^name: sdd-loop$" .claude/skills/sdd-loop/SKILL.md` matches.
- [x] 3.2 Copy it to `.agents/skills/sdd-loop/SKILL.md`. Check: `cmp .claude/skills/sdd-loop/SKILL.md .agents/skills/sdd-loop/SKILL.md` exits 0.

## 4. Documentation

- [x] 4.1 Update `docs/dev-loop.md`: each step's start (intake/propose, implement, judge, archive) names the skill verb first, a short section describes the skill, `loop-start.sh`, `--dry-run`, `status` and its exit codes, the manual `loop-prompt.sh`/`loop-launch.sh` commands stay labelled as the fallback, and the reuse checklist lists the two SKILL.md files, `loop-start.sh` and `test-loop-start.sh`. Check: `grep -n "sdd-loop\|loop-start.sh" docs/dev-loop.md` matches in each step section and in the reuse checklist; `grep -n "fallback" docs/dev-loop.md` matches.
- [x] 4.2 Update `.agents/loop/README.md`: the table's "Launched with" column names the skill verb first and keeps the manual command as the fallback. Check: `grep -n "sdd-loop\|loop-start.sh" .agents/loop/README.md` matches; `grep -rn "agent-works" .agents/loop/*.md` prints nothing.

## 5. Verification

- [x] 5.1 Run every `scripts/test-*.sh`. Check: all exit 0.
- [x] 5.2 Run a real `bash scripts/loop-start.sh status`, a real `bash scripts/loop-start.sh --dry-run start dry-run-probe --brief "probe"`, and a real `bash scripts/loop-start.sh --dry-run implement harden-loop-handoffs`. Check: the first two exit 0 and the third exits 6; all output is in the PR description, labelled as real runs, separately from the simulated test output.
- [x] 5.3 Run `openspec validate --all --strict` and `bash scripts/spec-length.sh openspec/changes/add-sdd-loop-skill`. Check: both exit 0.
- [x] 5.4 Run `BASE=origin/main bash scripts/spec-lock.sh`. Check: exits 0.
- [x] 5.5 Record in the PR description each command run with its output, the `--help` output of every `orca-ide` command `loop-start.sh` uses, and any check not run. Check: Evidence and "Not done / not run" sections present.
