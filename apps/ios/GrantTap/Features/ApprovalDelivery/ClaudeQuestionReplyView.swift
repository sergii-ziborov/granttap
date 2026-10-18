import SwiftUI

/// Native agent questions require explicit answers, never an automation rule.
struct ClaudeQuestionReplyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let request: ApprovalRequest
    @State private var selections: [Int: Set<Int>] = [:]
    @State private var otherSelections: Set<Int> = []
    @State private var otherText: [Int: String] = [:]
    @State private var submissionError: String?
    @State private var submittedHere = false
    @FocusState private var editingQuestion: Int?

    private var questions: [ApprovalQuestion] { request.questions ?? [] }
    private var readableQuestions: Bool {
        !questions.isEmpty && Set(questions.map(\.question)).count == questions.count
            && questions.allSatisfy { !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var queued: ApprovalDecisionQueue.Entry? {
        model.approvalDecisionQueue.entries.first { $0.requestId == request.requestId }
    }
    private var waiting: Bool {
        queued != nil || model.approvalDecisionsInFlight[request.requestId] != nil
    }
    private var online: Bool {
        guard let room = model.requestSourceRoom[request.requestId] else { return false }
        return model.roomRuntime[room]?.socketUp == true
    }
    private var completedCount: Int {
        questions.indices.filter { answer(at: $0) != nil }.count
    }
    private var savedAnswers: [String: String] {
        guard let note = queued?.note, let data = note.data(using: .utf8),
              let answers = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return answers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let chatId = model.approvalChatId(request) {
                Button { model.sessionToOpen = chatId } label: {
                    Label(L("Open chat"), systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                .pointerButtonStyle()
                .accessibilityIdentifier("approval.open-chat.\(request.requestId)")
            }
            if !readableQuestions {
                Label(L("Questions could not be read. Refresh this request."), systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(Theme.riskMed).card()
            } else {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    questionCard(question, index: index)
                }
                submissionControls
            }
        }
        .onChange(of: model.pending.map(\.requestId)) { ids in
            if submittedHere && !ids.contains(request.requestId) && !waiting { dismiss() }
        }
        .onChange(of: model.approvalDecisionWasStoredOnRelay(request)) { saved in
            if submittedHere && saved { dismiss() }
        }
        .onAppear { submittedHere = waiting }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("Done")) { editingQuestion = nil }
                    .accessibilityIdentifier("approval.question.keyboard-done")
            }
        }
    }

    private func questionCard(_ question: ApprovalQuestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(question.header.isEmpty ? L("Question") : question.header)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(index + 1) / \(questions.count)")
                    .font(Theme.mono(11)).foregroundStyle(Theme.muted)
            }
            Text(question.question).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("approval.question.\(index)")
            if waiting, let saved = savedAnswers[question.question] ?? answer(at: index) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Your answer")).font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
                    Text(saved).font(.subheadline).foregroundStyle(Theme.ink).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            } else {
                Text(question.multiSelect ? L("Select all that apply") : L("Select one"))
                    .font(.caption).foregroundStyle(Theme.muted)
                ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                    optionRow(option, question: question, index: index, optionIndex: optionIndex)
                }
                otherRow(question, index: index)
            }
        }
        .card()
    }

    private func optionRow(_ option: ApprovalQuestionOption, question: ApprovalQuestion,
                           index: Int, optionIndex: Int) -> some View {
        let selected = selections[index]?.contains(optionIndex) == true
        return Button {
            submissionError = nil
            if question.multiSelect {
                var values = selections[index] ?? []
                if selected { values.remove(optionIndex) } else { values.insert(optionIndex) }
                selections[index] = values
            } else {
                selections[index] = [optionIndex]
                otherSelections.remove(index)
            }
        } label: {
            choiceLabel(option.label, description: option.description, selected: selected,
                        multiSelect: question.multiSelect)
        }
        .pointerButtonStyle(selected: selected, cornerRadius: Theme.radiusSmall)
        .disabled(waiting)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("approval.question.option.\(index).\(optionIndex)")
    }

    private func otherRow(_ question: ApprovalQuestion, index: Int) -> some View {
        let selected = otherSelections.contains(index)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                submissionError = nil
                if selected { otherSelections.remove(index) } else { otherSelections.insert(index) }
                if !question.multiSelect { selections[index] = [] }
            } label: {
                choiceLabel(L("Other"), description: "", selected: selected, multiSelect: question.multiSelect)
            }
            .pointerButtonStyle(selected: selected, cornerRadius: Theme.radiusSmall)
            .disabled(waiting)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("approval.question.other.\(index)")
            if selected {
                TextEditor(text: Binding(
                    get: { otherText[index] ?? "" },
                    set: {
                        otherText[index] = $0
                        submissionError = nil
                    }
                ))
                .font(.subheadline).frame(minHeight: 72, maxHeight: 120).padding(12)
                .foregroundStyle(Theme.ink).tint(Theme.accent(for: request.agent))
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line))
                .disabled(waiting)
                .focused($editingQuestion, equals: index)
                .accessibilityIdentifier("approval.question.other-text.\(index)")
            }
        }
    }

    private func choiceLabel(_ label: String, description: String, selected: Bool,
                             multiSelect: Bool) -> some View {
        let symbol = multiSelect ? (selected ? "checkmark.square.fill" : "square")
            : (selected ? "checkmark.circle.fill" : "circle")
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 19))
                .foregroundStyle(selected ? Theme.accent(for: request.agent) : Theme.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                if !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .background(selected ? Theme.accent(for: request.agent).opacity(0.06) : Theme.surface,
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
            .stroke(selected ? Theme.accent(for: request.agent).opacity(0.4) : Theme.line))
    }

    private var submissionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if waiting {
                ApprovalSubmissionStatus(saved: model.approvalDecisionWasStoredOnRelay(request),
                    message: model.approvalDecisionDeliveryMessage(request))
            } else {
                Text(String(format: L("Answered %d of %d"), completedCount, questions.count))
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
                if !online {
                    Label(L("Offline · answers will wait for this computer to reconnect."), systemImage: "wifi.slash")
                        .font(.caption).foregroundStyle(Theme.riskMed)
                }
            }
            if let submissionError {
                Label(submissionError, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(Theme.riskHigh)
            }
            Button(action: submit) {
                Label(L("Submit answers"), systemImage: "paperplane.fill")
            }
            .buttonStyle(FilledButton(tint: Theme.accent(for: request.agent),
                                      textColor: Theme.glyphInk(for: request.agent)))
            .disabled(waiting || model.demoMode || completedCount != questions.count)
            .accessibilityIdentifier("approval.question.submit")
        }
        .card()
    }

    private func answer(at index: Int) -> String? {
        let question = questions[index]
        var values = question.options.indices.filter { selections[index]?.contains($0) == true }
            .map { question.options[$0].label }
        if otherSelections.contains(index) {
            let other = (otherText[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !other.isEmpty else { return nil }
            values.append(other)
        }
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    private func submit() {
        guard !waiting, completedCount == questions.count, readableQuestions else { return }
        var answers: [String: String] = [:]
        for index in questions.indices { answers[questions[index].question] = answer(at: index) }
        guard let data = try? JSONEncoder().encode(answers), let note = String(data: data, encoding: .utf8) else {
            submissionError = L("Answers could not be saved. Try again.")
            return
        }
        model.decide(request, "allow", note: note)
        submittedHere = waiting
        if !waiting { submissionError = L("Answers could not be saved. Try again.") }
    }
}
