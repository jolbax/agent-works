## Context

The archive worker is launched headless from `.agents/loop/archive.md` after the implementation PR merges (see proposal.md - Why). `openspec archive --help` lists `-y, --yes` (skip confirmation prompts) and `--skip-specs`; without `--skip-specs` it updates main specs from delta specs.

## Goals / Non-Goals

- Goal: the archive prompt completes with no interactive input.
- Goal: unfinished work is never archived silently.
- Non-goal: changing other templates, `--skip-specs` usage, or the openspec-only diff rule.

## Decisions

1. **Use `openspec archive <change-name> -y`.** It is the non-interactive CLI path and syncs delta specs and moves the change. Alternative: keep `/opsx:archive` and pre-answer prompts, rejected because the prompts are not scriptable.
2. **Explicit "do not ask questions" in the prompt**, consistent with the propose prompt's rule. Anything unresolved goes in the PR description.
3. **Pre-check open tasks before archiving.** The worker looks for unchecked task boxes in `openspec/changes/<change-name>/tasks.md`; if any, it does not run the archive command, opens the draft PR with the list under "Not done" (no archive diff), and stops. Alternative: rely on `openspec archive` to refuse; rejected because `-y` skips confirmations and its behavior with open tasks is unverified.
4. **Update the archive step of `docs/dev-loop.md`** to name the same command and the stop rule, and remove the claim that the skill is equivalent.

## Risks / Trade-offs

- [A draft PR with no diff may be awkward] → The PR description is the report; the operator decides and may close it.
- [Grep for unchecked boxes could mis-detect text in task descriptions] → Match only list-item checkboxes at line start.
