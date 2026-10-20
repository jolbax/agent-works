# Tasks

## 1. Spec-lock regression script

- [ ] 1.1 Write `scripts/test-spec-lock.sh` covering the seven scenarios in a throwaway git repo; verify `bash scripts/test-spec-lock.sh` exits 0 and prints each scenario
- [ ] 1.2 Mutate a temporary copy of the lock to allow a `proposal.md` edit and verify the script exits non-zero naming the scenario (record command and output)

## 2. Loop documentation

- [ ] 2.1 Write `docs/dev-loop.md` (loop, roles, eight rules, per-step `orca-ide`/`openspec`/`gh` commands, failure handling incl. `gh pr edit` workaround and dropped prompts, separation from `docs/architecture.md`); verify every internal link resolves
- [ ] 2.2 Add the "Reuse in another Orca project" checklist (copy, adapt, GitHub UI steps); verify it names `openspec/config.yaml`, the `AGENTS.md` section, token scope and the rule on `main`
- [ ] 2.3 Run `--help` for each `orca-ide` and `openspec` command cited and verify the PR description lists them
- [ ] 2.4 Replace the workflow paragraph in `AGENTS.md` with a pointer to `docs/dev-loop.md`; verify `git diff AGENTS.md` shows no other rule changed

## 3. Prompt templates

- [ ] 3.1 Write `.agents/loop/propose.md`, `apply.md` (with MUST-NOT list), `judge.md`, `fix.md`, `archive.md` with `<placeholders>`; verify `grep -ril agent-works .agents/loop` prints nothing
- [ ] 3.2 Write `.agents/loop/README.md` mapping each template to its step and command; verify all five templates are listed

## 4. GitHub templates

- [ ] 4.1 Add `.github/ISSUE_TEMPLATE/change.md` (name, goal, decisions answered, out of scope, acceptance hints) and `.github/pull_request_template.md` (kind, evidence, judge verdict link, justified config changes); verify the files exist and the lock lists them as a NOTE

## 5. Integration checks

- [ ] 5.1 Run `openspec validate --all --strict` and `bash scripts/test-spec-lock.sh`; verify both pass and put commands plus output in the PR description

## Workflow follow-up

- Operator: optionally wire `bash scripts/test-spec-lock.sh` into `.github/workflows/ci.yml`.
- Archive the change in a separate openspec-only PR after the implementation PR merges.
