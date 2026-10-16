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

`TaskHandoffOutcome` matches a new source request to the destination's validated
receipt. `TaskHandoffConfirmationPoller` waits for that receipt and the destination
catalog entry before opening the chat. An uncertain response keeps the operation
pending; checking again only reads its status and cannot submit a duplicate.

The transfer footer stays visible while the form scrolls. A fresh checkout
reading from a resumed native chat can offer a checkpoint even when its previous
execution was closed. Missing readings still block preparation. Cancel closes the
form; preparation failures remain visible there.
