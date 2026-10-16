import SwiftUI

/// A direct, per-chat shortcut beside attachments, on both Apple clients.
struct ComposerApprovalButton: View {
    let sessionId: String
    let session: SessionInfo
    @ObservedObject var model: AppModel
    @State private var showing = false

    private var mode: PersonalApprovalMode {
        ChatApprovalPreferences(sessionId: sessionId, session: session, model: model).mode
    }
    private var elevated: Bool { mode == .full || session.accessLevel == "full" }

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: mode.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(elevated ? Theme.riskMed : Theme.ink)
                .frame(width: 34, height: 34)
                .background(Theme.raised, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .pointerButtonStyle()
        .accessibilityLabel(L("Approval Mode"))
        .accessibilityValue(mode.label)
        .accessibilityIdentifier("composer.approval")
        .sheet(isPresented: $showing) {
            ChatSheetNavigation(title: L("Approval Mode"), doneIdentifier: "chat.approval.done",
                onClose: { showing = false }) {
                List {
                    ChatApprovalSection(sessionId: sessionId, session: session, model: model)
                    ChatApprovalAccessSection(sessionId: sessionId, session: session, model: model)
                }
            }
            #if targetEnvironment(macCatalyst)
            .frame(minWidth: 480, minHeight: 640)
            #endif
        }
    }
}
