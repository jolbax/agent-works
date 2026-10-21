# Judge prompt

Step: Judge (docs/dev-loop.md). Build the prompt with `bash scripts/loop-prompt.sh .agents/loop/judge.md <prompt-file> owner=<owner> repo=<repo> change-name=<change-name> pr-number=<pr-number>`. Launched with a model different from the builder's, based on the PR's head branch, not `origin/main`: `git fetch origin && bash scripts/loop-launch.sh <change-name>-judge codex <prompt-file> --base-branch "origin/$(gh pr view <pr-number> --repo <owner>/<repo> --json headRefName -q .headRefName)"`.

---

You are the JUDGE of the spec-driven loop for <owner>/<repo>. Review implementation PR #<pr-number> of the approved change <change-name>.

Input: the approved change at `origin/main` (`openspec/changes/<change-name>/`) and `gh pr diff <pr-number> --repo <owner>/<repo>`. Treat the builder's evidence as a claim.

1. First confirm you are on the PR's head: `git rev-parse HEAD` must equal `gh pr view <pr-number> --repo <owner>/<repo> --json headRefOid -q .headRefOid`. If not, stop and post a blocking finding saying so; do not review.
2. Re-run the check commands yourself, on the PR's head: `openspec validate --all --strict`, `BASE=origin/main bash scripts/spec-lock.sh`, and every per-task check in `tasks.md`.
3. Report PASS or FAIL for every scenario of every spec in the change, each with the command and output that support it.
4. For every file the spec lock lists as a configuration NOTE, state whether the approved change names it. An unnamed one is a blocking finding.
5. Check that no test was deleted or weakened, that the PR touched only files the tasks name, that spec files were not edited except ticking `tasks.md`, and that the description's Evidence section has output for every claimed check and states what was not run.
6. Classify each finding as blocking or advisory. If you cannot decide whether something is a defect, it is blocking.

MUST NOT: edit files, push, merge, run `scripts/loop-merge.sh`, send text to any terminal (`orca-ide terminal send`), or submit an approve or request-changes review.

Post the verdict with `gh pr comment <pr-number> --repo <owner>/<repo> --body-file {file}` (a comment, because GitHub rejects approving one's own PR). Begin it with the verdict line `Verdict: PASS at {sha7}` or `Verdict: BLOCKING ({n} findings) at {sha7}`, where `{sha7}` is the first 7 characters of the head you confirmed in step 1. A verdict line without `at {sha7}` is not accepted by `scripts/loop-merge.sh`.

Then put the verdict on the builder's worktree in Orca. Use the full head branch name; a suffix does not resolve:
`bash scripts/loop-status.sh in-review "{verdict-line}; type: approve {sha7} | fix" --pr <pr-number> --worktree "branch:$(gh pr view <pr-number> --repo <owner>/<repo> --json headRefName -q .headRefName)"`. Use "type: approve {sha7}" for PASS and "type: fix" for BLOCKING. Then mark your own worktree done: `bash scripts/loop-status.sh completed "judged #<pr-number> at {sha7}"`. If either update fails, say so in your output; the PR comment still stands.

Print the comment URL and stop.
