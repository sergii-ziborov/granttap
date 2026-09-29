# Mesh and repository catalog

`RepositoryCatalog.swift` indexes repository identities across visible Mesh
scopes. `ProjectsTabView` keeps a pinned Mesh / Repositories switch on Mac,
iPad and iPhone. A repository opens `RepositoryCatalogDetailView`, which lists
each original Mesh scope and routes its chats through their stable Task IDs.
Pushed Task pages open chats without dismissing their navigation frame, so Back
returns to the original Task and repository instead of an empty destination.

`ProjectTaskRepositoryGroups` supplies the shared assignment algorithm. A
confirmed current owner wins over historical executions. Conflicting reports,
earlier execution repositories and missing Git evidence are shown explicitly.
Names, chat titles and parent paths never assign a chat to a repository.
Bindings from offline computers remain visible. Foreign and hidden Mesh records
are excluded. Workspace roots without confirmed Git identity remain distinct
from Git repositories; local paths are not displayed as remote identities.

`MeshTaskPlacement` presents a Task under the unique visible Mesh whose primary
repository matches its confirmed current execution. This also detects a chat
started in another repository's Mesh. The original Task ID, history, route and
access scope stay intact. The target shows where it started; the source links to
its current presentation. Missing or ambiguous evidence keeps it in the source.
Placement recalculates when snapshots, executions or visible scopes change.

`RepositoryActivity` places working repositories first and shows active work,
attention, task counts and observed branches. Previous executions do not count
as active work. Repository details show current and previous tasks, Mesh scopes,
computers, Git branch/HEAD, working tree state, up to eight recent commits and
up to twelve contributors, with branch totals and observation time. Missing
telemetry stays unknown. There is no inferred code dependency.

`ProjectRepositoryDetails` consumes optional encrypted Git observations from MCP
0.8.29 source or later. `RepositoryIdentityIndex` combines local and remote IDs
only when the latest computer reports agree about the real checkout. A changed,
missing or conflicting checkout cannot reuse an older identity claim. The Mac
requests enrichment while the catalog is visible; phone clients consume the
same computer-published data. Opening or refreshing a repository requests fresh
details. Read-only Git commands run in the standalone MCP, never in Swift.

Behavior tests: `GrantTapTests/Features/ProjectMesh/RepositoryCatalog`.
UI navigation and Git/activity tests: `GrantTapUITests/RepositoryCatalogUITests.swift`, run on both
iPhone and iPad. The normal Mac client uses the same views; demo fixtures are
used only in simulator test launches.

See the [Project Mesh module](../README.md) and repository
[engineering contract](../../../../../../AGENTS.md).
