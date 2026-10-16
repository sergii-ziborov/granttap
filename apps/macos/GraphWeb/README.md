# Mac code city

[Engineering index](../../../AGENTS.md) · [Public entry point](mesh-graph.js)

The Apple client embeds the Repo Lens Cyberboard in a local WKWebView. Reports
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
`update-vendor.sh` reproduces the generated Repo Lens bundle and the explicit
host callback bridge. Its source revision is recorded in `REPO_LENS_COMMIT`;
`build/` is generated third-party code, not a second machine runtime.

Tests live in `tests/` and exercise the received map, actual Three.js camera and
materials, DOM controls, section selection, corrupted view preferences and
repository isolation. `MacGraphControlsUITests` covers the embedded renderer and
full-screen transition on the Mac. The canonical release gate is described in
the engineering index.
