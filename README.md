# agent-works

An agent harness and Software Factory for turning development requests into investigated, approved, implemented, and reviewable changes, with explicit execution authority, retained evidence, and recoverable state.

**Status:** documentation baseline. No runtime, model connection, scheduler, sandbox, or recovery behavior is implemented. TypeScript/Node is the selected implementation stack; exact versions and dependencies remain to be selected before coding.

## Initial audience and workflow

The initial user is a developer operating locally on one explicitly selected repository. Start with one worker and one model adapter, controlled through a CLI.

The first implementation milestone is:

> Manually supplied task → investigation → persisted scope approval → isolated implementation → checks → reviewable local diff, retained evidence, and durable outcome.

A useful first result must survive interruption with explainable state. One successful uninterrupted task is insufficient to establish recovery correctness.

## Architecture

One modular codebase separates enduring factory work from individual agent executions. The factory owns workstreams, changes, stage attempts, approvals, and scheduling. The harness owns sessions, turns, model/tool cycles, and execution outcomes. Execution supervision owns processes and workspaces; persistence owns canonical records and recovery data. Interfaces present and control these capabilities.

REA remains a separate reverse-engineering product. Future investigation tasks may call its existing CLI/MCP interface; this project does not extend REA's execution authority.

## Project documents

- [Overall plan and milestones](docs/plan.md)
- [Architecture and lifecycle contracts](docs/architecture.md)
- [Acceptance and interruption plan](docs/acceptance.md)
- [Evidence and design provenance](docs/evidence.md)
- [Open implementation decisions](docs/decisions.md)
- [Contributor and agent instructions](AGENTS.md)

The design draws on static Droid analysis and Astra's planning advice. Recovered behavior, proposed design, and unverified guarantees are distinct. See the evidence index before making claims about Droid.

## Working here

Refine the contracts and acceptance scenarios before adding runtime code. Resolve the decisions required by each milestone and record the rationale. No install, build, or run command exists yet. The private GitHub repository `jolbax/agent-works` is the remote; changes go through OpenSpec and pull requests (see [AGENTS.md](AGENTS.md)). No license is selected; publication beyond that private repository requires an explicit licensing decision.
