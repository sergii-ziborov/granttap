import Foundation

/// What a person does with an agent once the two are connected: the chat, the
/// turn, and the hold.
extension LearnLibrary {
    static let work: [LearnTopic] = [
        LearnTopic(
            id: "the-chat", icon: "bubble.left.and.bubble.right",
            title: "A Task is a chat you can read",
            summary: "Visible messages and what each tool did, not the agent's private reasoning.",
            body: [
                .text("Open a Task and you see the conversation as it happened: what the agent said, which tools it ran, what each call cost, and what it changed. A tool call folds to one line; open it and the command and its result are there."),
                .heading("What is not there"),
                .text("Hidden reasoning is never forwarded. What a model thinks to itself stays on the computer with the agent; GrantTap carries the visible conversation and bounded facts about the calls."),
                .text("A chat is fetched and decrypted once. Opening it again is instant, and opening it from a call in history lands on that call rather than at the end."),
            ]
        ),
        LearnTopic(
            id: "the-turn", icon: "paperplane",
            title: "Sending the next turn",
            summary: "Text, voice, photos and files — and the terms the turn runs under.",
            body: [
                .text("The composer is one block: what you attached, what you are writing, and under it the controls that decide how the turn runs. The plus adds photos, a camera shot, files, a project skill, or one allowed MCP server. The microphone dictates in the language you speak, including Russian."),
                .text("The pill beside it names the model the turn will use. Leave it as the chat's own, or pick another for this chat; the choice stays with the chat rather than with the app."),
                .heading("When a message cannot go"),
                .text("Every message is queued with a delivery mark. Sent, delivered, or failed — and a failed one offers to go again. A message is never silently dropped: if the computer is asleep, the message waits in the bounded queue and arrives when it wakes."),
            ]
        ),
        LearnTopic(
            id: "pause", icon: "pause.circle",
            title: "Holding an agent, and letting it go",
            summary: "A pause is enforced where the work happens, not only on the screen.",
            body: [
                .text("Hold a chat from the phone and its computer refuses every tool call that chat makes — the agent is told to wait, and a delivery already running for it is stopped. It is not a display state; it is a hold at the place the work happens."),
                .text("Resume lifts it. Ask it to continue and the computer answers at once, then delivers one continuation prompt in the background, so starting again is a single tap."),
                .text("The screen answers your tap immediately, but it only shows a hold as done once the computer confirms. If the computer refuses, or says nothing at all, the phone puts back what it showed before and tells you so."),
            ]
        ),
        LearnTopic(
            id: "capabilities", icon: "slider.horizontal.3",
            title: "What an agent is allowed to reach",
            summary: "Skills, MCP servers and shell, decided for a whole computer or one chat.",
            body: [
                .text("An agent can reach skills, MCP servers, and your shell. Each of those is a switch you own. Turn one off for a computer and it is off in every chat on it; no per-chat setting can turn it back on."),
                .text("Inside one chat you can be narrower still: allow this MCP server for this conversation only, or refuse the shell here while leaving it elsewhere."),
                .text("When a rule stops a call, the refusal appears in the chat beside the call it stopped, naming the rule. You never have to guess why an agent stopped."),
            ]
        ),
    ]
}
