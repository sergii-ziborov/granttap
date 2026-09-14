# Task Delivery

[`TaskDeliveryQueue.swift`](TaskDeliveryQueue.swift) owns deterministic FIFO
ordering for the durable phone outbox. Messages retain their original computer,
provider, session, and message IDs while offline; reconnect retries the oldest
eligible message first without creating a second queue.

Persistence and retry compatibility remain in `Delivery.swift` and
`MessageOutbox.swift` while those large legacy files are split. Tests live in
`GrantTapTests/Features/TaskRouting`. See [`AGENTS.md`](../../../../../AGENTS.md).
