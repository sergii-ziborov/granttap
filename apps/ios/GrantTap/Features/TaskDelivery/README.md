# Task Delivery

[`TaskDeliveryQueue.swift`](TaskDeliveryQueue.swift) owns deterministic FIFO
ordering for the durable phone outbox. Messages retain their original computer,
provider, session, and message IDs while offline; reconnect retries the oldest
eligible message first without creating a second queue.

An unsent offline message can wait up to 24 hours. Its receipt window starts
with its first actual dispatch. Explicit Retry starts a fresh bounded wait for
the same message ID, retaining its original date, route, text and attachments.
These anchors persist across relaunch; pruning cannot discard a just-retried
older message before the computer reconnects.

`ChatMessageQueue.swift` admits explicit follow-ups to that same durable outbox.
Waiting messages open from a compact floating queue control rather than taking
height from the transcript. They
keep their text, attachment bytes, provider, Task, session and computer route
across app restarts. Admission remains bounded by the existing 32 active-message
and encoded-byte limits; an over-capacity request leaves the draft intact.
The queue sheet shows retained messages, full delivery errors, attachment previews,
Send now/Retry and cancellation. Files and nested agent conversations remain
reachable beside the queue; their controls do not reserve a panel below the chat.

`ChatMessageQueuePolicy.swift` releases the oldest waiting follow-up only after
GrantTap receives an idle/finished observation for that execution. Paused,
busy, unavailable and unknown executions remain held. One in-flight or failed
follow-up blocks automatic advancement of that chat. Other chats can advance
independently. Send now releases the selected ID immediately; cancellation
removes an unsent row. Submitted calls cannot be cancelled through that action.
Queue admission time keeps the original order, while the delivery lifetime starts
when a message is released. A long wait therefore does not consume its transport
retry window or attachment preview retention.

`MacQueuedMessageDelivery.swift` uses the existing same-user MCP endpoint and
the persisted delivery UUID. An interrupted local send requires explicit retry
after inspecting the chat. A fresh catalog releases the next message.

The queue belongs to this GrantTap client. It advances while GrantTap can
observe the computer; relaunch resumes retained rows. It does not import the
provider application's independently composed drafts or install a scheduler.
The shared UI lives in `TaskInterface/Chat/Queue`; queue tests live in
`GrantTapTests/Features/TaskDelivery` and `GrantTapUITests/ChatMessageQueueUITests.swift`.

Persistence and retry compatibility remain in `Delivery.swift` and
`MessageOutbox.swift` while those large legacy files are split. Tests live in
`GrantTapTests/Features/TaskRouting`. See [`AGENTS.md`](../../../../../AGENTS.md).

Catalog refreshes and reconnects respect live send generations and persisted
receipt/backoff deadlines. The provider window is ten minutes and the machine
lease eleven minutes; a received processing receipt is non-terminal.
