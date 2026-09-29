# Task interface

This feature folder owns the iPhone Now, Tasks, Usage, chat-first Task, composer,
attachment, approval, pairing, settings, and troubleshooting surfaces.
`ContentView.swift` remains the root coordinator; each component here owns one
visible Personal responsibility.

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
long tool runs cannot hide the question above them. Top-edge paging also works,
and the explicit history button recovers failed or stalled loads without a retry loop.
The latest-message action shares the pinned request strip, outside the scrolling
surface, so it cannot intercept transcript pans. Its space stays reserved while
hidden so the first jump to the newest message survives layout. Paging measures the content
container rather than a lazy header that may disappear from the view hierarchy.
Stable entry ids and older cursors survive live snapshots. iPhone keeps a bounded
recent window extended through two complete request boundaries. Mac retains every
fetched page in a per-chat protected archive across launches until the user clears
it in Settings → This Mac → Chat history & cache. Clearing the cache also clears
its durable files, while preserving provider history and device connections. `ChatFileChanges` renders the computer's completed-reply file
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
