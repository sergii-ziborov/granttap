# Task Composer

Parent index: [`AGENTS.md`](../../../../../AGENTS.md)

[`TaskComposerRouteModel.swift`](TaskComposerRouteModel.swift) owns the bounded
provider/computer/workspace labels and honest computer availability tone.
[`TaskComposerRoutePicker.swift`](TaskComposerRoutePicker.swift) renders the
three equal compact menus in the existing bottom composer row.

Provider art is mapped in
[`ProviderIdentity/ProviderArtwork.swift`](../ProviderIdentity/ProviderArtwork.swift)
and stored in `Assets.xcassets`. Tests live in
`GrantTapTests/Features/TaskComposer`; full names remain accessibility labels
even when long English computer/workspace values are visually truncated.
