## Why

`.agents/loop/archive.md` step 1 runs the interactive skill `/opsx:archive <change-name>`, which stops to ask "Sync now / Archive without syncing" and, when tasks are open, asks for confirmation. A headless Orca worker cannot answer and stalls. In the `adopt-sdd-loop` run (#5) the operator had to append a line telling the worker to run `openspec archive adopt-sdd-loop -y` instead. See issue #6.

## What Changes

- The archive prompt template runs `openspec archive <change-name> -y` (non-interactive; verified with `openspec archive --help`: `-y, --yes  Skip confirmation prompts`), not the `/opsx:archive` skill.
- The prompt states explicitly that the worker asks no questions.
- If the change has unchecked tasks, the worker does not archive; it reports them in the PR description under "Not done" and stops, so the operator decides.
- `docs/dev-loop.md` archive step is updated to match.
- The `development-loop` requirement "Archive is a separate openspec-only pull request" gains the headless and unchecked-task behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `development-loop`: only the requirement "Archive is a separate openspec-only pull request" changes. No other requirement is touched, because another change is being proposed in parallel against the same spec.

## Impact

- `.agents/loop/archive.md` and `docs/dev-loop.md` (implementation PR, not this spec PR).
- `openspec/specs/development-loop/spec.md` at archive time.
- No code, CI or `.github/` change. Other templates are out of scope (separate launch-confirmation issue).

## Open questions

- **Step number.** The issue says `docs/dev-loop.md` "step 7"; in the current file the archive step is "### 8. Archive (Claude worker)" (step 7 is Ship). This change assumes the issue means the archive step and edits that one.
- **Detecting unchecked tasks.** The issue does not say how. This change proposes checking `openspec/changes/<change-name>/tasks.md` for unchecked boxes (see design.md); the operator may prefer an openspec command if one exists.
- **Archive with unchecked tasks.** Whether `openspec archive -y` itself refuses open tasks was not verified here; the design assumes it may not, hence the explicit pre-check.
