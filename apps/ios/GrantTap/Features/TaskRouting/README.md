# Task Routing

[`TaskRoutePresentation.swift`](TaskRoutePresentation.swift) is the public UI
projection for a task's immutable computer route. It keeps provider activity
separate from computer presence: a stale native `working` value can never make
an offline computer look active.

`TaskListCatalog` indexes sessions by Project/Task and executions by Task once
per snapshot. A Task owner already retained in native history opens its chat on
the first tap, with Project/Task/provider/computer scope checked before routing.
The native-session index keeps only the newest record per ID in one pass;
canonical provider IDs match directly, with normalization reserved for aliases.
The Now screen classifies that result once and renders lazy groups;
switching root tabs does not repeatedly scan every execution for every card.
`tests/TaskCatalogPerformanceTests.swift` exercises a 2,000-Task catalog.

The durable delivery route is owned by `MessageOutbox.swift`; compact new-task
controls are in [`../TaskComposer`](../TaskComposer/README.md). Tests live in
`GrantTapTests/Features/TaskRouting`. See [`AGENTS.md`](../../../../../AGENTS.md)
for repository architecture and quality rules.

Working cards say Working now while their route is Live. Event timestamps remain
unchanged and inactive/offline cards label that clock Last activity. Quiet
transcript age alone does not classify a provider-confirmed working Task as
stalled. Connecting routes retain the cached grouping while their cards show
Connecting instead of claiming a new outage.
