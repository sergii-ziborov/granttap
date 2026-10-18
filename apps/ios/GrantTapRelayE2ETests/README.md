# Encrypted relay device verification

Dedicated opt-in integration scheme. A synthetic computer publishes four
provider-labelled sessions to a loopback relay without running provider commands.
Use a fresh, dedicated simulator and the normal ad hoc simulator signing.
Run `GrantTap Relay E2E` with `-only-testing:GrantTapRelaySetupTests` to save its
synthetic pairing through the application's secure persistence. Run the same
scheme with `-only-testing:GrantTapRelayE2ETests` on that simulator afterwards.
The fixture's loopback `/pairing-json` endpoint must never be publicly exposed.
Keep keys out of logs. Never use this setup target on the physical owner device.

The computer disconnects after its catalog and approval cards are published.
The UI test saves four approvals and four messages plus a queued task while it is offline and checks
that relay acknowledgment takes less than six seconds. Reconnect the fixture
only after the app exits to verify delivery without a running phone.

The normal release UI suite does not depend on this external fixture. See the
[root engineering contract](../../../AGENTS.md).
