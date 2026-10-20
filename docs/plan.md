# Goal and delivery plan

## Goal

Build an independently engineered agent harness and Software Factory that converts development requests into bounded, reviewable changes while preserving authority, evidence, and recoverable state across failures.

The initial audience is a developer running locally against an explicitly chosen repository. The design uses one modular TypeScript/Node codebase. The initial interface is a CLI. The project is separate from REA.

Success means a representative task produces a reviewable result and deliberate interruptions leave explainable, recoverable state without silently repeating ambiguous effects. Model quality and operational reliability must be measured rather than inferred from architectural similarity to Droid.

## Delivery stages

| Stage | Deliverable | Observable acceptance gate |
| --- | --- | --- |
| 0 — Documentation baseline | Goal, architecture, lifecycle contracts, evidence index, acceptance plan, decision register | Internal links and evidence references resolve; planned behavior is clearly labeled; no runtime claims |
| 1 — Implementation foundation | Selected toolchain and local store, typed domain boundaries, execution adapter, CLI skeleton, deterministic test execution | Decisions D1–D6 are resolved; a controlled execution can start, report an outcome, and settle cancellation with retained records |
| 2 — First vertical slice | Manual task intake, investigation, revision-bound approval, isolated edits and checks, local review artifact | One representative repository change passes the acceptance matrix, including restart, ambiguous outcome, stale-worker, and cleanup cases |
| 3 — External integration | Draft PR creation and bounded review/CI follow-up | Interrupted creation reconciles by stable identity; review/check states remain distinct; authorized real-provider workflow verified |
| 4 — Concurrency | Multiple workers, bounded scheduling, exclusive workspaces, stale-worker control | Competing workers cannot accept conflicting claims or modify another attempt's workspace; capacity and recovery behavior verified |
| 5 — Broader operation | Scheduled intake/triage, additional models, stage memory, dashboard | Each capability has explicit authority and freshness semantics plus measured completed-task value |

These are dependency gates, not calendar estimates. Build the thin harness and factory together in stages 1–2; do not complete an expansive harness or scheduler in isolation first.

## First workflow

1. The operator submits a bounded task for an explicitly selected repository and baseline revision.
2. Investigation produces a versioned specification, evidence, planned checks, and proposed execution scope.
3. The operator approves that revision; rejection or revision requests remain recorded decisions.
4. A stage attempt acquires an owned isolated workspace and starts a harness session under the approved scope and tool policy.
5. The worker implements and runs the selected checks. Failures, unknown outcomes, and incomplete coverage remain explicit.
6. Finalization retains the diff, check results, source baseline, specification revision, and durable outcome. Workspace disposition is recorded; failed cleanup remains owned for retry.
7. The CLI presents the local review result. No PR or merge is performed in this milestone.

## Scope boundaries

Start with one repository, one worker, one model adapter, manual intake, local execution, and a CLI. Initial approval is explicit human approval of investigated scope. No automatic merge, unattended publication, multiagent delegation, remote execution, organization management, dashboard, or automated intake is required for the first slice.

Keep execution replaceable through a narrow adapter. An existing runtime can validate workflows only to the extent its exposed contracts support observation, cancellation, outcomes, and recovery. A minimal custom model/tool loop remains part of the intended product.

## Progress and measurement

Stage 0 is the current delivery; stages 1–5 are planned. No implementation acceptance tests have run.

For completed workflows retain task outcome, human interventions, recovery decisions, token use, elapsed time, CPU time, and peak process-family memory where measurable. Separate controlled tests from real-provider evidence and cold from warm execution. Set numerical budgets after a representative baseline exists.

Resolve [implementation decisions](decisions.md) before dependent work. Use [the acceptance plan](acceptance.md) as the implementation gates and [the evidence index](evidence.md) to distinguish recovered findings from our choices.
