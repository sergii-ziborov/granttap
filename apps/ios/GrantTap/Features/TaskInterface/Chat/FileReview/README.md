# File review

[public source](https://github.com/sergii-ziborov/granttap) · [Recorded diff interface](ChatFileReviewSheet.swift) · [Workspace contract](TaskWorkspaceModels.swift)

`ChatFileReviewSheet` opens a recorded edit from the completed-reply file list.
The full path and recorded added/removed counts stay above the diff. Mac uses
the shared compact page header; phone and tablet retain native sheet navigation.

`ChatFileDiffViewport` separates vertical history movement from horizontal code
scrolling. Short diffs start at the top left; long lines retain their complete
unwrapped width. A fresh file starts at the leading edge. The existing bounded
preview warning remains visible when the runtime truncated the diff.

The review displays recorded successful edits, not a fabricated final Git diff.
Tests live in `GrantTapTests/Features/TaskInterface/Chat/FileReview` and the
changed-file scenario in `GrantTapUITests/TranscriptHistoryUITests.swift`.

`ChatActivityRail` keeps the latest reply's file count and recorded added/removed
lines above the composer. A completed summary supersedes that reply's tool
records; previous replies keep their own recorded changes. Its Files sheet
opens Modified diffs and the scoped All files tree. Nested execution
conversations open from the adjacent Agents pill.

`ChatWorkspaceDirectoryView` shows the saved root immediately, loads a directory
when expanded and exposes partial-list pagination. `ChatWorkspaceFileSheet`
shows saved text first, preserves it through a failed refresh and exposes
bounded preview pagination. Missing uncached content has an unavailable state
and retry. Both consume the public `AppModel.readTaskWorkspace(for:mode:path:offset:)`
and `cachedTaskWorkspace(for:mode:path:offset:)` entry points. Reads stay within
the native execution's workspace on its computer; protected paths are enforced
by the MCP reader. Device-protected previews persist until cache clearing, which
also cancels pending reads and preserves account identity.

`ChatActivityRailUITests` use only synthetic recorded edits, nested conversations
and persisted workspace pages. They exercise current-reply counters, diff
opening, offline folder expansion, paged text and unavailable uncached folders.
`ChatReplyChangesTests` cover edit coalescing and completed summary precedence.
