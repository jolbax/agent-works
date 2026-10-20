## Context

See proposal.md for motivation. The loop launches workers with `orca-ide worktree create --agent <id> --prompt <text>`. `docs/dev-loop.md` currently documents recovery by reading the terminal and resending by hand. `scripts/spec-lock.sh` is the style reference: plain bash, `python3` for JSON, no dependencies.

Facts verified with `--help` (orca-ide 1.4.230): `worktree create` accepts `--name --agent --prompt --base-branch --issue --json` and reports `result.launch` with `launch.outcome.handle`; `terminal send` accepts `--terminal --text --enter --wait-submit <seconds> --retry-request --json`, its result separates input acceptance, observed submission and turn start, and `--wait-submit` never resends on timeout; `terminal read` has `--screen`, `--cursor`; `terminal wait` has `--for exit|tui-idle --timeout-ms`.

## Goals / Non-Goals

**Goals:**
- A launch either confirmed (turn started) or reported failed through the exit code; no silent idle worker.
- At most one resend, so a prompt is never delivered more than twice in the success path.

**Non-Goals:**
- Supervising workers after launch; changing Orca; supporting agents without a terminal handle.

## Decisions

1. **One script, `scripts/loop-launch.sh <name> <agent> <prompt-file> [extra worktree-create args]`.** Reads the prompt from a file (`$(cat file)`) so quoting issues stay out of callers. Alternative: inline `--prompt` text — rejected, templates in `.agents/loop/` are files.
2. **Handle from JSON, not text.** `worktree create --json` is parsed with `python3`; the script fails with a message if no terminal handle is present (for example a chat-kind launch), rather than guessing.
3. **Confirm, then resend once.** After create, check that a turn started (mechanism: see proposal Open question 1). If not, `terminal send --text <prompt> --enter --wait-submit 20 --json` and require stage `turn_started` in its result. Second failure exits non-zero and prints the handle so the operator can inspect. Alternative: loop with retries — rejected; repeated sends of a long prompt can queue duplicates, and issue #7 specifies once.
4. **Ambiguous resend failure is not retried blindly.** If `terminal send` fails at transport level, the script reports the `--retry-request` ID from the error and exits non-zero; it does not resend a new payload. This follows AGENTS.md: an effect whose outcome is unknown stays unknown.
5. **Output is evidence-friendly.** Prints the handle and the observed stage on stdout, diagnostics on stderr.

## Risks / Trade-offs

- [JSON shape undocumented in `--help`] → implementation captures real output and tests parse against it; unrecognized shape fails closed (non-zero).
- [First prompt was delivered but slowly; resend duplicates it] → check waits a bounded time before resending; a duplicate prompt is considered cheaper than an idle worker, and is reported on stderr.
- [Test without launching real workers] → the script reads `orca-ide` through an overridable command variable so a stub can simulate dropped and delivered prompts; real-launch evidence is reported separately from stub results.

## Migration Plan

Additive. Rollback: delete the script and revert the doc examples; manual fallback remains documented.
