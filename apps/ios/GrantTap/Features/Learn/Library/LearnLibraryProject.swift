import Foundation

/// One Task across several agents and computers, the policy that governs a
/// Mesh, and what happens when it is shared with another person.
extension LearnLibrary {
    static let project: [LearnTopic] = [
        LearnTopic(
            id: "mesh", icon: "point.3.connected.trianglepath.dotted",
            title: "One Task can outlive one agent",
            summary: "A Mesh can link several repositories and Tasks. Each Task keeps its execution history.",
            body: [
                .text("An execution runs with one agent on one computer. A Task keeps its identity while agents and computers change, and every execution — Claude here, Codex there — is listed under it."),
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
            title: "Governance for a Mesh",
            summary: "Allow, ask, or deny — for a whole kind, or one named capability.",
            body: [
                .text("Capabilities are decided for the Mesh. A policy names an effect for each kind — skills, MCP servers, shell and scripts, file writes, deploy, network — and may name one capability alone, so a single MCP server can be forbidden without forbidding every server."),
                .text("The controlling device sends the policy to computers in the Mesh through the relay. A computer that was asleep receives it when it returns."),
                .text("Each computer reports what it actually reached: enforced, observed only, unsupported, or unknown. Coverage is never claimed on a computer's behalf."),
            ]
        ),
        LearnTopic(
            id: "sharing", icon: "person.2",
            title: "Sharing a Mesh with another person",
            summary: "An invite, a role, and checks before shared actions reach a computer.",
            body: [
                .text("The controlling device checks a person's role before forwarding shared actions to a computer."),
                .text("Invite a person and choose a role — Viewer, Member, or Admin — and permissions to see messages, send them, post to the Mesh, and edit Governance. The invite is one code, good for fifteen minutes; they scan it under Mesh → Join a Mesh."),
                .heading("What the hub checks"),
                .text("Every message, pause, handoff and release is checked against the member's role before it is forwarded. What a role does not allow never reaches a computer, and the member sees which rule stopped it."),
                .text("A member works with computers of their own. Adding one gives it the Mesh key over an existing trusted pairing; then a Task can be handed to it."),
                .text("Changing a role takes effect at once. Removing a member stops the forwarding at once — though nothing they already saw can be recalled."),
            ]
        ),
    ]
}
