# Implementation decision register

This register makes open implementation decisions explicit. It is not a list of implemented capabilities. Resolve each decision before dependent code is introduced, recording the selected option, rationale, alternatives, and acceptance evidence in a short decision record.

## Established choices

- Project: `agent-works`, separate from REA, with one local repository and modular codebase.
- Initial delivery: documentation only; future implementation uses TypeScript/Node.
- Initial operation: one developer, explicitly chosen repository, one worker, one model adapter, CLI, manual task intake, explicit specification approval, local review artifacts.
- Product intent includes a custom model/tool harness. Keep execution behind an adapter so lifecycle tests can use controlled execution and existing runtimes can be evaluated honestly.
- No remote, publication, license choice, dependency installation, or executable scaffold is part of the documentation baseline.

## Required before the first implementation slice

| ID | Decision | Required resolution | Gate |
| --- | --- | --- | --- |
| D1 | Toolchain and development workflow | Pin Node, package manager, TypeScript, test/check commands, and dependency policy | Before executable scaffolding |
| D2 | Canonical persistence and durability | Select local transactional store, artifact layout, schema evolution, atomic boundaries, and process-crash versus power-loss contract | Before lifecycle persistence |
| D3 | Model and execution adapter | Select first provider and credentials delivery; define exact start/observe/cancel/outcome/recovery types and error semantics | Before real inference and dispatch |
| D4 | Workspace and process ownership | Select isolation strategy, baseline verification, worker identity, late-handshake handling, generation fencing, resource bounds, and cleanup retry | Before target mutation |
| D5 | Approval and workflow transitions | Finalize typed states, revision binding, approval invalidation, dispatch eligibility, and unresolved-outcome handling | Before state machine implementation |
| D6 | Tool authority and containment | Select initial tools and enforceable filesystem/network/process policy, credential boundaries, and per-operation recovery classes | Before real tool effects |

Dependency direction is already fixed: domain contracts inward, shared workflows above them, concrete model/store/execution adapters outward, and interfaces calling the workflows. The decisions refine that architecture rather than opening a separate-services redesign by default.

## Later decisions

Before stage 3, choose Git-provider integration, stable remote operation identity, reconciliation queries, credential scope, and bounded review behavior. Before stage 4, define claim/lease semantics, concurrent workspace capacity, and stale-process effect control. Before stage 5, choose intake sources, memory retention, model-selection policy, and dashboard freshness rules.

Decide licensing before sharing or publishing the project. Do not infer rights to redistribute recovered source or archives from their availability in the local investigation.

## Decision record format

Each record should state the problem, selected behavior, owner and public interfaces affected, alternatives and tradeoff, recovery/authority consequences, and the tests required to validate it. Update the architecture and acceptance plan when a decision changes their contracts. Unresolved entries remain visible rather than being silently selected by an implementer.
