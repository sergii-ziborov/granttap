# Transcript viewport

Public entry: `ChatTranscriptViewport`. `TaskChatView` supplies stable grouped
rows and uses the existing scroll reader for request jumps, focused calls and
latest-message navigation. iPhone, iPad and Mac use native `List` recycling; only
visible rows and the system's nearby prefetch rows render rich text and images.
Storage has no viewport row limit.

`ChatTranscriptCache` prepares the full `ChatTranscriptPresentation` once per
conversation revision, starting with the first layout. The opening screen does
not repeatedly sort fallback timelines before `onAppear`. Cached rows, completed
reply changes and child conversations are shared by every chat subview. Updating a different chat, scrolling,
and typing in the composer do not sort the opened transcript again. A change
in the same chat is observed even if its ids and provider timestamp remain
unchanged. Only Mesh events belonging to this Task refresh its combined timeline.

`ChatRequestNavigation` and `TranscriptRequestIndex` prepare request boundaries
and row positions with that projection. Pinned-request updates and scroll
callbacks reuse those lookups, including requests split into text and image
fragments. The pinned label is bounded to 240 characters. `TaskMeshEventIndex`
groups events once per Mesh revision instead of scanning every Project for each
row read. Mac chat opening owns its local history request; the sidebar only
navigates. Unsupported Watch transports skip snapshot preparation entirely.

Top-edge paging reads actual visible rows and native scroll gestures. Native cursors and stable
ids support jumps into any locally retained part of the history. The activity
archive and image store remain owned by `DeliveryPersistence` and `OfflineReplica`.

Local tests in `tests/TranscriptViewportTests.swift` exercise a 5,000-row viewport.
`GrantTapUITests/LongTranscriptUITests.swift` and `MacTranscriptUITests` check the
actual chat's old/new message navigation and composer. `TranscriptHistoryUITests` covers older-page
loading and pinned-request scroll position. Durable storage and slow-write tests
live in `GrantTapTests/Features/DeliveryPersistence`.

`TranscriptScrollPerformanceTests` exercises repeated production chat reads with
5,000 messages and 2,000 Mesh events. `TranscriptRequestNavigationTests` compares
the prepared index with existing paging and request-navigation semantics.

See the [engineering contract](../../../../../../../AGENTS.md).

`TranscriptScrollPosition` observes the native List's content offset, size and
viewport to report its bottom edge. It does not depend on a recycled SwiftUI
footer remaining mounted. Request navigation still uses the existing reader.
