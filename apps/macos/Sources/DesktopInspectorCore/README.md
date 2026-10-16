# DesktopInspectorCore

`InspectorService.swift` is the public read-only entry point. `EngineCodec.swift`
owns the bounded protocol-v1 request and response checks. `EngineClient.swift`
owns one local Unix-socket request at a time, a monotonic deadline, partial IO,
and owner/mode checks. `LocalMCPStatus.swift` discovers the MCP-owned local
channel; `MeshProjectSnapshot.swift` validates bounded Task state from it.
These files do not import the machine runtime or persist Project state.
`project.resolve(local_root)` resolves an existing bound folder to a Project
ID without creating a Project in the desktop app.

`InspectorHistory.swift` describes Knowledge and invocation evidence.
`EngineHistoryCodec.swift` checks Project and Task scope, page bounds, and
cursor order before either history reaches the UI. Project-only Knowledge
requests exclude Task-private records; an explicit Task ID enables that Task's
records. Source labels do not claim verified outcomes.

`InspectorPolicyCoverage.swift` and `EngineCoverageCodec.swift` read current
policy coverage receipts. The result must match the selected Project and the
policy revision returned in the same inspector read; stale endpoint receipts
are not displayed as current coverage.

Tests live in `../../Tests/DesktopInspectorCoreTests`. See the [desktop module](../../README.md)
and repository [AGENTS.md](../../../../AGENTS.md).
