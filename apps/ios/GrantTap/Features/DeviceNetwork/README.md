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

Tests: `GrantTapTests/Features/DeviceNetwork/EndpointDirectoryTests.swift`.
