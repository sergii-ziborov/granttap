import Foundation

/// What is encrypted, what is stored, and what a person can check for
/// themselves.
extension LearnLibrary {
    static let trust: [LearnTopic] = [
        LearnTopic(
            id: "encryption", icon: "lock",
            title: "What the relay can and cannot read",
            summary: "Sealed envelopes, keys that never leave your devices.",
            body: [
                .text("Every payload between your phone, your watch and your computers is sealed on the device that sends it and opened only on the device it is addressed to. The relay routes ciphertext."),
                .text("What the relay necessarily sees is the shape of delivery: that a room exists, that something arrived for it, roughly how large it was, when it expires, and enough to wake a sleeping device. Pairing keys, task keys, prompts, commands, replies and attachments are not in that list."),
                .heading("On your devices"),
                .points([
                    "Pairing keys live in the keychain, one pair per linked computer.",
                    "Each Task has a key of its own, so one chat's contents cannot be read with another chat's key.",
                    "Chat history is stored encrypted on the phone and can be locked behind Face ID or the device passcode.",
                ]),
                .text("The bridge that runs on your computer and the relay itself are public and auditable; you do not have to take this page's word for any of it."),
            ]
        ),
        LearnTopic(
            id: "what-is-collected", icon: "hand.raised.slash",
            title: "What GrantTap collects",
            summary: "A push token, so a device can be woken. Nothing else.",
            body: [
                .text("GrantTap keeps the Apple push token for your devices, because without it a sleeping phone cannot be told that an agent is waiting. It is linked to the device, used for app functionality, and never used for tracking."),
                .points([
                    "No analytics of what you do in the app.",
                    "No advertising identifiers, and no advertising.",
                    "No task content, source code, prompts or commands on any server in readable form.",
                    "No biometric data: Face ID is checked by the system, and the app is only told yes or no.",
                ]),
                .text("The local audit log stays on the device. It records what was decided and when, so you can look back at your own answers."),
            ]
        ),
        LearnTopic(
            id: "demo", icon: "play.rectangle",
            title: "The Demo, and why it is labelled",
            summary: "Sample content that performs no real action.",
            body: [
                .text("Demo fills the app with deterministic sample tasks so you can look around before pairing anything. It is visibly labelled while it runs."),
                .text("Nothing in Demo reaches a computer: no command is executed, no message is delivered, and no pairing material or credential of yours appears in it. Leaving Demo puts the app back to what your own computers actually report."),
            ]
        ),
        LearnTopic(
            id: "when-things-break", icon: "wrench.and.screwdriver",
            title: "When something does not arrive",
            summary: "Where to look when a computer goes quiet.",
            body: [
                .text("A computer is Live when it has published recently. When it goes quiet the connection badge says so, and the tasks it owns stop claiming to be working."),
                .points([
                    "Check that the helper is running on the computer: it is what talks to the relay.",
                    "A message that could not be delivered stays in the outbox with a way to send it again.",
                    "Approvals that were answered while a computer was away are re-checked when it returns; a stale request cannot resurrect itself.",
                ]),
                .text("Troubleshooting in Settings collects the same facts into one screen, and the diagnostics report can be shared without carrying your task content with it."),
            ]
        ),
    ]
}
