# Relay task queue

Public entries: `RelayTaskQueueEncoding`, `RelayTaskQueueTransport`, and AppModel's
`queueChatMessage`, `synchronizeRelayTaskQueues` and queue actions. This feature
uses the sibling relay's encrypted task-job API and the standalone MCP receiver.
It does not embed a machine runtime in the Apple application.

An immutable authenticated job carries the chosen model, effort, current Task
route, schedule and complete inline attachments. Its ciphertext is kept in a
private file outside the frequently rewritten outbox metadata. Retries reuse
that exact ciphertext and job ID. The UI reports saving separately from a relay
receipt, so an offline computer does not require an online phone once saved.

Cancellation is confirmed by the relay. An ambiguous upload is reconciled before
cancellation; a missing response cannot justify silently removing a job. A retry
uses a fresh operation only after the old queued or failed job is cancelled.
An accepted job uses the existing chat Stop action. Provider failures and unknown
outcomes remain visible instead of being treated as successful responses.

Send now confirms cancellation of a waiting job before creating a fresh encrypted
operation with `deliveryMode: immediate`. It retains text, images and turn options.
An ambiguous upload is retried with its original ciphertext before cancellation;
an already accepted job is never duplicated. The immediate intent survives app
restart and relay storage. The receiver skips only the idle wait and queue order;
pause, in-flight delivery, provider availability and computer policy still apply.
This wire option requires a compatible MCP receiver (0.8.69 or later).

Scheduled sends are one-time queue operations in the existing chat composer.
Tests mirror this feature under `GrantTapTests/Features/TaskDelivery`.
