import SwiftUI

struct ChatCacheView: View {
    @EnvironmentObject private var model: AppModel
    @State private var bytes = LocalReplicaCache.bytes
    @State private var confirmClear = false
    @AppStorage(ReplicaImageRetention.settingsKey) private var imageRetention = ReplicaImageRetention.month.rawValue

    var body: some View {
        List {
            Section {
                CompatLabeledContent(L("Saved on this device"), value:
                    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                Button(L("Clear local chat cache"), role: .destructive) { confirmClear = true }
                    .accessibilityIdentifier("settings.cache.clear")
            } header: {
                Text(L("GrantTap chat history"))
            } footer: {
                Text(L("Messages and Mesh are saved on this device for offline reading. Earlier messages download automatically while connected. Attachment cleanup is configured below."))
            }
            Section {
                Picker(L("Remove unused attachments after"), selection: $imageRetention) {
                    ForEach(ReplicaImageRetention.allCases, id: \.rawValue) { policy in
                        Text(policy.title).tag(policy.rawValue)
                    }
                }
                .accessibilityIdentifier("settings.cache.retention")
                .onChange(of: imageRetention) { _ in refreshCache() }
            } header: {
                Text(L("Attachment cache"))
            } footer: {
                Text(L("Downloaded pictures and submitted documents use up to 256 MB. Cleanup runs when the app opens and saves attachments. Pictures can download again when their computer is available. Pending messages and their original attachments are kept."))
            }
            #if targetEnvironment(macCatalyst)
            if let reader = model.localMCPReader {
                NavigationLink {
                    MacProviderStorageView(reader: reader)
                } label: {
                    Label(L("Codex, Claude & Cursor storage"), systemImage: "externaldrive")
                }
                .accessibilityIdentifier("settings.cache.providers")
            }
            #endif
        }
        .pageNavigationTitle(L("Chat history & cache"))
        .onAppear { refreshCache() }
        .confirmationDialog(L("Clear local chat cache?"), isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button(L("Clear cache"), role: .destructive) {
                model.clearLocalSessionCache()
                bytes = LocalReplicaCache.bytes
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Deletes saved messages, pictures and Mesh from this device. Keys, device connections and provider history are kept. New updates download again when connected."))
        }
    }

    private func refreshCache() {
        ReplicaImageStore.shared.prune()
        bytes = LocalReplicaCache.bytes
    }
}
