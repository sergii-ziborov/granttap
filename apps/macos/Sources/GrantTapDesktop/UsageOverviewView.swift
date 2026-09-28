import DesktopInspectorCore
import SwiftUI

struct UsageOverviewView: View {
    let snapshot: InspectorSnapshot?
    let workspace: MeshWorkspaceSummary?

    private var summary: WorkspaceSummary { WorkspaceSummary(page: snapshot?.invocations) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Usage").font(.largeTitle.bold())
                Text("Mesh activity across this Mac")
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    DesktopCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tasks").foregroundStyle(.secondary)
                            Text((workspace?.task_count ?? 0).formatted()).font(.title.bold())
                        }
                    }
                    DesktopCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Chats").foregroundStyle(.secondary)
                            Text((workspace?.project_count ?? 0).formatted()).font(.title.bold())
                        }
                    }
                }
                Text("Recorded tool activity").font(.headline)
                if summary.tools.isEmpty {
                    DesktopCard {
                        Text("No tool activity is available in the current local evidence page.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    DesktopCard {
                        VStack(spacing: 0) {
                            ForEach(summary.tools) { tool in
                                HStack {
                                    Text(tool.name)
                                    Spacer()
                                    Text("\(tool.count)×").monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                Divider()
                            }
                        }
                    }
                }
                Text("Task and chat counts come from the local Mesh index. Tool events, when shown, are a limited evidence page; token and cost totals are not available through this connection.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
