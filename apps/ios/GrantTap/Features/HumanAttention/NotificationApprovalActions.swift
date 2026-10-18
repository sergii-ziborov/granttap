import SwiftUI

struct NotificationApprovalActions: View {
    let request: ApprovalRequest
    @ObservedObject var model: AppModel
    @State private var answer = ""

    var body: some View {
        if model.approvalDecisionsInFlight[request.requestId] != nil {
            ApprovalSubmissionStatus(saved: model.approvalDecisionWasStoredOnRelay(request),
                                     message: model.approvalDecisionDeliveryMessage(request))
        } else if model.isMcpOpenAsk(request) {
            VStack {
                TextField(L("Your answer"), text: $answer)
                Button(L("Send")) { model.answerQuestion(request.requestId, answer) }
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else {
            HStack(spacing: 10) {
                DecisionActionButton(title: L(model.isMcpAskApproval(request) ? "No" : "Deny"),
                                     tint: Theme.riskHigh, filled: false) { decide(false) }
                DecisionActionButton(title: L(model.isMcpAskApproval(request) ? "Yes" : "Allow"),
                                     tint: Theme.accent(for: request.agent),
                                     textColor: Theme.glyphInk(for: request.agent)) { decide(true) }
                    .accessibilityIdentifier("approval.allow.\(request.requestId)")
            }
        }
    }

    private func decide(_ allow: Bool) {
        if model.isMcpAskApproval(request) { model.answerQuestion(request.requestId, allow ? "yes" : "no") }
        else { model.decide(request, allow ? "allow" : "deny") }
    }
}
