# Acceptance and interruption plan

**Status:** planned scenarios only. No runtime, model/provider, recovery, or containment tests have been executed. Documentation validation does not establish these capabilities.

## Representative task

For implementation testing, create a disposable Git fixture containing a small parser with a reproducible malformed-input regression and a behavioral test that fails before repair. The task is to investigate and repair that regression within a bounded scope. The fixture must have a known baseline and no external side effects.

First run the lifecycle with a deterministic execution adapter, then exercise a real selected model through the same public CLI workflow. Deterministic simulation establishes lifecycle behavior only; it does not establish model quality or actual provider behavior.

## Successful first slice

The operator submits the task and repository baseline. Investigation retains its evidence and produces an immutable specification revision. Implementation remains blocked until an approval for that revision is durably recorded. A worker edits only its owned isolated workspace, runs the required behavioral checks, and produces a reviewable local diff.

Retained review evidence includes task/change and attempt identities, approved specification revision, original repository baseline, resulting diff, exact check commands and outcomes, relevant execution records, and limitations. Completion survives restart. Finalization accounts for owned processes and workspaces; the review artifact remains accessible after cleanup.

No remote PR or merge is part of this acceptance gate. A check failure or unresolved effect must not be presented as a successful accepted change.

## Interruption matrix

Inject failures at actual production boundaries using the deterministic adapter before repeating relevant cases against the real execution path. Inspect persisted records and owned resources after restarting the controller.

| Scenario | Required result |
| --- | --- |
| Crash before dispatch | Pending/claimed state remains explainable; recovery establishes whether execution started before redispatch |
| Worker starts, acknowledgment is lost | Stable attempt/execution identity permits reconciliation; no silent second worker |
| Intent persists, effect has not started | Recovery applies that operation's declared policy rather than blindly replaying all tools |
| Effect occurs, result is not persisted | Outcome remains unknown until operation-specific evidence or an operator resolves it |
| Completion persists, acknowledgment is lost | Restart discovers the same terminal outcome without rerunning completed work |
| Approval wait spans restart | Exact revision and decision survive; absence of approval still blocks implementation |
| Scope revision or baseline changes | Old approval cannot silently authorize different scope or an unvalidated new baseline |
| Controller/client disconnect | Display loss is distinguished from execution loss; inspect/reconnect reports current or unknown state honestly |
| Cancellation during active work | No newly unauthorized effects are admitted; owned work settles through finalization |
| Cancellation during final cleanup | Cleanup is not bypassed; pending ownership remains visible and retryable |
| Late worker handshake after cancellation/recovery | Worker is attached or stopped under current ownership; no orphaned resources or stale authority |
| Cleanup partly succeeds, then fails | Successful cleanup is retained; failed resources remain owned; retry addresses remaining work |
| Stale worker returns after replacement | Old generation cannot commit authoritative state or alter the replacement workspace |
| Check fails or model ends early | Preserve partial output and failure evidence; do not claim review readiness |
| Persisting outcome/artifact fails | Live output cannot substitute for durable completion; recovery reports incomplete persistence |

When concurrency and nested execution are introduced, extend this matrix to mixed child outcomes, bounded capacity, and cancellation while accepted nested work is settling.

## Stage-specific gates

- **Foundation:** typed boundaries and deterministic adapter exercise start, inspect, cancellation, and persistence failure through application workflows.
- **First slice:** representative task plus the interruption matrix pass; real-model coverage and unavailable scenarios are reported separately.
- **External integration:** crash after draft PR creation but before result persistence reconciles to the existing PR. External review, CI, and merge remain distinct. Real integration verification requires authorized access.
- **Concurrency:** competing claimers, stale generations, exclusive workspace access, resource limits, and cleanup retry are verified together.

## Verification records and measurements

For every executed scenario record the code revision, environment/tool identities, injection point, expected outcome, observed outcome, evidence locations, and remaining limitations. Report tests as planned, simulated, or executed against a real provider.

Measure completed-task outcome, human interventions, recovery decisions, tokens, elapsed time, CPU, and peak process-family memory where available. Keep cold and warm runs distinct and mark unmeasured values. Establish budgets after the initial baseline, then compare equivalent completed workflows.

For this documentation baseline, validate local Markdown links, evidence references, consistent lifecycle terminology, explicit milestone gates, and the absence of runtime claims.
