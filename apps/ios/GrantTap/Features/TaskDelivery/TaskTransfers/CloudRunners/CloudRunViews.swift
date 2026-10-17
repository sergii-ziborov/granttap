import SwiftUI

/// A started cloud run, said as what it is: a link, not a live chat.
struct CloudRunStartedNote: View {
    let run: ExecutionSessionLink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(format: L("%@ started."), run.external?.title(computer: run.computerId) ?? run.sessionId),
                  systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ok)
            CloudRunLink(run: run)
        }
        .accessibilityIdentifier("handoff.cloudStarted")
    }
}

/// The link the computer reported, or the run's id when the CLI printed none.
struct CloudRunLink: View {
    let run: ExecutionSessionLink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let url = run.external?.link {
                Link(destination: url) {
                    Label(L("Open the cloud run"), systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityIdentifier("cloudRun.open")
            } else {
                Text(String(format: L("The provider reported no link. Its id is %@."), run.sessionId))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Text(L("GrantTap cannot follow a cloud run's progress. Check it with the provider."))
                .font(.caption2).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
