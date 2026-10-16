# Task control

`AppModelTaskControl` owns pause, resume, confirmed results and timeout rollback.
`AppModelLocalTaskControl` selects the authenticated local MCP channel for an exact
local execution, and retains relay routing for other computers and iPhone.
Local preferences change only after a machine confirmation; repeated identical
reads do not invalidate the transcript. A held Task blocks immediate sends on
both platforms. Queueing remains a separate action.

The sibling MCP owns process interruption, durable hook enforcement, provider
context compaction and revision-checked approval grants. Native clients never
modify provider configuration files directly. Tests in `tests/` cover the native
wire and confirmed state; `SessionPauseTests` covers shared optimistic rollback.

See the [engineering contract](../../../../../../AGENTS.md).
