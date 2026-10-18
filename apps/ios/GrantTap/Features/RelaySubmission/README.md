# Relay submission

[Engineering contract](../../../../../AGENTS.md)

Public entries: `RelaySubmissionReceipt`, `RelaySubmissionTracker`, and the
`RelayClient` submission transport extension.

Explicit messages, approval decisions and attachment uploads use stable outer
delivery IDs. The phone requests relay control frames and completes submission
only on `relay.stored`, emitted after durable persistence by a compatible relay.
An MCP computer is not required to be online. This receipt confirms storage;
native delivery, approval and execution retain their own authenticated receipts.

The bounded, thread-safe tracker completes each registered attempt once. Retry
attempts for the same immutable ID share its storage receipt. Old timers cannot
expire a newer attempt. Disconnect and storage failure leave the durable client
outbox available for retry. Completions run outside its lock.

Local tests cover correlation, retries, expiry, capacity and reentrant callbacks.
