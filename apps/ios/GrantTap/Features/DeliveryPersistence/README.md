# Reliable delivery persistence

This feature keeps outbound messages durable without silently evicting active
work.

- `DeliveryModels.swift` defines state and lifecycle deadlines.
- `DeliveryStore.swift` performs bounded loading, saving, and admission.
- `DeliveryAdmission.swift` builds compact visible failures and byte-bounds rows.
- `ArchivedSessionStore.swift` retains the local archive index.

The state machine itself lives in `../AppRuntime/Outbox*.swift`. Persistence and
recovery regressions are covered by `GrantTapTests/AppRuntimeTests.swift`.
