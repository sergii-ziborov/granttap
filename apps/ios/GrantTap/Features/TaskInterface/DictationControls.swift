import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ListeningMicButton: View {
    let isRecording: Bool
    let isStarting: Bool
    let tint: Color
    let action: () -> Void
    @State private var pulse = false

    private var isActive: Bool { isRecording || isStarting }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isActive {
                    Circle()
                        .stroke(tint.opacity(0.45), lineWidth: 2)
                        .scaleEffect(pulse ? 1.35 : 0.9)
                        .opacity(pulse ? 0 : 1)
                }
                Image(systemName: isRecording ? "stop.fill" : (isStarting ? "waveform" : "mic.fill"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isActive ? .white : Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(isActive ? tint : Theme.surface, in: Circle())
                    .overlay(Circle().stroke(isActive ? .clear : Theme.line, lineWidth: 1))
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? L("Stop listening") :
                            (isStarting ? L("Starting microphone…") : L("Start dictation")))
        .onAppear { updatePulse() }
        .onChange(of: isRecording) { _ in updatePulse() }
        .onChange(of: isStarting) { _ in updatePulse() }
    }

    private func updatePulse() {
        pulse = false
        guard isActive else { return }
        withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

struct ListeningStatus: View {
    let isStarting: Bool
    let language: String?

    var body: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.mini).tint(Theme.claude)
            Text(isStarting ? "Starting microphone…" : "Listening… tap the red button to stop")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.claude)
            Spacer(minLength: 4)
            Text(language.map { "\($0) + tech EN" } ?? L("RU/EN auto"))
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.claude)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.claude.opacity(0.12), in: Capsule())
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

/// The same real attachment picker is used on the home composer, task detail,
/// and full chat. Chat selection is deliberately a separate control.
