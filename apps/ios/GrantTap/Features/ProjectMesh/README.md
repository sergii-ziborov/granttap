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

The shared Mesh list groups Projects by reported repository identities from
their canonical repository, scoped bindings, and their own Task executions.
Historical executions retain those links. Shared non-canonical repositories
also connect groups, while names, paths, and shared computers do not. Weavatrix
relations with positive evidence produce Solution groups; repository membership
alone produces linked groups. Every member retains its Project identity,
navigation destination, Tasks, and access scope on Mac, iPad and iPhone.
The pinned Mesh / Repositories switch also exposes a repository index with every
original Mesh scope and its chat executions. Mesh chat rows show reported
repository identity and branch independently of their title. Current ownership,
historical executions, ambiguity and missing Git evidence use the shared
assignment algorithm in the [repository catalog](RepositoryCatalog/README.md).

A local parent workspace without confirmed Git identity does not connect its
observed repositories into one linked group. `ProjectTaskRepositoryGroups`
recomputes repository sections for every Mesh on each snapshot: a confirmed owner repository
wins, otherwise a single observed repository is used. Conflicting or multiple
repositories remain in a distinct section, and Tasks without Git evidence stay
under workspace Tasks. Git bindings and native worktree observations also
recognize repositories without a remote or first commit. Names, prompt text,
and parent-directory matches never assign a repository. These sections change
presentation, not persisted Project membership or permissions.

Project management remains under the existing Project view. Governance,
Members / Computers, Graph, and Health are Project destinations. Graph is a
full-screen SceneKit view: repository towers are connected only by the bounded
WEAVATRIX edges reported in the Project snapshot. Health lists load and
repository bindings, and opens its observed code map as full-screen code
towers. A missing Engine report is shown as unavailable. Governance supports
authoring the first policy at revision zero. Auto-accept opens a separate Action
rules editor that preserves the Mesh's confirmed enforcement mode. The client preserves custom
rules, sends one next-revision policy under each computer's Project key, and
keeps showing the last confirmed state until the engine publishes its status.
Coverage uses the exact states enforced, observed, unsupported, and unknown, so
a provider without a deterministic hook is never presented as protected.
The Mac applies policy and auto-accept through the installed local MCP runtime;
known remote computers still receive the scoped policy through their relay rooms.
Skill and MCP detail views match observed calls to the exact Mesh executions and
computers. Installation and missing resource reports do not count as usage.

Only bounded policy, member, binding, and status projections belong on iPhone.
The protected Project Governance cache is separate from the hot Mesh snapshot,
keeps at most 64 Projects, and never becomes the Project database.
Binding rows deliberately omit `localPathHint`; absolute paths and the full
endpoint graph or memory remain on their endpoint computers. The phone renders
only the repository-level edges already present in its encrypted snapshot.

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
The handoff sheet selects a computer, enabled agent, and advertised model,
and accepts a bounded user comment. The comment and model choice travel in the
encrypted Task Capsule. The destination opens a new native execution in a
separate worktree under the same Task; its receipt changes the owner. The same
agent on the same computer is allowed only with a different model.

Tests live in `GrantTapTests/Features/ProjectMesh`. See the repository
[`AGENTS.md`](../../../../../AGENTS.md) for the product and quality contract.
