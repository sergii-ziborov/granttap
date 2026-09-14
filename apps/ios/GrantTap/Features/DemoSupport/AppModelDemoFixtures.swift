import Foundation
import UIKit

enum AppModelDemoFixtures {
    static let codexSessionId = "granttap-review-demo"
    static let claudeSessionId = "granttap-claude-demo"

    struct ChatCapture {
        let activity: SessionActivity
        let delivery: OutgoingDelivery
    }

    /// A real local-delivery shape for screenshot and preview regression checks.
    /// The bytes are generated locally and never contain user data.
    static func chatCapture(at now: Double) -> ChatCapture {
        let id = "demo-photo-delivery"
        let photo = UserAttachment(
            name: "release-check.jpg", mimeType: "image/jpeg",
            data: capturePhotoData().base64EncodedString()
        )
        let delivery = OutgoingDelivery(
            id: id, text: L("Please verify this build 40 capture."),
            agent: "codex", cwd: nil, sessionId: codexSessionId,
            requestId: nil, roomId: nil, attachments: [photo],
            preferredMcp: nil, skill: nil,
            createdAt: now - 20_000, updatedAt: now - 18_000,
            attempts: 1, state: .delivered, error: nil, nextRetryAt: nil
        )
        let activity = SessionActivity(
            sessionId: codexSessionId, agent: "codex", state: "waiting",
            entries: [
                ActivityEntry(
                    id: "demo-chat-agent", kind: "message",
                    text: L("The latest app build is installed. I am checking the chat fixes now."),
                    createdAt: now - 34_000
                ),
                ActivityEntry(
                    id: "local-user-\(id)", kind: "user", text: delivery.text,
                    createdAt: delivery.createdAt, attachments: [photo.name]
                ),
                ActivityEntry(
                    id: "demo-chat-ok", kind: "final", text: "ok", createdAt: now - 8_000
                ),
            ],
            generatedAt: now
        )
        return ChatCapture(activity: activity, delivery: delivery)
    }

