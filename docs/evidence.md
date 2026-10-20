# Evidence and design provenance

## Source of architectural guidance

The previous investigation statically inspected recovered shipped Droid sources and associated artifacts. The saved primitives catalog describes 15 Software Factory primitives, 16 Droid-agent primitives, eight mappings, and a conditional worked example. Astra reviewed that analysis and subsequently advised the project-start approach summarized below.

These findings are source-derived. Droid was not executed during the investigation; backend internals, production guarantees, effective feature flags, and runtime reachability remain unverified. Source inclusion does not prove active behavior.

## Local references

These absolute paths refer to an existing investigation outside this repository. They are machine-local references and will not travel with a clone. They are retained by reference, not copied.

| Artifact | Use |
| --- | --- |
| [REA report](/home/orca/droid-investigation/droid-rea-report.html) | Consolidated findings and source citations |
| [Architecture report](/home/orca/droid-investigation/droid-architecture.html) | Detailed source-derived architecture views |
| [Primitives catalog](/home/orca/droid-investigation/evidence/astra-primitives.json) | Entity ownership, relationships, lifecycle distinctions, source ranges, and limitations |
| [Orchestration findings](/home/orca/droid-investigation/evidence/orchestration-findings.json) | Agent loop, tool dispatch, concurrency, and local orchestration |
| [Durability findings](/home/orca/droid-investigation/evidence/durability-findings.json) | Transcripts, receipts, selective resume, child identity, and persistence limits |
| [Software Factory findings](/home/orca/droid-investigation/evidence/software-factory-findings.json) | Store contracts, worker pools, dispatch recovery, and backend unknowns |
| [Validation record](/home/orca/droid-investigation/evidence/validation.json) | Saved investigation validation scope; not agent-works runtime verification |

## Findings we can use

- The local runtime owns an explicit model/tool loop and distinct session, turn, and invocation identities.
- Factory work items and stage activities are separate from their execution sessions.
- Transcript identity, terminal receipts, child invocation records, and selective resume provide application-specific recovery mechanisms.
- Software Factory's shipped clients expose meaningful transitions and dispatch recovery, while backend claims and coordinator behavior remain incompletely established.
- Live output, persisted records, durable terminal outcomes, accepted workflow results, and external completion have different meanings.

See the linked evidence for exact source locations and qualifications. This baseline does not claim new runtime observations or create a new REA Evidence record.

## Astra's planning advice

The planning consultation recommended a separate repository, one modular codebase, compact lifecycle contracts, and one crash-tested vertical slice. Build a thin harness and factory together; keep execution behind an adapter. Finish first with a local diff, then introduce draft PR creation as an external effect requiring reconciliation.

This is planning advice from the conversation, not a Droid observation or a separately archived provider verification result.

## Our design choices and unknowns

The TypeScript/Node stack, local-first initial workflow, CLI, module boundaries, staged roadmap, and acceptance gates are agent-works choices. We are not claiming to reconstruct Factory's unobserved backend or match its product quality.

Do not infer a particular database engine, queue, distributed workflow framework, server authorization scheme, lease implementation, or exactly-once external effects from the recovered client contracts. Our concrete choices require decisions and tests of their own.

The investigation archive and recovered source tree remain outside this repository. Do not vendor them into the project. Publication/licensing decisions remain open.
