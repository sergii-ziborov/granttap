# Task Delivery

[`TaskDeliveryQueue.swift`](TaskDeliveryQueue.swift) owns deterministic FIFO
ordering for the durable phone outbox. Messages retain their original computer,
provider, session, and message IDs while offline; reconnect retries the oldest
eligible message first without creating a second queue.

An unsent offline message can wait up to 24 hours. Its receipt window starts
with its first actual dispatch. Explicit Retry starts a fresh bounded wait for
the same message ID after transport failure, retaining its original date, route, text and attachments.
An authenticated computer refusal is terminal: explicit user Retry creates a new
operation ID and renames the retained local bubble without duplicating it.
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

New queues use the encrypted durable relay queue described in
[`RelayTaskQueue/README.md`](RelayTaskQueue/README.md). They survive a closed app
or an offline computer. Legacy client-managed rows resume when this client can
observe the computer. Neither path imports drafts composed in the provider app.
The shared UI lives in `TaskInterface/Chat/Queue`; recovery tests live in
`TaskDelivery/tests`, legacy queue tests in `GrantTapTests/Features/TaskDelivery` and `GrantTapUITests/ChatMessageQueueUITests.swift`.

Persistence and retry compatibility remain in `Delivery.swift` and
`MessageOutbox.swift` while those large legacy files are split. Tests live in
`GrantTapTests/Features/TaskRouting`. See [`AGENTS.md`](../../../../../AGENTS.md).

Catalog refreshes and reconnects respect live send generations and persisted
receipt/backoff deadlines. The provider window is ten minutes and the machine
lease eleven minutes; a received processing receipt is non-terminal.

`NativeDeliveryConfirmation.swift` retires a message once its own user entry is
confirmed in the native transcript, independently of turn completion. Matching
is scoped to computer, provider, session and dispatch time, consumes each native
entry once, and persists that binding across restart. Late receipts and old
processing timers cannot revive a completed row. `LegacyQueueRecovery.swift`
checks a submitted legacy message by refreshing its native history; it never
resubmits uncertain work, even after a computer's dedupe lease expires. A confirmed
computer refusal gets a fresh ID on explicit Retry, with one retained bubble.

`DeliveryCancellation.swift` removes failed or never-submitted deliveries and
their local retry lifecycle from the chat and Needs You. Already-running agent
work is controlled by Pause. Cancellation of relay-managed queue rows still
requires the relay's durable cancellation receipt.
