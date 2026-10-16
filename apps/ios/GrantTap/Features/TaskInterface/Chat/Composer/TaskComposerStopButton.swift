import SwiftUI

/// The existing computer-confirmed pause is reachable directly during a turn.
struct TaskComposerStopButton: View {
    let pending: Bool
    let stop: () -> Void

    var body: some View {
        Button(action: stop) {
            Group {
                if pending { ProgressView().tint(Theme.glyphInk(for: "codex")) }
                else { Image(systemName: "stop.fill").font(.system(size: 14, weight: .bold)) }
            }
            .foregroundStyle(Theme.glyphInk(for: "codex"))
            .frame(width: 36, height: 36)
            .background(Theme.codex, in: Circle())
        }
        .pointerButtonStyle(cornerRadius: 18)
        .disabled(pending)
        .accessibilityLabel(pending ? L("Pausing…") : L("Stop task"))
        .accessibilityIdentifier("composer.stop")
        .help(L("Stop and pause task"))
    }
}

extension TaskChatView {
    var showsStopControl: Bool {
        controlPending || (!currentSession.isPaused && currentSession.state == "working")
    }
}
