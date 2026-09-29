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
The phone's ordinary 300-row limit expands to retain the two most
recent user requests and all intervening replies. If trimming discards older
rows, the native cursor is discarded too, so it cannot silently skip a gap.

`Session/TranscriptArchive.swift` retains full fetched Mac transcripts in separate
files with hashed session ids, atomic writes and platform file protection. It
retains native history cursors, survives relaunch and rejects mismatched records.
The cache can be measured and explicitly cleared without deleting native-provider
logs, credentials or pairings. Tests are in `GrantTapTests/Features/DeliveryPersistence`.
