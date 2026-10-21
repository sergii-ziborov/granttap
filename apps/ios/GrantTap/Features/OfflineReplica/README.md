# Offline device replica

Public entry points are `AppModel.syncOfflineConversations`,
`AppModel.messageImageData`, `AppModel.restoreLocalReplica`, and
`AppModel.clearLocalSessionCache`.

Startup restores the linked-computer registry and its saved catalog before
awaiting StoreKit or any transport entitlement. Reading the local replica starts
no relay connections; network control still waits for verified transport access.

Every active conversation is subscribed while the app can run. A fair two-request
queue fetches current heads first, then walks native history cursors without
requiring the user to open the chat. A changed active chat refreshes its head
within the next 30-second scheduling window even while its old pages remain;
the saved oldest cursor is retained so historical backfill continues.
Pages merge by native row identity and remain in protected per-conversation
archives on both iPhone and Mac. Reopening resumes at the persisted oldest cursor.
Transport timeouts and non-advancing cursors back off; they never clear local data.
Completed histories fetch a fresh head when the authenticated catalog reports a
new activity revision. A restart refreshes the head and resumes older pages;
unchanged completed chats do not repeatedly download their whole history.
iOS suspension pauses work and the next catalog/foreground refresh resumes it.
Account reconnection removes demo rows while retaining real catalog rows and
their metadata. Cleanup replaces the SQLite rows within a transaction so a
restart cannot lose the saved catalog between deleting and rewriting the file.

Pictures use the existing authenticated, task-encrypted transport, in bounded
chunks. Already known pictures enter that queue even while older transcript
pages remain pending, so a long history cannot block offline picture storage.
Original validated bytes are retained in Application Support, scoped by
computer and conversation. Fetched Mesh snapshots and their routes also remain
on device. No model call or agent-authored report participates in replication.

Settings clears the replica's transcripts, catalog, pictures and Mesh projection.
There is no automatic day-based expiration of received chats or pictures: they
remain in protected Application Support until the user explicitly clears them.
It preserves identity, pairings, outbound deliveries and computer-enforced policy.
New server updates refill the replica. Stored content is recovery material for
offline reading and continuation; it does not recreate a lost provider process,
working tree or credentials. Content not yet received cannot be recovered locally.

Tests live in `GrantTapTests/Features/OfflineReplica` and the existing DeliveryPersistence test module.

Prefetch and an opened image share one validated transfer. A received image
updates an already visible gallery, and failed previews offer Retry. Clearing
the replica cancels those reads before removing bytes, keeping authentication
and pairing separate from content storage.

`SubmittedImageReplica` archives submitted photo bytes before dispatch, including
Queue → Send now. Local gallery identifiers survive outbox cleanup. A matched
native user turn receives cached image aliases in block order; incomplete or
ambiguous picture groups retain the original preview. Native aliases read the
same device store after the outbox is removed and while offline.

Compatible relays also keep bounded encrypted catalogs, Mesh snapshots and recent
chat heads for reconnect while the computer is offline. This seven-day read
cache is separate from queued commands and the device’s protected offline copy.
Expiry or cache eviction does not cancel queued work. Historical pages and
content never published still require the original computer.
