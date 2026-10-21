# Connection health

This feature separates honest machine freshness from the phone WebSocket state.
`ConnectionSnapshot.swift` defines the phases, `AppModelConnectionHealth.swift`
derives them from authenticated room state, and `SettingsConnectionSection.swift`
renders per-computer QR, reconnect, and unlink controls. `DevicesView.swift`
owns the Devices destination after Usage. It shows the Account Mesh before any
computer is linked, then one row per account MCP machine. QR and passkey rooms
with the same verified machine ID are routes of that row. Phone links and QR
rooms without a verified machine ID remain under Other connections; their
pairings are preserved. A Project Mesh and each Task retain their own route.
The account device roster refreshes when Devices reappears, when the app returns
to the foreground, and on pull to refresh. It keeps known devices visible during
a transient account-service failure and retries secure account pairing when a
new online Mac appears. `AccountDeviceRoster.swift` owns this loading state;
its tests cover late registration, retry, account switching, and sign-out.
`AccountComputerChatStatus.swift` distinguishes an account-visible Mac from an
encrypted pairing, an eligible relay route, and a live chat catalog. The
corresponding tests are in `GrantTapTests/Features/ConnectionHealth`.

Connection routing and multi-computer regressions live in
`GrantTapTests/AppRuntimeTests.swift`.
The header connection pill reports this device’s relay transport. It becomes Live as soon as an authenticated WebSocket opens, independently of computer availability. `ConnectionDetailSheet`
lists one row per verified machine, even when QR and passkey created two routes;
`ComputerConnectionDetailView` shows that machine's own room health, load,
tools, and repair action. Its multi-computer UI test is in `GrantTapUITests`.

`ProviderHookReviewView` shows native Codex hook trust for a selected computer.
A person reviews the full command and hash before confirming one definition.
The request targets that computer and hash; the client accepts success only
from the matching room, endpoint, and request with the same enabled, trusted
native definition. Timeout, modified definitions, and unavailable status do
not claim success. Tests live in `GrantTapTests/Features/ConnectionHealth`.

A new or foreground recovery attempt shows a bounded 15-second Connecting state.
Opening the relay socket ends the header's loader immediately. Computer rows
retain their own authenticated catalog and heartbeat freshness; a connected relay
does not invent a running agent. Saved chats stay visible during recovery.
Relay presence adds room-scoped device connection and last-seen metadata without
turning persisted content into fresh provider activity.
