import SwiftUI

struct NotificationRequestFocus: Identifiable { let id: String }

/// A notification opens its request above the current tab or chat. The signed
/// notification is a navigation hint; only authenticated payloads offer actions.
struct NotificationRequestSheet: View {
    let requestId: String
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var answer = ""
    @State private var waitingForRefresh = false

    var body: some View {
        Group {
            if let request = model.pending.first(where: { $0.requestId == requestId }) {
                ApprovalDetailSheet(request: request).environmentObject(model)
                    .safeAreaInset(edge: .bottom) {
                        if request.kind != "question" {
                            NotificationApprovalActions(request: request, model: model)
                                .padding(16).background(Theme.bg)
                        }
                    }
            } else {
                ChatSheetNavigation(title: L("Request"), doneIdentifier: "notification.request.done", onClose: close) {
                    List {
                        if let question = model.questions.first(where: { $0.requestId == requestId }) {
                            Section(L("Question")) {
                                Text(question.text).textSelection(.enabled)
                                TextEditor(text: $answer).frame(minHeight: 120)
                                    .accessibilityIdentifier("notification.request.answer")
                                Button(L("Send")) { model.answerQuestion(requestId, answer) }
                                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } else if let event = model.meshNeedsYouEvents.first(where: { $0.eventId == requestId }) {
                            Section {
                                Text(L("This Mesh needs your attention."))
                                Button(L("Open task")) { model.sessionToOpen = event.sourceSessionId; close() }
                            }
                        } else {
                            Section {
                                ProgressView(L("Loading the request…"))
                                    .accessibilityIdentifier("notification.request.loading")
                                Text(L("The request is being refreshed from your computer. Decisions appear after the encrypted request is received."))
                                    .font(.caption).foregroundStyle(Theme.muted)
                                Button(L("Retry")) { refresh() }.disabled(waitingForRefresh)
                            }
                        }
                    }
                }
            }
        }
        .task { refresh() }
    }

    private func refresh() {
        guard !waitingForRefresh else { return }
        waitingForRefresh = true
        model.handleRemoteWake { _ in }
        Task {
            await model.refreshSessions()
            waitingForRefresh = false
        }
    }
}

extension ContentView {
    var notificationFocusBinding: Binding<NotificationRequestFocus?> {
        Binding(get: {
            guard !security.launching, !security.locked,
                  let id = model.focusedApprovalId else { return nil }
            return NotificationRequestFocus(id: id)
        }, set: { value in
            if value == nil && !security.locked { model.focusedApprovalId = nil }
        })
    }
}
