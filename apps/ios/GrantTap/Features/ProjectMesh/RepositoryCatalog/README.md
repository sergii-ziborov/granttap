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

The catalog and grouped chat rows recalculate when Mesh snapshots or executions
change. They do not move Tasks, merge Projects, grant access, or claim a code
dependency. Binding and code-map membership are presented with their source.

Behavior tests: `GrantTapTests/Features/ProjectMesh/RepositoryCatalog`.
UI navigation tests: `GrantTapUITests/RepositoryCatalogUITests.swift`, run on both
iPhone and iPad. The normal Mac client uses the same views; demo fixtures are
used only in simulator test launches.

See the [Project Mesh module](../README.md) and repository
[engineering contract](../../../../../../AGENTS.md).
