# Mesh Task creation

`ProjectNewTaskView` is the shared iPhone and Mac entry point inside a selected
Mesh. The Mac uses a bounded sheet, a side-by-side editor and route card, the
shared model picker and animated effort control, and a persistent Create footer.
iPhone stacks the same fields in a scrolling sheet above the footer and keyboard.
Cancel and interactive dismissal protect a nonempty draft.
Both platforms use the shared SwiftUI text editor.
On Catalyst, `ProjectTaskMacDismissal` dismisses the sheet's own native presenter
before clearing its owner binding, including after discard confirmation.

`ProjectTaskCreationContext` restricts computers and workspaces to this Mesh's
available bindings and pinned-host policy. Computer names and workspace names
are separate. `ProjectTaskDraft` preserves text and attachments across provider
and computer changes, clearing only incompatible model, effort or binding choices.
It validates the native 8,000-character prompt limit and attachment limits.

`ProjectTaskSubmission` uses the existing authenticated local MCP or the exact
computer relay route. It carries Project, repository binding, model and effort.
An uncertain local response retains the operation ID for a safe retry; a confirmed
refusal permits a new attempt. A successful native creation opens only its returned
session after refreshing the catalog. Demo mode cannot submit real work.

New Mesh belongs to `ProjectsTabView`, the Mesh selection level. New Task belongs
to `ProjectMeshView`. Neither action remains in the Mac's global sidebar.

Tests in `tests/` cover route scope, pinned refusal, option changes, retry identity
and the bounded Mac form. `ProjectTaskCreationUITests` exercises the real sheet,
provider/model/effort controls and discard confirmation on both Apple clients.
The Mac regression also closes an empty form and checks the model picker's Done.
`GRANTTAP_UI_TARGET_BUNDLE_ID` optionally points the UI runner at an isolated QA
copy; ordinary runs use the app under test. Numeric draft input avoids dependence
on the Mac's active keyboard layout.

See the [engineering contract](../../../../../../AGENTS.md).
