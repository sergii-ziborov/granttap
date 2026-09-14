# Task interface

This feature folder owns the iPhone Now, Tasks, Usage, chat-first Task, composer,
attachment, approval, pairing, settings, and troubleshooting surfaces.
`ContentView.swift` remains the root coordinator; each component here owns one
visible Personal responsibility.

Behavioral tests live in `GrantTapTests/AppRuntimeTests.swift`, provider/catalog
tests in `SessionCatalogTests.swift`, and end-to-end rendering/delivery is
validated by the Simulator suite. Production files in this folder stay below
300 lines; composed surfaces are split by responsibility.
