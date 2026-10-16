# Chat approval shortcut

Public entry: `ComposerApprovalButton`, beside attachments on iPhone and Mac.
`ChatApprovalSection` is also used by Task controls. `ChatApprovalPreferences`
reads and changes the same exact-session rule through ApprovalDelivery, including
its matching computer receipt, rejection and timeout handling.

The picker explains ask always, routine approvals, allowing all actions, and the
provider's own approval flow. Existing custom rules remain visible as custom.
Native Codex read-only/workspace/full access is a separate control: an approval
choice never changes a sandbox, another chat, global automation or Mesh denies.
Offline and demo previews cannot grant permissions. A sent rule stays pending
until the owning computer confirms it; global pauses remain visible.

Behavior tests: `GrantTapTests/Features/TaskInterface/Permissions/`.
Cross-platform UI flow: `ComposerApprovalUITests`.
See [AGENTS.md](../../../../../../../AGENTS.md).
