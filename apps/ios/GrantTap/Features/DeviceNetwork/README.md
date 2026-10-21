# Device network

`DeviceEndpointDirectory.resolve` chooses an eligible managed transport or
opens a short-lived encrypted endpoint record with the paired computer's key.
The room, pairing keys, sessions and outbox identities do not change when the
address changes. A rejected or unavailable direct record never authorizes paid
hosted transport. Self-hosted links do not consult the managed directory.

Responses are bounded, redirect forwarding is refused, and expired records,
wrong room identity, tampering, and unsafe addresses are rejected. Polling runs
only while the client wants a foreground connection; iOS does not promise
periodic execution while suspended. Local setup and server processes belong
to the separately maintained MCP runtime.

`RelayReconnect.swift` binds delayed retries to their disconnected generation.
Foreground recovery, route replacement and disconnect invalidate older timers,
so an overdue callback cannot tear down an already recovered socket.

Tests: `GrantTapTests/Features/DeviceNetwork/EndpointDirectoryTests.swift`.

The authenticated WebSocket upgrade advertises the SHA-256 digest of the local
public key. Updated relays use it to select addressed ciphertext, reducing
traffic sent to unrelated controllers. RelayClient checks that hint before
attempting decryption; envelopes from earlier clients remain readable. Room
credentials and encrypted payload authentication remain required.

`RelayPresence` validates optional room-scoped relay device metadata. It is never
passed to agent activity, usage or approval handlers. Existing verified transport
access opens immediately while one background revalidation runs; cold startup
races verified local TestFlight evidence with account access. Unverified evidence
cannot authorize hosted transport. Reading local caches and starting connection
checks no longer wait behind account or storefront requests.
