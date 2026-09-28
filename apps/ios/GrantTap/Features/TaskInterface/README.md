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

Codex chat history uses native backward pages through `ChatHistoryPaging`.
The top of the transcript loads older messages and keeps a retryable explicit
button. Stable entry ids and the older cursor survive live snapshots; loaded
pages are held while reading and released on leaving the chat. Disk caches
remain bounded. `ChatFileChanges` renders the computer's completed-reply file
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
