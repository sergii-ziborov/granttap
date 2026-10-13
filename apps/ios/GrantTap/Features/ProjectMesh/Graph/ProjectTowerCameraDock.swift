import SwiftUI

struct ProjectTowerCameraDock: View {
    @Binding var settings: ProjectTowerViewSettings
    let selected: Bool
    let perform: (ProjectTowerCameraAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            control(.zoomOut, icon: "minus.magnifyingglass", title: "Zoom out", id: "zoom-out")
            control(.zoomIn, icon: "plus.magnifyingglass", title: "Zoom in", id: "zoom-in")
            control(.fit, icon: "viewfinder", title: "Fit all towers", id: "fit")
            control(.focus, icon: "scope", title: "Focus selected tower", id: "focus").disabled(!selected)
            Picker(L("Camera movement"), selection: $settings.navigation) {
                ForEach(ProjectTowerNavigationMode.allCases, id: \.self) { mode in Text(L(mode.rawValue)).tag(mode) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 150)
            .accessibilityIdentifier("code-towers.navigation-mode")
        }
        .padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .pointerButtonStyle()
    }

    private func control(_ action: ProjectTowerCameraAction, icon: String, title: String, id: String) -> some View {
        Button { perform(action) } label: { Image(systemName: icon).frame(width: 44, height: 44) }
            .accessibilityLabel(L(title)).accessibilityIdentifier("code-towers.\(id)").help(L(title))
    }
}

struct ProjectTowerSettingsSheet: View {
    @Binding var settings: ProjectTowerViewSettings
    @Binding var colorMode: ProjectTowerColorMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Picker(L("Color"), selection: $colorMode) {
                    ForEach(ProjectTowerColorMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .accessibilityIdentifier("code-towers.color-mode")
                Picker(L("Highlight"), selection: $settings.highlight) {
                    ForEach(ProjectTowerViewSettings.Highlight.allCases, id: \.self) { mode in
                        Text(L(mode.rawValue)).tag(mode)
                    }
                }
                VStack(alignment: .leading) {
                    Text(L("Visibility of unrelated towers"))
                    Slider(value: $settings.dimOpacity, in: 0.04...1)
                }
                Toggle(L("Show labels"), isOn: $settings.labels)
                    .accessibilityIdentifier("code-towers.labels")
                Toggle(L("Show evidenced links"), isOn: $settings.roads)
                Toggle(L("Move camera on selection"), isOn: $settings.autoFocus)
                    .accessibilityIdentifier("code-towers.auto-focus")
            }
            .navigationTitle(L("View settings"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
        }
    }
}

struct ProjectTowerControlsHelp: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            List {
                Label(L("Drag to orbit; choose Pan to move the scene."), systemImage: "hand.draw")
                Label(L("Pinch or use the zoom buttons to change scale."), systemImage: "plus.magnifyingglass")
                Label(L("Tap a tower section to inspect its source facts."), systemImage: "rectangle.stack")
                Label(L("Scroll Sections to reach every reported symbol."), systemImage: "list.bullet")
                Label(L("Fit restores the whole map. Focus returns to the selected section."), systemImage: "viewfinder")
            }
            .navigationTitle(L("Graph controls"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
        }
    }
}
