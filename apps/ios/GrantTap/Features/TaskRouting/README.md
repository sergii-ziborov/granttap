# Task Routing

[`TaskRoutePresentation.swift`](TaskRoutePresentation.swift) is the public UI
projection for a task's immutable computer route. It keeps provider activity
separate from computer presence: a stale native `working` value can never make
an offline computer look active.

The durable delivery route is owned by `MessageOutbox.swift`; compact new-task
controls are in [`../TaskComposer`](../TaskComposer/README.md). Tests live in
`GrantTapTests/Features/TaskRouting`. See [`AGENTS.md`](../../../../../AGENTS.md)
for repository architecture and quality rules.
