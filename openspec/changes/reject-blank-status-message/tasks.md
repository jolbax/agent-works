## 1. Helper

- [x] 1.1 In `scripts/loop-status.sh`, reject a message that is empty or only whitespace with exit 2 before any `orca-ide` call, without altering a valid message. Check: `bash scripts/loop-status.sh in-progress "   " --worktree branch:x; echo $?` prints `2`.

## 2. Test

- [x] 2.1 In `scripts/test-loop-status.sh`, add a scenario for a whitespace-only message (exit 2, no call) and one for a message with surrounding spaces (exit 0, passed unchanged). Check: `bash scripts/test-loop-status.sh` exits 0 and prints both PASS lines.
- [x] 2.2 Confirm the new scenario guards the behaviour. Check: with the new check temporarily removed from `loop-status.sh`, `bash scripts/test-loop-status.sh` exits non-zero; restore it afterwards.

## 3. Verification

- [x] 3.1 Run `openspec validate --all --strict`. Check: exits zero.
- [x] 3.2 Run `BASE=origin/main bash scripts/spec-lock.sh`. Check: exits zero.
- [ ] 3.3 Record in the PR description each command run with its output, and state any check not run. Check: Evidence section present.
