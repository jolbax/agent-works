## 1. Verify the interface

- [x] 1.1 Run `--help` for `orca-ide worktree create`, `terminal send`, `terminal read`, `terminal show`. Check: every flag the script uses appears in the output, and the commands and output are pasted in the PR description.
- [x] 1.2 Capture real `--json` output of one real launch and one `terminal send --wait-submit 20 --json` to learn the handle and `turn_started` field names (proposal open question 1). Check: the PR description shows the captured JSON with credentials redacted; if no real launch was run, it says so.

## 2. Helper script

- [x] 2.1 Write `scripts/loop-launch.sh` (bash + `python3`, no other dependencies). Check: `bash -n scripts/loop-launch.sh` exits 0.
- [x] 2.2 Run shellcheck on it. Check: `shellcheck scripts/loop-launch.sh` exits 0, or the PR states shellcheck was not run because it is not installed.
- [x] 2.3 Add a stub-based check with a fake `orca-ide` for the four helper scenarios (delivered, resent once, second failure, no handle). Check: running it reports each scenario and exits non-zero if the helper misbehaves; the PR labels it a simulation.
- [x] 2.4 Run one real launch of a trivial prompt through the helper. Check: the PR shows the printed handle and confirmed `turn_started` stage, or states it was not run.

## 3. Documentation

- [x] 3.1 Use the helper in launch examples in `docs/dev-loop.md` and `.agents/loop/README.md`, keep the manual fallback, and add `scripts/loop-launch.sh` to the reuse checklist. Check: `grep -n loop-launch docs/dev-loop.md .agents/loop/README.md` shows the examples and `grep -n "terminal send" docs/dev-loop.md` still shows the fallback.
- [x] 3.2 Confirm templates still carry no project specifics. Check: `grep -rn agent-works .agents/loop/` prints nothing.

## 4. Validation

- [x] 4.1 Run `openspec validate --all --strict`. Check: exits 0, output in the PR description.
- [x] 4.2 Run `BASE=origin/main bash scripts/spec-lock.sh`. Check: exits 0, output in the PR description; only `scripts/`, `docs/` and `.agents/loop/` and `tasks.md` ticks changed.
