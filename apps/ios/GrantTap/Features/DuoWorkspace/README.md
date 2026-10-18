# Duo workspace

[Engineering contract](../../../../../AGENTS.md)

Public entry: `AdaptiveChatWorkspace.swift`.

The conversation and reply surfaces use the native overlay arrangement on iOS
27.1. The system separates them across a partial fold and keeps the reply at
the bottom or trailing edge. Navigation remains outside this arrangement.
The view hierarchy does not switch on hinge angle, so folding preserves the
chat's draft, focus, transcript state and pending approvals.

On a flat screen the reply overlays the conversation. `ChatSurfaceOcclusion`
reserves only the part actually covered at the bottom, without wasting reading
space when the two surfaces occupy separate panes. Earlier iOS versions and
Mac Catalyst keep the existing bottom safe area layout.

Local tests cover bottom overlap, separated book/laptop panes, invalid geometry
and clamping. Native device posture checks complement these geometry tests.
