# Tasks

## 1. Spec-lock regression script

- [x] 1.1 Write `scripts/test-spec-lock.sh` covering the seven scenarios in a throwaway git repo; verify `bash scripts/test-spec-lock.sh` exits 0 and prints each scenario
- [x] 1.2 Mutate a temporary copy of the lock to allow a `proposal.md` edit and verify the script exits non-zero naming the scenario (record command and output)

## 2. Loop documentation

- [x] 2.1 Write `docs/dev-loop.md` (loop, roles, eight rules, per-step `orca-ide`/`openspec`/`gh` commands, failure handling incl. `gh pr edit` workaround and dropped prompts, separation from `docs/architecture.md`); verify every internal link resolves
- [x] 2.2 Add the "Reuse in another Orca project" checklist (copy, adapt, GitHub UI steps); verify it names `openspec/config.yaml`, the `AGENTS.md` section, token scope, the ruleset on `main` and the plan caveat for private repositories
- [x] 2.3 Run `--help` for each `orca-ide` and `openspec` command cited and verify the PR description lists them
- [x] 2.4 Keep in `AGENTS.md` the rule sentences (only tick `tasks.md`; no deleting/weakening tests or changing tooling/test config unless the approved change names it) and add a pointer to `docs/dev-loop.md`; verify with `grep` that those rule sentences are still present and the link exists
- [x] 2.5 Update `AGENTS.md` and `README.md` to call the repository public without selecting a license; verify `grep -in private AGENTS.md README.md` shows no reference to the repository and no license is named

## 3. Prompt templates

- [x] 3.1 Write `.agents/loop/propose.md`, `apply.md` (with MUST-NOT list), `judge.md`, `fix.md`, `archive.md` with `<placeholders>`; verify `grep -ril agent-works .agents/loop` prints nothing
- [x] 3.2 Write `.agents/loop/README.md` mapping each template to its step and command; verify all five templates are listed

## 4. GitHub templates

- [x] 4.1 Add `.github/ISSUE_TEMPLATE/change.md` (name, goal, decisions answered, out of scope, acceptance hints) and `.github/pull_request_template.md` (kind, evidence, judge verdict link, justified config changes); verify the files exist and the lock lists them as a NOTE

## 5. Integration checks

- [x] 5.1 Run `openspec validate --all --strict` and `bash scripts/test-spec-lock.sh`; verify both pass and put commands plus output in the PR description

## Workflow follow-up

- Operator: optionally wire `bash scripts/test-spec-lock.sh` into `.github/workflows/ci.yml`.
- Archive the change in a separate openspec-only PR after the implementation PR merges.
