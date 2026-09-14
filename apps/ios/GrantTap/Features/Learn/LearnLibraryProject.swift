import Foundation

/// One Task across several agents and computers, the policy that governs a
/// Project, and what happens when a Project is shared with another person.
extension LearnLibrary {
    static let project: [LearnTopic] = [
        LearnTopic(
            id: "mesh", icon: "point.3.connected.trianglepath.dotted",
            title: "One Task can outlive one agent",
            summary: "A Project holds Tasks; a Task holds every execution that worked on it.",
            body: [
                .text("A chat belongs to one agent on one computer. A Task does not: it keeps its identity while agents and computers come and go, and every execution of it — Claude here, Codex there — is listed under it."),
                .text("Agents publish bounded facts to each other: what they finished, what blocks them, which files they are holding, and what they decided. They never publish transcripts or hidden reasoning."),
                .heading("Claims"),
                .text("Every edit an agent makes becomes a claim it was seen to hold. The same file is a conflict; the same module is the warning that comes before one. The Task screen names who else is in these files while it can still be avoided."),
                .text("A claim outlives an agent that crashed or was closed. Touch and hold it and you release it yourself — the computer answers, and if it refuses, the claim comes back with the reason beside it."),
            ]
        ),
        LearnTopic(
            id: "handoff", icon: "arrow.left.arrow.right",
            title: "Handing a Task to another agent",
            summary: "A bounded capsule of facts, authorized from the phone, with a receipt.",
            body: [
                .text("A handoff moves a Task, not a folder. GrantTap builds a capsule from explicit facts — the goal, the git state, the files that changed, the tests, what remains — and the destination starts from the commit the capsule names."),
                .text("Nothing moves without you: the phone authorizes the handoff, and the receipt that comes back is bound to that exact capsule."),
                .heading("Uncommitted work"),
                .text("A capsule carries facts, not files, so uncommitted changes cannot travel inside one. Ask for a checkpoint and the source computer commits them to a branch of its own, touching neither your branch nor your working tree, and the capsule carries that commit."),
                .text("Nothing is pushed unless you ask for it. A push that fails blocks the move rather than losing it quietly, and a destination that lacks the commit fetches once before refusing."),
            ]
        ),
        LearnTopic(
            id: "governance", icon: "checkmark.seal",
            title: "Governance: one answer per Project",
            summary: "Allow, ask, or deny — for a whole kind, or one named capability.",
            body: [
                .text("Capabilities are decided per Project rather than per task. A policy names an effect for each kind — skills, MCP servers, shell and scripts, file writes, deploy, network — and may name one capability alone, so a single MCP server can be forbidden without forbidding every server."),
                .text("The phone writes the policy and hands it to every computer of the Project through the relay, which holds it until each one reads its mailbox. A computer that was asleep receives it when it returns."),
                .text("Each computer reports what it actually reached: enforced, observed only, unsupported, or unknown. Coverage is never claimed on a computer's behalf."),
            ]
        ),
        LearnTopic(
            id: "sharing", icon: "person.2",
            title: "Sharing a Project with another person",
            summary: "An invite, a role, and your phone checking everything that comes back.",
            body: [
                .text("A Project is shared from the phone that owns it, and that phone stays the hub: nothing the other person does reaches a computer without passing through it."),
                .text("Invite a person and you choose a role — Viewer, Member, or Admin — and the four answers under it: see the Project's chats, write to them, post to the Project, edit Governance. The invite is one code, good for fifteen minutes; their phone scans it under Projects → Join a Project."),
                .heading("What the hub checks"),
                .text("Every message, pause, handoff and release from their phone is checked here against their role before it is forwarded. What a role does not allow never reaches a computer, and their phone is told which rule stopped it."),
                .text("A member works with computers of their own. Adding one hands it the Project's mesh key over the pairing their phone already trusts; from then on its chats are the Project's and a Task can be handed to it."),
                .text("Changing a role takes effect at once. Removing a member stops the forwarding at once — though nothing they already saw can be recalled."),
            ]
        ),
    ]
}
