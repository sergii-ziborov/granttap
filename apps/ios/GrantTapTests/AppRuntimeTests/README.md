# App runtime tests

The `AppRuntimeTests` XCTest case is grouped by behavior so regressions stay
close to their state-machine domain: transport/Watch projection, deferred
delivery, receipt recovery, terminal events, outbox admission and persistence,
pairing/routing/usage, and echo reconciliation with shared fixtures.

All files compile into the `GrantTapTests` target through the shared `GrantTap`
scheme.