    private static func capturePhotoData() -> Data {
        let size = CGSize(width: 900, height: 1_200)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 0.035, green: 0.055, blue: 0.09, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.16, green: 0.95, blue: 0.67, alpha: 0.18).setFill()
            UIBezierPath(ovalIn: CGRect(x: 470, y: -90, width: 620, height: 620)).fill()
            UIColor(red: 0.18, green: 0.48, blue: 1, alpha: 0.22).setFill()
            UIBezierPath(ovalIn: CGRect(x: -220, y: 720, width: 720, height: 720)).fill()
            let card = UIBezierPath(
                roundedRect: CGRect(x: 90, y: 250, width: 720, height: 700),
                cornerRadius: 54
            )
            UIColor(red: 0.075, green: 0.095, blue: 0.14, alpha: 0.96).setFill()
            card.fill()
            let centered = NSMutableParagraphStyle()
            centered.alignment = .center
            let title: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 92, weight: .black),
                .foregroundColor: UIColor.white,
                .paragraphStyle: centered,
            ]
            let detail: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 42, weight: .semibold),
                .foregroundColor: UIColor(red: 0.36, green: 1, blue: 0.76, alpha: 1),
                .paragraphStyle: centered,
            ]
            ("BUILD 40" as NSString).draw(
                in: CGRect(x: 120, y: 420, width: 660, height: 130),
                withAttributes: title
            )
            ("CHAT VERIFIED\n\nPHOTO · KEYBOARD · DEDUPE" as NSString).draw(
                in: CGRect(x: 140, y: 600, width: 620, height: 220),
                withAttributes: detail
            )
        }
        guard let data = image.jpegData(compressionQuality: 0.86) else {
            preconditionFailure("deterministic chat capture must encode")
        }
        return data
    }

    static func approvals(at now: Double) -> [ApprovalRequest] {
        [ApprovalRequest(
            type: "approval.request", requestId: "demo-approval", agent: "codex",
            kind: "command", tool: "shell", title: L("Publish the release build?"),
            command: "npm run test && npm run deploy", cwd: "/Users/reviewer/granttap",
            sessionId: codexSessionId, risk: .medium, danger: nil, createdAt: now
        )]
    }

    static func questions(at now: Double) -> [AgentEvent] {
        [AgentEvent(
            type: "agent.event", text: L("Should I run the final regression suite?"),
            requestId: "demo-question", kind: "question",
            sessionId: codexSessionId, createdAt: now
        )]
    }

    static func sessions(at now: Double) -> [SessionInfo] {
        [
            SessionInfo(
                sessionId: codexSessionId, agent: "codex",
                projectId: AppModelDemoMeshFixtures.projectId,
                taskId: AppModelDemoMeshFixtures.releaseTaskId, computerId: "Workstation",
                title: L("GrantTap release audit"), cwd: "/Users/reviewer/granttap",
                branch: "release/1.0", worktree: "/Users/reviewer/granttap-release",
                model: "gpt-5.6-sol",
                state: "working", startedAt: now - 12 * 60 * 1000, lastActivityAt: now,
                tokensSession: 18_420, tokensLastTurn: 1_284,
                contextTokensUsed: 227_400, contextWindow: 258_400,
                mcpServers: [
                    McpServerInfo(name: "granttap", configuredEnabled: true, allowed: true,
                                  authStatus: nil),
                    McpServerInfo(name: "github", configuredEnabled: true, allowed: true,
                                  authStatus: "authenticated", title: "GitHub", metadataSource: "mcp"),
                    McpServerInfo(name: "figma", configuredEnabled: true, allowed: false,
                                  authStatus: "authenticated", title: "Figma", metadataSource: "mcp"),
                ],
                skills: [
                    SkillInfo(name: "release-check", description: "Run the repository release checklist"),
                    SkillInfo(name: "ios-qa", description: "Verify the iPhone and Apple Watch apps"),
                ],
                childThreads: [
                    ChildThreadInfo(
                        threadId: "demo-agent-release", parentThreadId: codexSessionId,
                        title: L("Release metadata audit"), agentName: L("Reviewer agent"),
                        depth: 1, state: "working", startedAt: now - 4 * 60 * 1000,
                        lastActivityAt: now - 18_000, tokensSession: 2_340, tokensLastTurn: 420
                    ),
                    ChildThreadInfo(
                        threadId: "demo-agent-ios", parentThreadId: codexSessionId,
                        title: L("iPad compatibility check"), agentName: L("iOS agent"),
                        depth: 1, state: "idle", startedAt: now - 7 * 60 * 1000,
                        lastActivityAt: now - 70_000, tokensSession: 1_180, tokensLastTurn: 190
                    ),
                ]
            ),
            SessionInfo(
                sessionId: claudeSessionId, agent: "claude",
                projectId: AppModelDemoMeshFixtures.projectId,
                taskId: AppModelDemoMeshFixtures.pairingTaskId, computerId: "MacBook",
                title: L("Pairing API review"), cwd: "/Users/reviewer/granttap",
                branch: "claude/pairing-api", worktree: "/Users/reviewer/granttap-pairing",
                model: "claude-opus-4-1",
                summary: L("Waiting for the final pairing schema before integration."),
                accessLevel: "workspace", state: "waiting",
                startedAt: now - 34 * 60 * 1000, lastActivityAt: now - 2 * 60 * 1000,
                tokensSession: 26_780, tokensLastTurn: 2_146,
                contextTokensUsed: 71_200, contextWindow: 200_000,
                mcpServers: [
                    McpServerInfo(name: "github", configuredEnabled: true, allowed: true,
                                  authStatus: "authenticated", title: "GitHub", metadataSource: "mcp"),
                    McpServerInfo(name: "cloudflare", configuredEnabled: true, allowed: true,
                                  authStatus: "authenticated", title: "Cloudflare", metadataSource: "mcp"),
                ],
                skills: [SkillInfo(
                    name: "security-review", description: "Audit the repository trust boundary"
                )]
            ),
        ]
    }

    static func history(at now: Double) -> [SessionInfo] {
        [SessionInfo(
            sessionId: "granttap-history-demo", agent: "codex", title: L("Earlier release checklist"),
            cwd: "/Users/reviewer/granttap", branch: "main", model: "gpt-5.6-sol", state: "idle",
            startedAt: now - 2 * 24 * 60 * 60 * 1000,
            lastActivityAt: now - 20 * 60 * 60 * 1000,
            tokensSession: 9_120, tokensLastTurn: 640
        )]
    }

    static func activities(at now: Double) -> [String: SessionActivity] {
        [
            codexSessionId: SessionActivity(
                type: "session.activity", sessionId: codexSessionId, agent: "codex",
                state: "working", entries: [
                    ActivityEntry(
                        id: "demo-message", kind: "message",
                        text: L("Checking the release metadata, privacy manifest, and public links."),
                        createdAt: now - 45_000
                    ),
                    ActivityEntry(
                        id: "demo-tool", kind: "tool", text: "xcodebuild test",
                        createdAt: now - 25_000, toolName: "Bash",
                        capabilities: [ObservedCapability(
                            kind: .cli, name: "Bash", toolName: "Bash",
                            commandPreview: "xcodebuild test -scheme GrantTap",
                            estimatedContextTokens: 96
                        )],
                        estimatedContextTokens: 96, childThreadId: "demo-agent-release",
                        childThreadTitle: L("Release metadata audit"), childThreadDepth: 1
                    ),
                    ActivityEntry(
                        id: "demo-final", kind: "final",
                        text: L("The build is ready for a final approval."), createdAt: now - 5_000
                    ),
                ], generatedAt: now
            ),
            claudeSessionId: SessionActivity(
                type: "session.activity", sessionId: claudeSessionId, agent: "claude",
                state: "waiting", entries: [
                    ActivityEntry(
                        id: "demo-claude-message", kind: "message",
                        text: L("Tracing pairing, task-key isolation, and delivery receipts."),
                        createdAt: now - 150_000
                    ),
                    ActivityEntry(
                        id: "demo-claude-tool", kind: "tool", text: "npm test -- security",
                        createdAt: now - 130_000
                    ),
                    ActivityEntry(
                        id: "demo-claude-final", kind: "final",
                        text: L("The relay cannot decrypt device or task payloads."),
                        createdAt: now - 120_000
                    ),
                ], generatedAt: now
            ),
        ]
    }

}
