# Project Mesh

Project Mesh is the Apple client coordination layer above native coding-agent
sessions. It keeps a stable Project and Task identity while Claude Code,
Codex, Cursor, or Grok Build executions move between computers.

Claude Code, Codex, and Cursor expose trusted caller hooks for agent-authored
scoped Mesh events. Grok Build is Experimental and observable where available,
but does not yet expose that trusted hook, so the app never claims authoring
parity. Grok Bot is a separate, explicitly scoped Mesh participant.

Public entry points are `ProjectMeshModels.swift`, `AppModelProjectMesh.swift`,
`ProjectMeshViews.swift`, and the bounded models in
`ProjectGovernanceModels.swift`. The module owns bounded wire validation,
device-protected persistence, explicit cross-computer routing, handoff receipt
verification, the compact Project view, Project management projections, and
curated task timeline rows.

Project management remains additive under the existing Project view. Governance,
Members / Computers, and Mesh status reuse the native list language and never
add a top-level dashboard. Governance becomes editable only after a linked
endpoint reports the full canonical engine policy. The phone preserves custom
rules, sends one next-revision policy under each computer's Project key, and
keeps showing the last confirmed state until the engine publishes its status.
Coverage uses the exact states enforced, observed, unsupported, and unknown, so
a provider without a deterministic hook is never presented as protected.

Only bounded policy, member, binding, and status projections belong on iPhone.
The protected Project Governance cache is separate from the hot Mesh snapshot,
keeps at most 64 Projects, and never becomes the Project database.
Binding rows deliberately omit `localPathHint`; absolute paths and the full
Project graph or memory remain on their endpoint computers.

Mesh traffic is task- or project-key encrypted. The phone grants a scope key to
another linked computer only for an explicit destination. A handoff started in
the app is authorized once; an agent-originated handoff enters Needs You before
the key or capsule is forwarded. The relay never receives project, task,
capsule, claim, question, or decision plaintext.

Technical agent questions and advisory conflicts remain inside the mesh.
Product, business, security, destructive, explicitly unresolved conflict, and
failed-handoff decisions reuse the existing Needs You inbox.

`TaskRouteView` is the Task-first destination. Needs You routes to a Task, not
to a native session, so a Grok Bot actor, an offline computer, a handoff still
in flight, or a session this phone no longer knows all still open. What to do
inside is decided from the current owner: an existing local chat, a human answer
that publishes `AGENT_ANSWER` back to the asking room, or the visible execution
history. A previous native execution is never reopened after ownership moves.

`ProjectMeshConvergence` keeps that identity while snapshots and events arrive
late, twice, and from several computers. Every writer raises the Task
`revision`, the higher one survives a merge, and ties resolve the same way here
and on the machine runtime. A receipt moves ownership only from the session that
owns the Task now, finished work is never reopened by an older event, and an
execution closed by a handoff stays closed even while the native session it left
behind keeps reporting itself.

`TaskHandoffReadiness` runs the pre-flight before the button. A Task Capsule
carries committed facts, so an execution reporting uncommitted work blocks the
handoff here and again on its own computer rather than continuing the Task
elsewhere from committed state alone. Overlapping resource claims, a missing
destination, and a disabled target agent block it the same way; the destination
verifies the commit itself when it accepts. A working tree the owning computer
could not read blocks it too, because "we could not look" is not "clean".

Tests live in `GrantTapTests/Features/ProjectMesh`. See the repository
[`AGENTS.md`](../../../../../AGENTS.md) for the product and quality contract.
