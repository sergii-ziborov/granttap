import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct WorkspaceSelectionMenu: View {
    let agent: String
    @Binding var selection: String
    let folders: [String]

    var body: some View {
        Menu {
            Button {
                selection = "granttap:general"
            } label: {
                Label(L("No project"), systemImage: selection == "granttap:general" ? "checkmark" : "square.dashed")
            }
            if !folders.isEmpty {
                Section("Open \(AgentIdentity.shortName(agent)) folders") {
                    ForEach(folders, id: \.self) { path in
                        Button {
                            selection = path
                        } label: {
                            Label(path, systemImage: selection == path ? "checkmark" : "folder")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selection == "granttap:general" ? "square.dashed" : "folder.fill")
                    .foregroundStyle(Theme.accent(for: agent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(selection == "granttap:general" ? L("No project") : workspaceName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(selection == "granttap:general" ? L("Isolated GrantTap workspace") : selection)
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(10)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.line))
        }
    }

    private var workspaceName: String {
        selection.split(separator: "/").last.map(String.init) ?? selection
    }
}
