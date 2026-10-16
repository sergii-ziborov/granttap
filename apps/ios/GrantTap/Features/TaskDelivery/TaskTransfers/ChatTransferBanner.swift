import SwiftUI

extension TaskChatView {
    var transferRequiresConfirmation: Bool {
        model.transferNotice(for: currentSession).map { $0.continuedAt == nil } ?? false
    }

    @ViewBuilder
    var transferBanner: some View {
        if transferRequiresConfirmation, let notice = model.transferNotice(for: currentSession) {
            VStack(alignment: .leading, spacing: 8) {
                Label(notice.isPending ? L("Transfer queued") : L("Transferred"), systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                Text(notice.isPending
                     ? L("Waiting for the destination computer. Continuing here starts a parallel branch.")
                     : L("Continue in the destination chat. Continuing here starts a parallel branch."))
                    .font(.caption).foregroundStyle(Theme.muted)
                HStack {
                    if let targetSessionId = notice.targetSessionId {
                        Button(L("Open destination")) {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                model.sessionToOpen = targetSessionId
                            }
                        }
                    }
                    Spacer()
                    Button(L("Continue anyway")) { showTransferContinuation = true }
                        .disabled(model.taskTransfers.pending[chatSessionId] != nil)
                }
                .font(.caption.weight(.semibold)).pointerButtonStyle()
                if model.taskTransfers.pending[chatSessionId] != nil {
                    ProgressView(L("Waiting for computer confirmation…")).font(.caption)
                }
                if let error = model.taskTransfers.errors[chatSessionId] {
                    Text(error).font(.caption).foregroundStyle(Theme.riskHigh)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
            .accessibilityIdentifier("chat.transfer.banner")
            .alert(L("Continue this branch?"), isPresented: $showTransferContinuation) {
                Button(L("Cancel"), role: .cancel) {}
                Button(L("Continue anyway")) { model.continueTransferredTask(currentSession) }
            } message: {
                Text(L("The destination will keep working. Both branches can make changes independently."))
            }
        }
    }
}
