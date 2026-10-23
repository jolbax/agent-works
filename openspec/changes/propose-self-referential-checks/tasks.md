## 1. Rule for task checks

- [ ] 1.1 Append the rule to step 2 of `.agents/loop/propose.md` per design decision 1, after "Every task carries a check that can be verified.", naming `loop-start.sh` implement, judge, archive, amend and cleanup and `loop-launch.sh`, the expected-refusal example with exit 6 and `<change-name>-impl`, the target-other-state and stub-simulation alternatives, and the "exactly these" list rule. No other line of the template changes. Check: `grep -n "own workers" .agents/loop/propose.md` and `grep -n "exit 6 because" .agents/loop/propose.md` each match the step 2 line, which also contains `<change-name>-impl`; `grep -nE "agent-works|#33|#37|<change>" .agents/loop/propose.md` prints nothing; with `tmp=$(mktemp)`, `bash scripts/loop-prompt.sh .agents/loop/propose.md "$tmp" owner=o repo=r change-name=c issue-number=1` exits 0 and `grep -c "c-impl" "$tmp"` prints at least 1; `bash scripts/test-loop-prompt.sh` exits 0.
- [ ] 1.2 Add the paragraph per design decision 2 under "### 2. Propose" in `docs/dev-loop.md`: the rule, PR #33 (task 5.2) and PR #37 (task 4.2) as the examples, and that a task that cannot be met stays blocking and the operator settles it with amend. Check: `sed -n '/^### 2. Propose/,/^### 3\./p' docs/dev-loop.md | grep -nE "own workers|#33|#37|amend"` matches each of the four terms.
- [ ] 1.3 Confirm the diff is confined. Check: `git diff --name-only origin/main...HEAD` on the implementation branch prints exactly `.agents/loop/propose.md`, `docs/dev-loop.md` and `openspec/changes/propose-self-referential-checks/tasks.md` (this change's own task ticks; its other artifacts are already on `origin/main`, so they do not appear); in particular `.agents/loop/judge.md` and nothing under `scripts/` or `.github/` appears.

## 2. Verification

- [ ] 2.1 Run every `scripts/test-*.sh`. Check: each exits 0; output in the PR description, labelled as simulations.
- [ ] 2.2 Run `openspec validate --all --strict`, `bash scripts/spec-length.sh openspec/changes/propose-self-referential-checks` and `BASE=origin/main bash scripts/spec-lock.sh`. Check: all exit 0.
- [ ] 2.3 Record in the PR description each command run with its output and any check not run. Check: Evidence and "Not done / not run" sections present.

No task here runs a loop launcher or cleanup for real (design decision 4).
