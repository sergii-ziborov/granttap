# Task Delivery

[`TaskDeliveryQueue.swift`](TaskDeliveryQueue.swift) owns deterministic FIFO
ordering for the durable phone outbox. Messages retain their original computer,
provider, session, and message IDs while offline; reconnect retries the oldest
eligible message first without creating a second queue.

`ChatMessageQueue.swift` admits explicit follow-ups to that same durable outbox.
Waiting messages stay above the composer rather than in the transcript. They
keep their text, attachment bytes, provider, Task, session and computer route
across app restarts. Admission remains bounded by the existing 32 active-message
and encoded-byte limits; an over-capacity request leaves the draft intact.
The collapse control stays immediately above the composer in both states, so
changing the visible queue height does not move the control under the pointer.

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
