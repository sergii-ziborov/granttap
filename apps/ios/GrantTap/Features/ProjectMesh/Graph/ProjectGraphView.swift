import SwiftUI
#if targetEnvironment(macCatalyst)
import WebKit
#endif

struct ProjectGraphView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var pending = false
    @State private var feedback: String?
    #if targetEnvironment(macCatalyst)
    @State private var macMode: MacGraphMode = .components
    @State private var selectedRepositoryId: String?
    @State private var selectedComponentId: String?
    @State private var webFailed = false
    #endif

    private var reports: [ProjectRepositoryGraph] {
        ProjectInsightReports.reports(currentSnapshot)
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
        .task(id: snapshot.projectId) {
            #if targetEnvironment(macCatalyst)
            if !reports.contains(where: { !$0.nodes.isEmpty }),
               !ProjectGraphModel.make(from: currentSnapshot).nodes.isEmpty {
                macMode = .repositories
            }
            #endif
            await model.observeProjectInsights(projectId: snapshot.projectId)
        }
        .onChange(of: reports) { _ in
            if pending && reports.contains(where: { $0.analysisStatus != "UNAVAILABLE" }) {
                pending = false
                feedback = L("Computer analysis report received.")
            } else if pending && !reports.isEmpty {
                feedback = L("Analysis reported an unavailable repository. Waiting for another computer or retry.")
            }
        }
    }

    @ViewBuilder private var graphContent: some View {
        #if targetEnvironment(macCatalyst)
        VStack(spacing: 0) {
            HStack {
                Text(String(format: L("%d repository reports in this Mesh"), reports.count))
                if reports.contains(where: \.truncated) { Text(L("Partial graph")) }
                Spacer()
                buildButton
            }
            .font(.caption).padding(.horizontal)
            Picker(L("Graph view"), selection: $macMode) {
                ForEach(MacGraphMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented).padding(.horizontal)
            if let feedback { Text(feedback).font(.caption).foregroundStyle(Theme.muted) }
            if pending { ProgressView(L("Building architecture…")) }
            switch macMode {
            case .components: macComponents
            case .repositories: ProjectRepositoryNetworkView(snapshot: currentSnapshot)
            case .code:
                if webFailed {
                    ScrollView {
                        VStack(alignment: .leading) {
                            Text(L("Code city could not open; component graph remains available."))
                            Button(L("Retry code city")) { webFailed = false }
                            macComponentReports
                        }.padding()
                    }
                } else if reports.contains(where: { !$0.nodes.isEmpty || $0.codeMap?.files.isEmpty == false }) {
                    MeshCyberboardView(reports: reports, failed: $webFailed)
                } else { ScrollView { emptyState.padding() } }
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

    #if targetEnvironment(macCatalyst)
    private var macComponents: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if reports.isEmpty { emptyState }
                if let report = reports.first(where: {
                    $0.repositoryId == selectedRepositoryId && !$0.nodes.isEmpty
                }) ?? reports.first(where: { !$0.nodes.isEmpty }) {
                    Picker(L("Repository"), selection: $selectedRepositoryId) {
                        ForEach(reports.filter { !$0.nodes.isEmpty }) { option in
                            Text(ProjectOtherSide.displayName(of: option.repositoryId,
                                in: currentSnapshot)).tag(Optional(option.repositoryId))
                        }
                    }
                    .onAppear { selectedRepositoryId = report.repositoryId }
                    .onChange(of: selectedRepositoryId) { _ in selectedComponentId = nil }
                    ProjectArchitectureScene(report: report, selectedId: $selectedComponentId)
                        .id("\(report.repositoryId):\(report.revision)")
                        .frame(minHeight: 420)
                        .accessibilityIdentifier("project.graph.components")
                }
                macComponentReports
            }.padding()
        }
    }

    private var macComponentReports: some View {
        ForEach(reports) { report in
            ProjectArchitectureDiagram(report: report,
                repositoryName: ProjectOtherSide.displayName(of: report.repositoryId,
                    in: currentSnapshot))
        }
    }
    #endif

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
            if let feedback { Text(feedback).font(.caption).foregroundStyle(Theme.muted) }
            if pending { ProgressView(L("Building architecture…")) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var buildButton: some View {
        Button {
            pending = true
            feedback = L("Building architecture…")
            Task {
                let result = await model.requestProjectGraphAnalysis(projectId: snapshot.projectId)
                feedback = result.message
                pending = result == .requested
                if pending {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
                        if pending {
                            pending = false
                            feedback = L("No analysis report arrived. Check the computer and repository binding in Health.")
                        }
                    }
                }
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
    @Binding var failed: Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "graphStatus")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.02, green: 0.04, blue: 0.06, alpha: 1)
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("RepoLensGraph"),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.html").path) {
            webView.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        } else {
            DispatchQueue.main.async { failed = true }
            webView.loadHTMLString("<p>Repo Lens graph is missing from this build.</p>", baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.reports = reports
        if !webView.isLoading { context.coordinator.deliver(to: webView) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(reports: reports, failed: $failed) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var reports: [ProjectRepositoryGraph]
        @Binding var failed: Bool
        private var deliveredDigest: String?

        init(reports: [ProjectRepositoryGraph], failed: Binding<Bool>) {
            self.reports = reports
            _failed = failed
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            deliver(to: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failed = true
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) { failed = true }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "graphStatus", message.body as? String == "failed" { failed = true }
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
                if error != nil { self.deliveredDigest = nil; self.failed = true }
            }
        }
    }
}
#endif
