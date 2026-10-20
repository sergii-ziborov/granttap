# Shared Apple code city

[Engineering index](../../../AGENTS.md) · [Public entry point](mesh-graph.js)

Each Apple client embeds the Repo Lens Cyberboard in a local WKWebView. Reports
come from the encrypted Project Mesh snapshot; this viewer does not run a
repository scan or send another model request. `board-data.js` retains repository,
file and symbol identities, Git revision, analysis fingerprint, measured lines
and directed relations. Equal paths in different repositories remain separate.

Select a tower, its file badge or one of its labelled sections to open the
scrollable Sections / Links / Health inspector. The section rail beside a tower
supports wheel and touch scrolling; the inspector lists every received symbol.
Files opens a folder list with file and symbol search. Links navigate to their
actual endpoint, including reported external services and architecture nodes.

The camera dock provides zoom, Fit, top and isometric views, Orbit / Pan, help
and full screen. Camera position, target, selected source section and highlight
preferences are retained when opening the full-screen viewer. Camera position
and selected symbol identity also survive report updates; inserted source sections
do not reassign a selection by its old row number. The Health tab and scroll
position remain part of the saved view. A removed symbol returns to its file.
Camera flights
stop when the user chooses manual movement. View settings change the measured
LOC warning threshold and expose the original edge and marker filters. Missing
coverage, complexity and structural health remain unknown; LOC warnings describe
size. Repository and source text is assigned through safe text nodes.

English and Russian controls follow the application language. `graph-ui.css`
owns the host panels and their pointer, focus and narrow viewport states.
`bundle-viewer.sh` produces a single classic script so file-backed WebKit does
not depend on cross-file ES-module loading. Scripts and styles stay inside
the read-only application resource directory; the viewer CSP blocks network
connections. `update-vendor.sh` reproduces the generated Repo Lens bundle and the explicit
host callback bridge. Its source revision is recorded in `REPO_LENS_COMMIT`;
`build/` is generated third-party code, not a second machine runtime.

Tests live in `tests/` and exercise the received map, actual Three.js camera and
materials, DOM controls, section selection, corrupted view preferences and
repository isolation. `MacGraphControlsUITests` covers the embedded renderer and
full-screen transition on the Mac. The canonical release gate is described in
the engineering index.

Camera framing tests project all received bounds through real Three.js cameras
in portrait and landscape. Phone UI tests exercise the bundled viewer, all
reported source sections, external-service search and camera controls offline.

The mobile HUD uses the same cyan grid, measured source towers and directed
traces as Repo Lens. Compact icon controls leave the scene visible. Overlapping
module, section and focused-tower labels are hidden until the camera separates them;
the selected section and tower paging take priority and clear the detail panel.
Rebuilding a section rail schedules a collision pass without a continuous layout timer.
All received sections, facts and full paths remain
in Files and the source inspector. Neutral blue towers mean that health was not
reported, while amber section highlights indicate measured size only.
On a narrow phone, the open inspector replaces duplicate world-space section
callouts and their scroll rail with the complete scrollable Sections list.
The selected tower, section highlight and 3D leaders remain in the scene.
Closing details removes that responsive state; Fit returns to the whole city.

Source framing uses the visible area above the phone inspector or beside the
landscape inspector. Saved camera offsets are relative to the viewport, so a
desktop or landscape offset cannot replace a phone's aspect ratio. Fit closes
the inspector and returns to the whole map. The search layout keeps file results
accessible while the landscape keyboard is open.

External services sit beside the measured module bounds, rather than at a fixed
world coordinate. Reopening in a different viewport refits the map or selected
source; a saved overview must show a readable share of the received map. A valid
camera, selected symbol, inspector tab and scroll position survive a same-size
report refresh. Top and ISO remain directly available as named icon buttons.
The phone inspector uses a compact bottom panel; landscape uses a side panel.
Legend filters open from Highlights and help replaces that popover without
discarding the selected source.

A neutral source body represents measured file lines outside the union of known
section ranges. It keeps a 253-line file visible when only three one-line
constants were reported. This body is never counted, searched, highlighted or
listed as an additional function or symbol. Missing file size or section
locations do not generate an additional measured source body. Overlapping ranges are counted once.
