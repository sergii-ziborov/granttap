# Wire protocol

These files mirror the encrypted payload schemas in
`packages/protocol/schema.ts`, grouped by product domain instead of transport
implementation detail.

- `TransportPayloads.swift` — envelopes, approvals, messages, and task controls.
- `SchedulePayloads.swift` — scheduled-task planning and execution payloads.
- `ActivityPayloads.swift` — chat activity and capability-usage events.
- `SessionCapabilityPayloads.swift` — session keys, MCP, skills, and child chats.
- `SessionInfo.swift` — tolerant session decoding and project grouping.
- `SessionsStatus.swift` — catalog snapshot decoding and row salvage.
- `ConfigurationPayloads.swift` — policy, hello, and outbound factories.

Decoder compatibility and malformed-wire behavior are covered in
`GrantTapTests/SessionCatalogTests.swift` and `GrantTapTests/AppRuntimeTests.swift`.
Run the shared `GrantTap` scheme to compile the iPhone, Watch, and XCTest targets.
