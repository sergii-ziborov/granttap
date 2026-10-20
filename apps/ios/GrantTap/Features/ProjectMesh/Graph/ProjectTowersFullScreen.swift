import SwiftUI

/// The same offline Repo Lens workspace is used on iPhone, iPad and Mac.
struct ProjectTowersFullScreen: View {
    let report: ProjectRepositoryGraph
    let repositoryName: String
    let map: ProjectCodeMap
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false
    @State private var immersive = false
    @State private var showScope = false

    private var receivedReport: ProjectRepositoryGraph {
        var value = report
        value.codeMap = map
        return value
    }

    private var scopeLabel: String {
        ProjectCodeMapScope(map).partialTitle ?? report.analysisStatus ?? L("Unknown")
    }

    var body: some View {
        Group {
            if failed {
                ProjectNativeTowersView(report: report, repositoryName: repositoryName, map: map)
                    .safeAreaInset(edge: .top) {
                        Button(L("Retry code city")) { failed = false }
                            .padding(8).frame(maxWidth: .infinity).background(.regularMaterial)
                    }
            } else {
                VStack(spacing: 0) {
                    if !immersive { header }
                    MeshCyberboardView(reports: [receivedReport], failed: $failed) {
                        immersive.toggle()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !immersive {
                        HStack {
                            Text("\(map.files.count)/\(map.totalFiles) \(L("Files"))")
                            Spacer()
                            Button(scopeLabel) { showScope = true }
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary).tint(Color.cyan.opacity(0.8)).padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if immersive {
                        Button { immersive = false } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel(L("Show graph panels")).padding(8)
                    }
                }
            }
        }
        .background(Color(red: 0.02, green: 0.04, blue: 0.06).ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.colorScheme, .dark)
        .alert(scopeLabel, isPresented: $showScope) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(L(ProjectCodeMapScope(map) != .complete
                ? "The computer limited some source details or links to fit this report. File counts show the received towers."
                : "The reported analysis is complete."))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .tint(.white)
                .accessibilityLabel(L("Close code towers"))
            VStack(alignment: .leading, spacing: 3) {
                Text(repositoryName).font(.system(size: 14, weight: .semibold, design: .monospaced)).lineLimit(1)
                Text("Weavatrix \(report.weavatrixVersion)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.cyan.opacity(0.65))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).background(Color(red: 0.03, green: 0.06, blue: 0.09))
    }
}
