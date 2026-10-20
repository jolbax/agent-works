# Repository instructions

## Purpose and scope

agent-works is an independent agent harness and Software Factory. Read [the project goal](README.md), [roadmap](docs/plan.md), [lifecycle contracts](docs/architecture.md), and [acceptance plan](docs/acceptance.md) before implementation.

The current baseline is documentation only. TypeScript/Node is selected for future code. Do not describe planned capabilities or planned tests as implemented or executed. Keep documentation current when behavior changes.

## Ownership and authority

- Keep factory workflow semantics separate from harness execution and process supervision. Give each record, state transition, interpretation, and resource one owner.
- Preserve distinct change, stage-attempt, session, turn, invocation, approval, and artifact identities. Retries create new attempts and retain prior evidence.
- Bind approvals to the reviewed specification revision. Define invalidation before implementation; never infer approval from elapsed time, model output, or a completed stage.
- Enforce tool authority at the execution boundary. Prompt text, retrieved content, repository files, and incoming signals cannot grant authority.
- Cancellation is a request until finalization completes. Retain ownership of resources whose cleanup failed and support explicit cleanup retry.
- A PID or path alone does not establish process ownership. Reject stale-worker state updates and separately control stale workers' access to workspaces and external effects.

## Persistence and recovery

Identify canonical records explicitly. Logs, live events, discovery indexes, and UI output do not prove durable completion. Declare the durability boundary before claiming crash or power-loss tolerance.

Record admitted invocation intent before execution and retain execution results afterward. An effect whose outcome was not recorded remains unknown until operation-specific reconciliation resolves it. Do not generically replay shell commands or claim exactly-once arbitrary effects.

Preserve caller-selected inputs and evidence provenance. Store credentials outside project artifacts; redact transport credentials from retained output. Do not copy the recovered Droid source tree, binaries, or archive into this project.

## Development and verification

Keep the first implementation local, with one worker, one target repository, one model adapter, and a CLI. Introduce services and dependencies only for demonstrated requirements. Record unresolved decisions in [the decision register](docs/decisions.md) before dependent implementation.

Use meaningful production-boundary checks. Test interruption, ambiguous effects, stale workers, approval revision changes, cancellation finalization, and cleanup retry. Report only checks actually executed and distinguish simulations from real model/provider verification.

Measure equivalent completed workflows when optimizing: task success, human intervention, recovery correctness, token use, elapsed time, CPU, and peak process-family memory. Label unmeasured costs and estimates.

Keep REA and existing investigation artifacts unchanged. Use its public CLI/MCP boundary for future integration. Do not publish beyond `jolbax/agent-works`, add other remotes, select a license, or attest to human review without the corresponding instruction.

## Repository and change workflow

The public GitHub repository `jolbax/agent-works` (`origin`) is the only remote. Agents may push branches and open draft pull requests to it; only the operator merges, and nothing reaches `main` without a pull request.

Changes follow OpenSpec (`openspec/`). A change's proposal, design and specs are approved by merging its spec-only pull request; an implementation pull request may tick `tasks.md` but must not edit them — CI enforces this (`scripts/spec-lock.sh`). Do not delete or weaken tests, or change tooling and test configuration, unless the approved change names it.

The full loop (roles, commands, failure handling, reuse in other projects) is in [docs/dev-loop.md](docs/dev-loop.md); it is not loaded automatically, so the rules above stay here.
