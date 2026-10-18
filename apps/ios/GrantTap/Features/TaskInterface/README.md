# Task interface

This feature folder owns the iPhone Now, Tasks, Usage, chat-first Task, composer,
attachment, approval, pairing, settings, and troubleshooting surfaces.
`ContentView.swift` remains the root coordinator; each component here owns one
visible Personal responsibility.

Now and Tasks use the same `TaskSwipeCard`: swipe left on a Task to reveal
**Send** and **Archive**. Archive hides its native sessions from the active
list and the existing Hidden tasks view restores them. Send opens the Project
Mesh handoff sheet for the current owner. A context menu exposes the same
actions for pointer and keyboard users.
Revealed actions use semantic action/surface colours with contrasting labels in
both appearances; provider glyph colours never supply the Send background.

On Mac, Settings is selected in the sidebar and uses the main navigation
stack, including its child pages. `SettingsView` owns the shared content;
`SettingsSheet` wraps it for phone and tablet presentation.

Behavioral tests live in `GrantTapTests/AppRuntimeTests.swift`, provider/catalog
tests in `SessionCatalogTests.swift`, and end-to-end rendering/delivery is
validated by the Simulator suite. Production files in this folder stay below
300 lines; composed surfaces are split by responsibility.

Local Mac generated image links use the shared `MessageImageContentView` and
`MessageImageGallery`. Runtime-advertised PNG/JPEG/WebP references become inline
previews with filenames and a full-screen viewer. `MessageImageLoader` bounds
decoding and serialises reads; failed files remain retryable. Compact task
previews retain text. Tests live in `GrantTapTests/Features/TaskInterface/Chat`
and `GrantTapUITests/MessageImageUITests.swift`.

The existing chat status strip names its Project/Mesh and opens that Project.
Messages and grouped runs show the provider’s date and local time.
Codex and Claude chat history use native backward pages through `ChatHistoryPaging`.
The persistent previous-request control preloads at least two root user requests,
including attachment-only requests. Each jump prepares the next older request;
while reading earlier turns, the pinned text follows the viewport and the next
jump goes upward from that turn. Native attachment fragments at one timestamp
share their request's text and navigation boundary. A standalone file or image
request still has a boundary of its own. Short transcripts retain sequential
request navigation even when all rows fit in the viewport.
long tool runs cannot hide the question above them. Top-edge paging also works,
and the explicit history button recovers failed or stalled loads without a retry loop.
The latest-message action shares the pinned request strip, outside the scrolling
surface, so it cannot intercept transcript pans. Its space stays reserved while
hidden so the first jump to the newest message survives layout. The phone uses
native recycled list rows through [TranscriptViewport](Chat/TranscriptViewport/README.md),
so old messages stay in the device archive without every row being laid out.
Top-edge paging follows actual visible row positions, and stable entry ids and
native cursors preserve navigation through older pages. Timeline grouping and
recorded reply changes are prepared once when the relevant transcript or Mesh
changes, rather than for each scroll or composer edit.
Every fetched page remains in a protected per-chat archive on iPhone and Mac
until the user clears Chat history & cache in Settings. Clearing that cache
preserves provider history, account credentials and device connections. `ChatFileChanges` renders the computer's completed-reply file
summary, added/removed counts, expandable file list and redacted diff previews.
The summary includes edits outside the visible page; it describes recorded
successful edits rather than the final Git tree. Full bounded tool call/result
previews use separate fields from the compact timeline labels. Tests live in
`GrantTapTests/Features/TaskInterface/Chat/TranscriptHistoryTests.swift` and
`GrantTapUITests/TranscriptHistoryUITests.swift`.

The [FileReview](Chat/FileReview/README.md) module owns the diff inspector,
with separate vertical and horizontal scrolling, a compact Mac header and
preserved incomplete-preview evidence when combining a reply's edits.

[AttachmentPreview](Chat/AttachmentPreview/README.md) opens selected or retained
sent files on Mac, iPhone and iPad. The shared Files picker accepts every file
type. Source/text previews are selectable; supported documents and media use
Quick Look. The composer fills its existing footer with a flat background and
one top divider, without an inset rounded container or an extra Mac bottom band.

`ActivityCommandMetrics` renders call duration, average CPU relative to one
core, CPU time, peak RSS and the reported resource source in command details.
An average requires the resource's own sampling window and can exceed 100%.
Agent resource attribution is an approximate share of the sampled provider
process family; MCP memory describes nearby server processes. Neither is
presented as an isolated command measurement. Estimated argument/result
context size is separate from model token billing, which the providers do not
report per command. Unknown values stay unknown. The local Mac projection keeps
the same capability evidence as the encrypted Apple wire contract.
Sparse refreshes preserve previously received telemetry for the same call and
capability; explicit new resource evidence replaces the old sampling window.
Tests: `ActivityCommandMetricsTests`, `MacCommandMetricsTests`, and the command
detail scenario in `TranscriptHistoryUITests`.

Running chats expose the existing computer-confirmed Stop/pause action beside
the composer. A pending control remains disabled until the computer replies;
its refusal or timeout restores the previous state. Resume remains in Task
controls. Neutral filled Retry and Mesh actions use the inverse neutral ink in
both appearances. Rendering tests verify the real Now Retry contrast.

`Session/Views/TaskCardSwipeGesture.swift` rejects vertical intent before pan
recognition, preserving the parent scroll gesture during live Task updates.
Horizontal swipes retain Send and Archive. Direction tests live in
`GrantTapTests/Features/TaskInterface/Session`; scrolling is exercised with a
streaming 240-Task fixture in `GrantTapUITests/TaskScrollUITests.swift`.
