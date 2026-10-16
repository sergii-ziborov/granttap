import SwiftUI

/// The modal header is part of the content layout. A safe-area inset inside a
/// Catalyst navigation sheet can be visible above the region that accepts clicks.
struct ChatSheetNavigation<Content: View>: View {
    let title: String
    let doneIdentifier: String
    var closeTitle: String = L("Done")
    var closeDisabled = false
    var dismissesPresentation = true
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        CompatNavigationStack {
            #if targetEnvironment(macCatalyst)
            VStack(spacing: 0) {
                MacPageHeader(title: title) {
                    ChatSheetDoneButton(identifier: doneIdentifier, title: closeTitle, dismissesPresentation: dismissesPresentation, onClose: onClose)
                        .disabled(closeDisabled)
                }
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarHidden(true)
            #else
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        ChatSheetDoneButton(identifier: doneIdentifier, title: closeTitle, dismissesPresentation: dismissesPresentation, onClose: onClose)
                            .disabled(closeDisabled)
                    }
                }
            #endif
        }
    }
}
