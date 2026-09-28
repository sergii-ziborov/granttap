import SwiftUI

struct ChatCacheView: View {
    @EnvironmentObject private var model: AppModel
    @State private var bytes = SessionActivityPersistence.bytes
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
                Text(L("Fetched history stays on this Mac until cleared. iPhone keeps at least the two latest user requests. Clearing this copy does not delete provider conversations or device connections."))
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
        .onAppear { bytes = SessionActivityPersistence.bytes }
        .confirmationDialog(L("Clear local chat cache?"), isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button(L("Clear cache"), role: .destructive) {
                model.clearLocalSessionCache()
                bytes = SessionActivityPersistence.bytes
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Only GrantTap’s saved copy is cleared. Provider history and linked devices remain available."))
        }
    }
}
