import SwiftUI

struct ChatCacheView: View {
    @EnvironmentObject private var model: AppModel
    @State private var bytes = LocalReplicaCache.bytes
    @State private var confirmClear = false

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
                Text(L("Messages from active chats, pictures and Mesh are saved on this device. Earlier messages download automatically while connected. Saved content remains readable offline until you clear it."))
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
        .onAppear { bytes = LocalReplicaCache.bytes }
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
}
