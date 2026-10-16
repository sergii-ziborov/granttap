import SwiftUI

/// One compact control shared by iPhone and Mac; only native levels are selectable.
struct ComposerEffortPicker: View {
    let agent: String
    @Binding var selection: TurnEffort?
    let fallback: TurnEffort?
    let choices: [TurnEffort]

    private var scale: EffortScale { EffortScale(choices: choices, selection: selection, fallback: fallback) }

    var body: some View {
        Section(L("Effort")) {
            if choices.isEmpty {
                Text(L("Reasoning effort is included in this provider's model variants."))
                    .font(.caption).foregroundStyle(Theme.muted)
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill").foregroundStyle(tint)
                        Menu {
                            Button { selection = nil } label: {
                                if selection == nil { Label(L("Keep current effort"), systemImage: "checkmark") }
                                else { Text(L("Keep current effort")) }
                            }
                            .accessibilityIdentifier("composer.effort.current")
                            ForEach(choices) { choice in
                                Button { selection = choice } label: {
                                    if selection == choice { Label(choice.label, systemImage: "checkmark") }
                                    else { Text(choice.label) }
                                }
                                .accessibilityIdentifier("composer.effort.select.\(choice.id)")
                            }
                        } label: {
                            Text(scale.effective?.label ?? L("Keep current effort"))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(scale.effective == nil ? Theme.muted : tint)
                        }
                        .accessibilityIdentifier("composer.effort")
                        .accessibilityLabel(L("Reasoning effort") + ": "
                            + (scale.effective?.label ?? L("Keep current effort")))
                        Spacer(minLength: 4)
                        Button { selection = nil } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 30, height: 30).contentShape(Rectangle())
                        }
                        .pointerButtonStyle()
                        .foregroundStyle(Theme.muted)
                        .disabled(selection == nil)
                        .accessibilityLabel(L("Keep current effort"))
                        .accessibilityIdentifier("composer.effort.reset")
                    }
                    ZStack {
                        EffortAnimatedTrack(effort: scale.effective, fraction: scale.fraction)
                        EffortSlider(scale: scale, selection: $selection)
                    }
                    .frame(height: 46)
                    HStack {
                        Text(L("Faster"))
                        Spacer()
                        Text(L("More reasoning"))
                    }.font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var tint: Color { scale.effective == .max || scale.effective == .ultra ? .purple : .blue }
}
