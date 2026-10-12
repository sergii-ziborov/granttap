# Provider Identity

Parent index: [public source](https://github.com/sergii-ziborov/granttap)

[`ProviderArtwork.swift`](ProviderArtwork.swift) is the single mapping from the
canonical `AgentIdentity` IDs to project-owned Claude, Codex, Cursor,
and Grok artwork in `Assets.xcassets`. Unknown future providers keep the text
glyph fallback instead of being mislabeled with another provider's mark.

Artwork identity is covered by
`GrantTapTests/Features/TaskComposer/TaskComposerRouteModelTests.swift` and used
by the shared `AgentGlyph` plus the compact task composer.
