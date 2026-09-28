import Foundation

/// What GrantTap is, how a computer becomes one it can speak to, and what
/// happens the first time an agent needs a person.
enum LearnLibrary {
    static let start: [LearnTopic] = [
        LearnTopic(
            id: "what-it-is", icon: "hand.raised",
            title: "What GrantTap is, and what it is not",
            summary: "A remote control for coding agents that already run on your computer.",
            body: [
                .text("A coding agent runs on your Mac or PC, in your repository, with your files. It is fast until it reaches something only a person should decide: a command that deletes, a push that publishes, a question it cannot answer for itself. Then it stops and waits — and until now it waited until you came back to the desk."),
                .text("GrantTap carries that moment to your phone. You see what the agent wants to run, in the chat it came from, and you allow it, refuse it, or answer the question. The agent carries on without you walking back."),
                .heading("What it is not"),
                .points([
                    "It is not an AI model. GrantTap never answers for the agent.",
                    "It is not a terminal. It shows what the agent said it will do; it does not give you a shell on your computer.",
                    "It does not sit between you and your model provider. Your prompts and completions never pass through GrantTap.",
                    "It does not receive your provider credentials, and it cannot sign in anywhere on your behalf.",
                ]),
                .text("What it does is narrow on purpose: it is the yes, the no, the answer, and the next message — from wherever you are."),
            ]
        ),
        LearnTopic(
            id: "how-it-connects", icon: "qrcode",
            title: "How your phone and your computer find each other",
            summary: "One helper on the computer, one scan on the phone, and a room only the two of them can read.",
            body: [
                .text("On the computer you install one helper and run one command. It registers itself with the coding agents you already use, so they can reach it when they need a person."),
                .command("npm install -g granttap-mcp\ngranttap setup"),
                .text("Setup prints a one-time QR code. You scan it with this app. Behind the scan, the two devices create a pair of keys and a room on the relay; from then on the computer and the phone speak only inside that room."),
                .heading("What the relay can see"),
                .text("The relay carries sealed envelopes. It knows a room exists, that something arrived, how large it was, and when it expires — enough to deliver a message and wake a device. It cannot open one. The keys that would open it were made on your two devices and never left them."),
                .text("You can link several computers to one phone. Each gets its own room and its own key; a message for one is unreadable to the others."),
            ]
        ),
        LearnTopic(
            id: "first-approval", icon: "checkmark.shield",
            title: "The first time an agent asks",
            summary: "A request arrives with the command, the risk, and the chat it belongs to.",
            body: [
                .text("When the agent reaches something that needs you, the request appears under Needs You: which agent, on which computer, in which chat, and the exact command it intends to run."),
                .text("Allow lets it through. Deny stops it and tells the agent so. Either way the answer is written down on the phone, and the agent hears it within a second or two."),
                .heading("From the wrist"),
                .text("Apple Watch shows the same request and takes the same two answers. The watch does not talk to the relay itself: it hands the decision to the iPhone it is paired with, and the iPhone delivers it. If the phone is out of reach, the watch says so rather than pretending the answer went out."),
                .text("If nobody answers, nothing happens. A request that times out is not a yes — the agent keeps waiting or gives up on its own, and GrantTap never decides for you."),
            ]
        ),
    ]
}
