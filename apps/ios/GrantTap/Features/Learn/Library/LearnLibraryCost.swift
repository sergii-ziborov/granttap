import Foundation

/// What the numbers mean, where they come from, and what the subscription buys.
extension LearnLibrary {
    static let cost: [LearnTopic] = [
        LearnTopic(
            id: "usage", icon: "chart.bar",
            title: "Where the time and the tokens went",
            summary: "Every figure on the Usage screen opens what it counted.",
            body: [
                .text("Usage counts a period: the chats that ran, the tokens they spent, the tools they called, what failed, what is still waiting for you, and which computers were awake."),
                .text("A number nobody can look into is a claim you have to take on trust, so each one opens the thing it counted: the chats behind Sessions, the calls behind Tool calls, the decisions behind Approvals, the computers and the agents they carry."),
                .heading("Measured, attributed, unknown"),
                .text("Processor time and peak memory are attributed rather than measured: a finished call is read back from a transcript and costed from the samples taken while it ran. GrantTap says which it is instead of presenting one as the other."),
                .text("A capability being available is not the same as it being used, and unknown usage is never presented as confirmed use."),
            ]
        ),
        LearnTopic(
            id: "reports", icon: "doc.text",
            title: "Reporting a Task",
            summary: "A PDF to read, or a CSV with every table.",
            body: [
                .text("A Task can be reported from the phone: tokens, tool calls, wrong turns, processor time, peak memory and wall time, by tool and by execution. The PDF is for reading and forwarding; the CSV carries every table for a spreadsheet."),
                .text("Nothing leaves the phone until you choose where it goes. The report is built on the device from what the phone already holds."),
            ]
        ),
        LearnTopic(
            id: "subscription", icon: "creditcard",
            title: "What the subscription pays for",
            summary: "Remote infrastructure — never model access, never your agents.",
            body: [
                .text("GrantTap is free to download and free to use on the computer in front of you. What needs paying for is the remote part: the encrypted relay, waking a sleeping device, and the bounded queue that holds a message until it can be delivered."),
                .text("Tiers differ only by how many computers you link. Coding agents on each computer are unlimited and are never counted or charged for."),
                .heading("What it never buys"),
                .text("It does not buy model access. GrantTap has no model and never receives your provider credentials; what you spend with Anthropic, OpenAI, or anyone else is between you and them."),
                .text("If the subscription lapses, local history and everything encrypted on the device stay yours and stay readable."),
            ]
        ),
    ]
}
