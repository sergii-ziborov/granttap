import SwiftUI
import WatchKit

struct SessionsOverview: View {
    let sessions: [WatchSession]

    var body: some View {
        NavigationStack {
              List {
                  if sessions.isEmpty {
                      ContentUnavailableView(
                          L("No active tasks"),
                          systemImage: "bubble.left.and.bubble.right"
                      )
                  }
                  ForEach(sessions) { session in
                    NavigationLink {
                        SessionActivityView(session: session)
                    } label: {
                        HStack(spacing: pt(7)) {
                            Text(agentGlyph(session.agent))
                                .font(.system(size: pt(10), weight: .black, design: .monospaced))
                                .foregroundStyle(glyphInkFor(session.agent))
                                .frame(width: pt(18), height: pt(18))
                                .background(accentFor(session.agent), in: RoundedRectangle(cornerRadius: pt(5)))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .font(.system(size: pt(12), weight: .semibold))
                                    .lineLimit(1)
                                Text(stateWord(session.state))
                                    .font(.system(size: pt(9), weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                  }
                  Section {
                      NavigationLink {
                          WatchSettingsView()
                      } label: {
                          Label(L("Settings"), systemImage: "gearshape")
                      }
                  }
              }
              .navigationTitle(L("Sessions"))
        }
    }
}
