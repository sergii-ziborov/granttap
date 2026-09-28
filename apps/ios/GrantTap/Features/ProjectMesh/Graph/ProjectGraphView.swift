import SwiftUI
#if targetEnvironment(macCatalyst)
import WebKit
#endif

struct ProjectGraphView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var pending = false
    @State private var feedback: String?

    private var reports: [ProjectRepositoryGraph] {
        (currentSnapshot.repositoryGraphs ?? []).sorted { $0.repositoryId < $1.repositoryId }
    }

    private var currentSnapshot: ProjectMeshSnapshot {
        model.meshSnapshots[snapshot.projectId] ?? snapshot
    }

    var body: some View {
        graphContent
        .background(Theme.bg)
        .pageNavigationTitle(L("Graph"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("project.graph")
        .onChange(of: reports) { _ in
            if pending {
                pending = false
                feedback = L("Computer analysis report received.")
            }
        }
    }

    @ViewBuilder private var graphContent: some View {
        #if targetEnvironment(macCatalyst)
        if reports.isEmpty {
            ScrollView { emptyState.padding() }
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text(String(format: L("%d repository reports in this Mesh"), reports.count))
                    if reports.contains(where: \.truncated) { Text(L("Partial graph")) }
                    Spacer()
                    buildButton
                }
                .font(.caption)
                .padding(.horizontal)
                MeshCyberboardView(reports: reports)
            }
        }
        #else
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if reports.isEmpty {
                    emptyState
                } else {
                    buildButton
                }
                if let feedback {
                    Text(feedback).font(.caption).foregroundStyle(pending ? Theme.muted : .orange)
                }
                if pending { ProgressView(L("Building architecture…")) }
                ForEach(reports) { report in
                    ProjectArchitectureDiagram(
                        report: report,
                        repositoryName: ProjectOtherSide.displayName(
                            of: report.repositoryId, in: currentSnapshot
                        )
                    )
                }
            }
            .padding()
        }
        #endif
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Architecture unavailable"), systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            Text(L("No repository architecture report is available in this Mesh yet. Build it on a linked computer to see components and evidenced relations."))
                .foregroundStyle(Theme.muted)
            if currentSnapshot.backbone?.nodes.isEmpty == false {
                Text(L("Mesh Backbone is present, but it does not replace a repository architecture analysis."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            buildButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var buildButton: some View {
        Button {
            if model.requestProjectGraphAnalysis(projectId: snapshot.projectId) {
                pending = true
                feedback = L("Requested on this Mesh's computers. Waiting for their reports.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
                    if pending {
                        pending = false
                        feedback = L("No analysis report arrived. Check the computer and repository binding in Health.")
                    }
                }
            } else {
                feedback = L("No connected computer can receive this Mesh's analysis request.")
            }
        } label: {
            Label(L("Build architecture now"), systemImage: "arrow.clockwise")
        }
        .disabled(pending)
        .accessibilityIdentifier("project.graph.analyze")
    }
}

#if targetEnvironment(macCatalyst)
private struct MeshCyberboardView: UIViewRepresentable {
    let reports: [ProjectRepositoryGraph]

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.02, green: 0.04, blue: 0.06, alpha: 1)
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("RepoLensGraph"),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.html").path) {
            webView.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        } else {
            webView.loadHTMLString("<p>Repo Lens graph is missing from this build.</p>", baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.reports = reports
        if !webView.isLoading { context.coordinator.deliver(to: webView) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(reports: reports) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var reports: [ProjectRepositoryGraph]
        private var deliveredDigest: String?

        init(reports: [ProjectRepositoryGraph]) { self.reports = reports }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            deliver(to: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }

        func deliver(to webView: WKWebView) {
            guard let data = try? JSONEncoder().encode(reports) else { return }
            let payload = data.base64EncodedString()
            guard deliveredDigest != payload else { return }
            deliveredDigest = payload
            webView.evaluateJavaScript("window.setMeshReports('\(payload)')") { _, error in
                if error != nil { self.deliveredDigest = nil }
            }
        }
    }
}
#endif
