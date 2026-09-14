# Watch task interface

The Watch companion is organized around the same task hierarchy as iPhone:
root chats contain nested agents, approvals stay explicit, and messages retain
their selected provider.

The files separate shared Watch task models, root navigation, chat/approval
controls, activity, session lists, sync state, new-task composition, and
settings. `WatchActionTests.swift` and the shared iPhone runtime tests cover the
wire projections used by these controls; the `GrantTap` scheme compiles both
the Watch app and its host on every `build-for-testing` run.
