import SwiftUI

/// Choosing a project among many.
///
/// A dropdown listing every folder an agent has opened is unusable once that
/// list is long: the names repeat, the useful part of a path is in the middle,
/// and there is nothing to type into. This is a searchable list that matches on
/// the folder name and on the path, and shows where each folder actually lives
/// so two projects called `web` stay distinguishable.
struct WorkspacePickerSheet: View {
    let workspaces: [String]
    @Binding var workspace: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var matches: [String] { Self.matches(workspaces, query: query) }

    /// Matching is a plain function so the rule can be asserted without a view.
    static func matches(_ workspaces: [String], query: String) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return workspaces }
        return workspaces.filter { $0.lowercased().contains(needle) }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    row(path: nil)
                }
                Section {
                    if matches.isEmpty {
                        Text(L("No project matches this search."))
                            .foregroundStyle(Theme.muted)
                    } else {
                        ForEach(matches, id: \.self) { path in
                            row(path: path)
                        }
                    }
                } header: {
                    Text(L("Open agent folders"))
                } footer: {
                    Text(String(format: L("%d of %d folders"), matches.count, workspaces.count))
                }
            }
            .searchable(text: $query, prompt: Text(L("Search projects")))
            .navigationTitle(L("Project"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    private func row(path: String?) -> some View {
        Button {
            workspace = path ?? ""
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: path == nil ? "square.dashed" : "folder.fill")
                    .foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(path.map(Self.name) ?? L("No project"))
                        .foregroundStyle(Theme.ink)
                    if let parent = path.flatMap(Self.parent) {
                        Text(parent).font(.caption).foregroundStyle(Theme.muted)
                            .lineLimit(1).truncationMode(.head)
                    }
                }
                Spacer(minLength: 6)
                if (path ?? "") == workspace {
                    Image(systemName: "checkmark").foregroundStyle(Theme.claude)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workspace.\(path ?? "none")")
    }

    static func name(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    static func parent(_ path: String) -> String? {
        let parts = path.split(separator: "/").dropLast()
        return parts.isEmpty ? nil : "/" + parts.joined(separator: "/")
    }
}
