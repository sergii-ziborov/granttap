# Session catalog

The public Apple-client entry point for account-wide Task visibility is
[`AccountDeviceCatalog.swift`](AccountDeviceCatalog.swift). Each authenticated
GrantTap MCP computer publishes its own catalog. The phone combines reports
from the current account's machines, including a secondary computer, and keeps
each Task's authenticated route to its source computer. A phone or tablet without
MCP does not contribute a machine catalog. QR and passkey links to one machine
are treated as one device facet; a replacement route takes over after its first
catalog arrives.

[`SessionCatalogIngestion.swift`](SessionCatalogIngestion.swift) applies the
combined snapshot and persists the last real Task list. Per-computer policy and
capability settings remain scoped to their source. The module tests are in
[`AppRuntimeTests/Connections`](../../../../GrantTapTests/AppRuntimeTests/Connections)
and [`Verification/Device`](../../../../GrantTapTests/Verification/Device).

See the repository [engineering index](../../../../../../AGENTS.md) for the
quality and security contract.
