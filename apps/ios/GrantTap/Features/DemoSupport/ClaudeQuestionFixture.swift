import Foundation

extension AppModelDemoFixtures {
    static func claudeQuestion(at time: Double) -> ApprovalRequest {
        ApprovalRequest(type: "approval.request", requestId: "demo-claude-question", agent: "claude",
            kind: "question", tool: "AskUserQuestion", title: "How should this app be distributed?",
            command: nil, cwd: "/Projects/GrantTap", sessionId: codexSessionId,
            risk: .low, danger: nil, createdAt: time, questions: [
                ApprovalQuestion(question: "How should this app be distributed?", header: "Distribution",
                    options: [.init(label: "App Store", description: "Use a sandboxed build"),
                              .init(label: "Website", description: "Distribute a signed download")], multiSelect: false),
                ApprovalQuestion(question: "Which devices should we verify?", header: "Devices",
                    options: [.init(label: "iPhone", description: "Phone control"),
                              .init(label: "Mac", description: "Desktop control")], multiSelect: true)
            ])
    }
}
