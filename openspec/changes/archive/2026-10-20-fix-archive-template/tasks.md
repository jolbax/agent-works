## 1. Archive template

- [x] 1.1 In `.agents/loop/archive.md`, replace the `/opsx:archive` step with `openspec archive <change-name> -y`. Check: `grep -n "opsx:archive" .agents/loop/archive.md` prints nothing and `openspec archive --help` shows `-y`.
- [x] 1.2 Add the explicit instruction not to ask questions. Check: `grep -n -i "do not ask" .agents/loop/archive.md` prints the line.
- [x] 1.3 Add the unchecked-tasks rule: do not archive, report them under "Not done" in the PR description, stop. Check: `grep -n "Not done" .agents/loop/archive.md` prints the line.
- [x] 1.4 Keep the template free of the repository name. Check: `grep -c "agent-works" .agents/loop/archive.md` prints 0.

## 2. Documentation

- [x] 2.1 Update the archive step ("### 8. Archive") in `docs/dev-loop.md` to match. Check: `grep -n "opsx:archive" docs/dev-loop.md` prints nothing and `grep -n "openspec archive" docs/dev-loop.md` shows the command.

## 3. Verification

- [x] 3.1 Run `openspec validate --all --strict`. Check: exits zero.
- [x] 3.2 Run `BASE=origin/main bash scripts/spec-lock.sh` and `bash scripts/test-spec-lock.sh`. Check: both exit zero.
- [x] 3.3 Record in the PR description each command run with its output, and state any check not run. Check: Evidence section present.
