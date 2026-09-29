# Task Composer

Parent index: [`AGENTS.md`](../../../../../AGENTS.md)

[`TaskComposerRouteModel.swift`](Routes/TaskComposerRouteModel.swift) owns the bounded
provider/computer/workspace labels and honest computer availability tone.
[`TaskComposerRoutePicker.swift`](Routes/TaskComposerRoutePicker.swift) renders the
three equal compact menus in the existing bottom composer row.

Provider art is mapped in
[`ProviderIdentity/ProviderArtwork.swift`](../ProviderIdentity/ProviderArtwork.swift)
and stored in `Assets.xcassets`. Tests live in
`GrantTapTests/Features/TaskComposer`; full names remain accessibility labels
even when long English computer/workspace values are visually truncated.

## Model selection

[`Models/TurnModelCatalog.swift`](Models/TurnModelCatalog.swift) selects models
from the exact computer's provider catalog. Codex uses fresh visible metadata
reported by its installed account, including provider descriptions and order.
New model generations require no static Swift enum update. Historical model
observations and stale catalogs cannot claim current availability. Claude's
Opus, Sonnet, Haiku and Fable remain CLI aliases resolved by the installed
provider; their descriptions explain their role and potential usage credits.

[`Models/ComposerModelPill.swift`](Models/ComposerModelPill.swift) provides the
same detailed picker in the composer, Task controls and new Mesh Task screen.
A changed existing-chat model requires confirmation before the stored choice
changes, including a return to a different default. New Tasks have no context
to reload. The next message resumes the existing conversation with the chosen
model, preserving history, identity and permissions; providers can summarize
context to fit their own limits. Cancel keeps the previous choice. Local Mac
and relay messages, including queued messages, carry the chosen model.

Model descriptions do not promise exact cost or correctness. Account limits
and billing remain the provider's responsibility. Guidance:
[OpenAI](https://developers.openai.com/api/docs/guides/latest-model),
[Claude Code](https://code.claude.com/docs/en/model-config).

Tests: `GrantTapTests/Features/TaskComposer/TurnModelCatalogTests.swift` and
`GrantTapUITests/TurnModelPickerUITests.swift`.
