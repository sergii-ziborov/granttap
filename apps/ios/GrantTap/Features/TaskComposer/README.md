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

The shared `ProviderAccountUsage` projection renders independently reported
subscription windows with freshness and reset times. All four provider model
IDs remain provider-scoped. Usage model rows open the sessions they counted;
missing limits are not reported as unlimited or zero use.

Effort is selected in the same model popover on iPhone and Mac, persisted per
chat with provider defaults, and carried by queued and immediate turns.
Codex levels come from the installed account's selected-model metadata;
Claude and Grok use their native effort flags. Cursor advertises reasoning
variants as separate model IDs. Unknown account quota remains unknown.

The shared [animated Effort control](Models/EffortControl/README.md) supports
touch, pointer, arrow keys and accessibility. Extra High, Maximum and Ultra have
distinct particle/pixel treatments. The current chat's reported effort is shown
when no override or provider default is set. Reduce Motion stops animation.
The model popover uses the same explicit Done header on both clients.
`ComposerModelPicker` owns the pending model confirmation inside the presented
view, so Catalyst can show the context warning and keep a canceled choice.

The home composer resolves model and effort before admitting either a new Task
or a continuation into the durable outbox. MCP question replies keep their
request scope and carry no turn override.

## Which computer's models

`AppModel.catalogEndpoint(forRoom:)` is the one rule for the computer a room
reaches, used by the composers, chat overrides and **Transfer to** alike, and by
the transfer itself: the computer's own status report (`endpointId` on its
integration rows) first, then the Project snapshots it published — the one with
the freshest model catalog when an old name is still mapped — then its chats.
Before, a room had to map to exactly one snapshot publisher, so after a relaunch
or with a former computer name the picker fell back to Automatic for Codex,
Cursor and Grok Build. Grok Build rows carry their own reasoning levels, up to
Extra High. An unreported list is said in words; Automatic stays the default and
nothing is invented. A transfer's chosen model and effort are stored for the
new chat, so its first message carries them even when the agent has a default.
Tests: `GrantTapTests/Features/ProjectMesh/Tasks/TaskHandoffModelChoiceTests.swift`.
