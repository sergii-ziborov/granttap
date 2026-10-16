# Reliable delivery persistence

This feature keeps outbound messages durable without silently evicting active
work.

- `DeliveryModels.swift` defines state and lifecycle deadlines.
- `DeliveryStore.swift` performs bounded loading, saving, and admission.
- `DeliveryAdmission.swift` builds compact visible failures and byte-bounds rows.
- `Session/ArchivedSessionStore.swift` retains the local archive index.

The state machine itself lives in `../AppRuntime/Outbox*.swift`. Persistence and
recovery regressions are covered by `GrantTapTests/AppRuntimeTests.swift`.

## Transcript storage

`Session/TranscriptRequestBoundary.swift` is the shared request definition for
retention and navigation. Child-agent messages are excluded, and image/file-only
requests count. Adjacent attachment fragments at the same native timestamp belong
to their text request; separate text requests stay separate even at equal times.
Every received message and page remains on both iPhone and Mac until an explicit
cache clear. The former 60-chat / 300-row phone eviction is removed. Native
history cursors survive relaunch, so automatic backfill resumes at the oldest
saved page without dropping earlier turns.

`Session/TranscriptArchive.swift` stores protected per-conversation files with
hashed identifiers and atomic writes. It rejects mismatched records.
`TranscriptArchiveWriter` serializes encoding and disk writes on a utility queue,
coalescing pending snapshots per chat without dropping another chat or an older
page contained in the full snapshot. Reading and explicit cleanup wait for that
queue, so cleared files cannot be resurrected by a pending write. iOS requests
a bounded background task to finish queued writes before suspension. Remote-wake
completion is acknowledged only after those writes finish, so the APNs lease
does not end while a received page is still waiting to be saved. The offline
replication queue and scoped picture storage are owned by `../OfflineReplica`.
Cache cleanup preserves provider logs, credentials, pending deliveries and pairings.
Tests are in `GrantTapTests/Features/DeliveryPersistence` and `Features/OfflineReplica`.
