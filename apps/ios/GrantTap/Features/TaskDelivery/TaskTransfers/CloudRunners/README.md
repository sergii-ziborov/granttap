# Cloud runners

Public entries: `TaskHandoffCloudTarget`, `ProjectMeshCloudLaunch`,
`ExternalExecution`, `CloudHandoffOutcome`, `CloudRunStartedNote` and
`CloudRunLink`. Back to the [engineering index](../../../../../../../AGENTS.md)
and the [task transfers](../README.md) it extends.

**Transfer to** lists a provider's cloud runner under the computer that will
start it — "Claude cloud · via MacBook", "Codex Cloud · via MacBook" — only for
the computer that holds the Task, and only when that computer's status report
says its installed CLI can start the runner without a terminal (`cloud: true`
on the `claude`/`codex` integration row). Older computers say nothing and offer
nothing. On the Mac, the app's own computer is recognised through its paired
room's report.

Choosing a runner sends the ordinary transfer request with `cloud`: Claude
cloud takes the chosen alias and effort; Codex Cloud runs its environment's
model and takes an optional environment name instead. Pushing the branch is
switched on, because a cloud runner only sees what the remote has; a readiness
row warns while it is off. Uncommitted work is warned about exactly as for a
computer transfer, and the readiness, comment and checkpoint rules are the same.

`CloudHandoffOutcome` reads the result from the Project snapshot: the external
execution the computer recorded for this Task after the request, or the
computer's `TASK_BLOCKED` reason in the CLI's own words. It never opens a chat.
The sheet then shows the run's link; the Task route lists the run with its link,
when it started, and that GrantTap cannot follow its progress. No state, usage or
"last active" time is invented for it.

The computer side is the MCP's `cloud-runners` module.

Tests: [`../tests/CloudRunnerTests.swift`](../tests/CloudRunnerTests.swift) and
[`TaskHandoffModelChoiceTests.swift`](../../../../../GrantTapTests/Features/ProjectMesh/Tasks/TaskHandoffModelChoiceTests.swift).
