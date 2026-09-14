# Capability catalog

`CapabilityCatalog.swift` models currently available MCP servers and skills as
a snapshot separate from confirmed usage history. Every row keeps the
authenticated computer room, AI provider, and workspace. Child agents are not
capabilities. Global toggles route back to the exact computer that reported the
row.
