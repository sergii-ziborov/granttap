import SwiftUI

/// The existing computer-confirmed pause is reachable directly during a turn.
struct TaskComposerStopButton: View {
    let pending: Bool
    var active = true
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
            .overlay {
                if active && !pending { TaskWorkingRing() }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .pointerButtonStyle(cornerRadius: 22)
        .disabled(pending)
        .accessibilityLabel(pending ? L("Pausing…") : L("Stop task"))
        .accessibilityValue(pending ? L("Pausing…") : (active ? L("Working") : L("Checking connection")))
        .accessibilityIdentifier("composer.stop")
        .help(L("Stop and pause task"))
    }
}

/// Indeterminate activity, never a completion percentage or a server heartbeat.
struct TaskWorkingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func rotation(at date: Date, reduceMotion: Bool) -> Double {
        reduceMotion ? -90 : date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) * 200
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            Circle().trim(from: 0.05, to: 0.77)
                .stroke(Theme.codex.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 43, height: 43)
                .rotationEffect(.degrees(Self.rotation(at: context.date, reduceMotion: reduceMotion)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension TaskChatView {
    var showsStopControl: Bool {
        controlPending || (!currentSession.isPaused && currentSession.state == "working")
    }

    var hasLiveTaskActivity: Bool {
        if model.demoMode { return true }
        #if targetEnvironment(macCatalyst)
        if model.usesLocalTaskDelivery(for: currentSession) { return true }
        #endif
        return model.chatComputerRoute(forSessionId: chatSessionId)?.phase == .live
    }
}
