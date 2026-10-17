# Task transfers

Public entries: `TaskHandoffSheet`, `AppModel.continueTransferredTask`, and
`ChatTransferBanner`. Transfer preparation selects a destination provider/model
and computer while preserving the stable Task identity. The destination starts
with its first message. Source continuation requires computer confirmation for
the current transfer receipt and permits parallel branches.

The standalone MCP owns native execution, worktrees, context capture and
computer policy. The Apple client displays and forwards compatible encrypted
contracts.

`AppModel.canOfferTaskTransfer` is the shared availability entry for the chat
menu and Task controls. All four supported providers use the same Project/Task
and computer requirements. A ready local Mac MCP does not require a phone
pairing merely to offer the transfer form; submission still uses the existing
computer policy and readiness checks.

`TaskCapsuleWireValidation` bounds every capsule the phone accepts, including a
prepared transfer's title, `on_message` launch and context digest, so the
destination's confirmation is not discarded on arrival. Rejoining a split Task
keeps those fields and the receipt's prepared flag.

`TaskHandoffOutcome` matches a new source request to the destination's validated
receipt. `TaskHandoffConfirmationPoller` waits for that receipt and the destination
catalog entry before opening the chat. An uncertain response keeps the operation
pending; checking again only reads its status and cannot submit a duplicate.

The transfer footer stays visible while the form scrolls and states what the move
leaves behind next to the action. A fresh checkout reading from a resumed native
chat can offer a checkpoint even when its previous execution was closed.
Uncommitted or unread work is a warning, never a block. Cancel closes the form;
preparation failures remain visible there.

The destination's Model and Effort pickers list what the destination computer
itself reported for that provider, resolved by the same computer the transfer
goes to (see the TaskComposer README); Automatic is always first, and a computer
or provider that reported no list says so instead of showing a made-up one.
Destinations also include the provider cloud runners of the computer holding the
Task; see [cloud runners](CloudRunners/README.md).
