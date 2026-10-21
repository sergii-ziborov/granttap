import SwiftUI

enum ProjectHealthOptions {
    struct Selection: Equatable {
        let filter: String
        let sort: String
        let diagnostics: Bool
    }
    static func repositories(_ values: [ProjectHealthPresentation.Repository], filter: String,
                             sort: String) -> [ProjectHealthPresentation.Repository] {
        values.filter { repository in
            switch filter {
            case "refresh": return repository.stale || !repository.usable
            case "errors": return repository.failed
            default: return true
            }
        }.sorted { left, right in
            if sort == "problems", priority(left) != priority(right) { return priority(left) < priority(right) }
            return left.name == right.name ? left.id < right.id : left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private static func priority(_ repository: ProjectHealthPresentation.Repository) -> Int {
        if repository.failed { return 0 }
        if !repository.usable { return 1 }
        if repository.stale { return 2 }
        return repository.ready ? 4 : 3
    }
}

struct ProjectHealthOptionsSheet: View {
    @Binding var filter: String
    @Binding var sort: String
    @Binding var diagnostics: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(L("Repositories")) {
                    Picker(L("Show reports"), selection: $filter) {
                        Text(L("All repositories")).tag("all")
                        Text(L("Needs refresh")).tag("refresh")
                        Text(L("Errors only")).tag("errors")
                    }
                    .accessibilityIdentifier("health.options.filter")
                    Picker(L("Sort reports"), selection: $sort) {
                        Text(L("Problems first")).tag("problems")
                        Text(L("Name")).tag("name")
                    }
                    .accessibilityIdentifier("health.options.sort")
                }
                Section(L("Diagnostics")) {
                    Toggle(L("Show technical diagnostics"), isOn: $diagnostics)
                        .accessibilityIdentifier("health.options.diagnostics")
                    Text(L("A partial report can be current. It describes a bounded part of the repository, not a failed analysis."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Section {
                    Button(L("Reset Health options")) { filter = "all"; sort = "problems"; diagnostics = false }
                }
            }
            .pageNavigationTitle(L("Health options"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }
}
