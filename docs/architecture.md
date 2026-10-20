# Architecture and lifecycle contracts

This document specifies intended agent-works behavior. No runtime or persistence guarantees are implemented yet. The architectural separation is informed by recovered Droid sources; the proposed contracts below are our design requirements.

## Modules and dependency boundaries

| Owner | Responsibilities | Boundary |
| --- | --- | --- |
| Factory | Workstreams, changes, stage attempts, review decisions, eligible dispatch | Domain transitions request execution through an adapter; model transports and process APIs stay outside domain logic |
| Harness | Sessions, turns, prompt/context assembly, model attempts, tool requests, terminal outcomes | Uses model and tool interfaces; returns execution facts rather than deciding change approval |
| Execution supervision | Process identity, workspace ownership, tool admission, resource bounds, cancellation and cleanup | Validates current authority before effects and retains resources requiring cleanup retry |
| Persistence | Canonical lifecycle records, invocation records, artifacts, recovery queries | Storage implementation must support the selected consistency and durability contract |
| Interfaces | CLI submission, inspection, approvals, cancellation, review presentation | Calls shared application workflows; does not reinterpret raw provider output into separate domain rules |

Domain types and contracts sit inward of application workflows and concrete adapters. Begin with one process hosting modular code, with owned worker processes as required by the selected execution design. Separate services require a demonstrated need.

## Identities and ownership

| Record | Meaning |
| --- | --- |
| Workstream | Continuing goal and operating envelope; one explicit local workstream is sufficient initially |
| Change | Enduring proposed outcome, repository identity, baseline, and current scope revision |
| Stage attempt | A particular investigation or implementation execution; retries retain earlier attempts |
| Specification revision | Immutable investigated scope, evidence references, proposed operations, and checks |
| Approval | Operator decision bound to an exact specification revision and authority scope |
| Session | Continuing conversation/execution identity associated with an attempt |
| Turn | One admitted invocation through a terminal outcome; can contain many model/tool cycles |
| Tool invocation | One admitted operation with identity, intent, observed result, and recovery classification |
| Artifact | Retained content with identity, provenance, and references from lifecycle records |

Change → stage attempts → execution sessions → turns → model/tool cycles is a relationship hierarchy, not a one-to-one mapping. A stage may wait for approval without a live worker. Live events and discovery views are projections of canonical records.

## Lifecycle rules

A change advances through investigation, awaiting scope approval, implementation, and local review readiness. Failures or requests for revision preserve prior attempts and approval history. A failed attempt does not erase or automatically close its change.

A stage attempt progresses from pending to claimed to running, then finalizing and a recorded terminal outcome: succeeded, failed, or canceled. Dispatch ambiguity and unknown tool effects are explicit unresolved conditions, not success or permission to redispatch. Cleanup failure keeps resources owned and prevents claiming finalization complete; the operator can inspect and retry cleanup.

Approval is required for the current specification revision before implementation starts. Scope revisions require new approval. A changed repository baseline blocks dispatch until the approved inputs are validated or a revised specification is approved. Ordinary implementation edits inside the owned workspace are expected outputs, not automatic approval invalidation. The concrete revision and baseline checks must be selected in D5.

A completed turn is execution evidence. The factory separately verifies expected artifacts, checks, and scope before marking an attempt successful or presenting a change as ready for local review. Later PR review, CI, and merge are separate external facts.

## Execution interface

The initial adapter must support these capabilities; exact TypeScript shapes are selected during stage 1:

| Operation | Required behavior |
| --- | --- |
| Start | Accept stable attempt identity, repository/workspace reference, approved specification reference, tool policy, and resource bounds; return execution identity or explicit dispatch uncertainty |
| Observe | Return ordered progress with freshness and execution identity; progress is not durable completion proof |
| Cancel | Request cancellation idempotently; expose ongoing finalization and incomplete cleanup |
| Inspect outcome | Return the canonical terminal outcome and evidence, or explicit running/unknown/unavailable state |
| Recover | Declare supported reattachment, reconciliation, or restart behavior; do not imply arbitrary tool replay |

Repeated starts for the same identity must not silently launch duplicate workers. An unavailable adapter is distinct from an absent execution. Recovery semantics must be verified at the adapter boundary, including when an existing agent runtime is used.

## Persistence and effect boundaries

Select one local transactional authority for workflow and execution metadata before implementation. Artifacts may live outside that store, but references must not report successfully retained content before its persistence boundary is satisfied. Define process-crash and power-loss guarantees separately.

Persist admitted invocation intent before its effect; retain the result afterward. A crash between effect and result creates an unknown outcome. Each operation is classified for safe retry, reattachment, reconciliation, or explicit operator decision. Arbitrary shell effects are never generically replayed.

Use stable identities and worker generations to reject stale authoritative updates. This does not stop stale processes making effects: process supervision, isolated workspace ownership, and external-effect admission must enforce that separately. Lost dispatch acknowledgments require inspecting recorded execution identity before starting another worker.

## Authority and resource lifecycle

Workflow approval authorizes a reviewed scope; tool policy authorizes individual effects. Both must hold at execution time. Instructions in repository content, signals, model output, or retained memory do not grant authority.

A client disconnect does not itself cancel an execution. Cancellation request, worker exit, completed finalization, and completed cleanup are distinct facts. Retain ownership after cleanup failure, and handle late worker handshakes or late results according to the current attempt generation.

Initial isolation, network policy, credential delivery, and enforceable limits must be selected and verified before real target execution. See [D3–D6](decisions.md) and [acceptance scenarios](acceptance.md).
