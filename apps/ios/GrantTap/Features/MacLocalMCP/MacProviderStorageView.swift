#if targetEnvironment(macCatalyst)
import SwiftUI

private struct MacStorageReport: Decodable {
    struct Store: Decodable, Identifiable {
        struct Entry: Decodable, Identifiable {
            let id: String
            let name: String
            let category: String
            let bytes: Int64
            let cleanable: Bool
            let reason: String?
        }
        let name: String
        let bytes: Int64
        let capped: Bool
        let entries: [Entry]
        var id: String { name }
    }
    let operation: String
    let available: Bool
    let planId: String?
    let stores: [Store]?
    let moved: Int?
}

/// Metadata comes from SweepLoom through the external runtime, outside App Sandbox.
struct MacProviderStorageView: View {
    @ObservedObject var reader: MacLocalMCPModel
    @State private var report: MacStorageReport?
    @State private var selected = Set<String>()
    @State private var loading = false
    @State private var confirmTrash = false
    @State private var error: String?
    @State private var result: String?

    var body: some View {
        List {
            Section {
                Text(L("SweepLoom inspects storage without reading chat contents. Select temporary caches or logs to move to the Mac Trash. Conversations, credentials and databases stay in place."))
                    .foregroundStyle(Theme.muted)
                Button(L("Refresh")) { Task { await inspect() } }.disabled(loading)
                if loading { ProgressView() }
                if let error { Text(error).foregroundStyle(Theme.riskHigh) }
                if let result { Text(result).foregroundStyle(Theme.ok) }
                if report?.available == false {
                    Link(L("Install SweepLoom"), destination: URL(string: "https://github.com/Weavatrix/sweeploom#install")!)
                    Text(L("Install the SweepLoom CLI on this Mac, then refresh."))
                }
            }
            ForEach(report?.stores ?? []) { store in
                Section {
                    ForEach(store.entries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).lineLimit(2)
                                Text(L(entry.category) + " · " + size(entry.bytes))
                                    .font(.caption).foregroundStyle(Theme.muted)
                                if entry.reason == "provider-running" {
                                    Text(L("Close this provider before clearing its cache."))
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                            Spacer()
                            if entry.cleanable {
                                Button {
                                    if selected.contains(entry.id) { selected.remove(entry.id) }
                                    else if selected.count < 16 { selected.insert(entry.id) }
                                } label: {
                                    Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                }
                                .accessibilityLabel(L("Select cache") + ": " + entry.name)
                            } else { Text(L("Inspect only")).font(.caption).foregroundStyle(Theme.muted) }
                        }
                    }
                } header: {
                    Text(store.name.capitalized + " · " + size(store.bytes))
                } footer: {
                    if store.capped { Text(L("Storage scan is incomplete. Cleanup is unavailable.")) }
                }
            }
            if !(report?.stores ?? []).isEmpty {
                Button(L("Move selected caches to Trash"), role: .destructive) { confirmTrash = true }
                    .disabled(selected.isEmpty || loading)
            }
        }
        .pageNavigationTitle(L("Provider storage"))
        .task { await inspect() }
        .confirmationDialog(L("Move selected caches to Trash?"), isPresented: $confirmTrash,
                            titleVisibility: .visible) {
            Button(L("Move to Trash"), role: .destructive) { Task { await trash() } }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The runtime checks that these caches are unchanged and the provider is closed. They remain recoverable in the Mac Trash."))
        }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func read(_ input: [String: String]) async throws -> MacStorageReport {
        guard let socket = reader.status?.desktopEngineSocket else { throw MacLocalMCPError.unavailable }
        let data = try await MacLocalMCPClient.read(socketPath: socket,
            operation: "desktop.provider_storage", input: input)
        let value = try JSONDecoder().decode(MacStorageReport.self, from: data)
        guard value.operation == "desktop.provider_storage", (value.stores?.count ?? 0) <= 3,
              value.stores?.allSatisfy({ $0.bytes >= 0 && $0.entries.count <= 128
                && $0.entries.allSatisfy { $0.bytes >= 0 && $0.name.count <= 1024 } }) ?? true else {
            throw MacLocalMCPError.incompatible
        }
        return value
    }

    private func inspect() async {
        guard !loading else { return }
        loading = true
        error = nil
        selected = []
        defer { loading = false }
        do { report = try await read(["action": "inspect"]) }
        catch { self.error = L("Storage inspection failed. Refresh to try again.") }
    }

    private func trash() async {
        guard let planId = report?.planId, !selected.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let ids = String(decoding: try JSONEncoder().encode(selected.sorted()), as: UTF8.self)
            let applied = try await read(["action": "trash", "planId": planId, "ids": ids, "confirm": "true"])
            result = String(format: L("Moved %d caches to Trash."), applied.moved ?? 0)
            report = try await read(["action": "inspect"])
            selected = []
        } catch {
            selected = []
            self.error = L("Cache changed or the provider is running. Refresh and review the selection again.")
        }
    }
}
#endif
