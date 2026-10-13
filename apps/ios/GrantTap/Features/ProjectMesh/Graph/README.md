# Repository graph and code towers

[public source](https://github.com/sergii-ziborov/granttap) · [Public entry point](ProjectGraphView.swift)

Graph consumes the current received Weavatrix report from Project Mesh. The
shared build card owns waiting, receipt confirmation and retry presentation;
the machine runtime owns automatic repository analysis and revision changes.
An existing graph stays available while a new report is being built.

The iPhone and iPad code city uses SceneKit with measured source geometry.
The visible dock supports zoom, Fit, Focus and Orbit / Pan. The view menu adds
top/isometric views, rotation, help, color and highlight settings, and an
immersive view. Camera target and position survive color and view settings;
idle rendering pauses after camera interaction ends. Reduce Motion removes
camera-flight animation.

An already open scene consumes new received maps. File additions and removals
update the geometry while retaining the camera, colour mode and valid selection.
Inline search keeps file actions separate from symbol actions, so selecting a
file opens its inventory and selecting a symbol opens its source details.

Select a tower or a measured section to open its source information. Sections
scroll through every received symbol. Files groups all received paths and
searches symbol names without a short result cap. Links retain their actual
direction and endpoint. Health shows measured lines, language, observed links
and report provenance. A missing structural health score is shown as unknown.
Git revision and the analysis content fingerprint remain distinct.

The Mac consumes the same wire reports through the local
[Repo Lens viewer](../../../../../macos/GraphWeb/README.md). Apple clients do not
import machine-runtime internals. Reports remain part of the protected offline
Mesh replica and inspection needs no network after receipt.

Unit tests live in `GrantTapTests/Features/ProjectMesh/Graph`; interaction tests
cover camera movement, selecting the last of 36 sections, searching, navigating
links and the embedded Mac full-screen viewer. The canonical release gate is
described in the engineering index.
