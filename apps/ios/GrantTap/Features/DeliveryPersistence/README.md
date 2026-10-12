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
hashed identifiers and atomic writes. It rejects mismatched records. The offline
replication queue and scoped picture storage are owned by `../OfflineReplica`.
Cache cleanup preserves provider logs, credentials, pending deliveries and pairings.
Tests are in `GrantTapTests/Features/DeliveryPersistence` and `Features/OfflineReplica`.
