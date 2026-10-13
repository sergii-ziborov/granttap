import SwiftUI
#if targetEnvironment(macCatalyst)
import WebKit
#endif

struct ProjectGraphView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    #if targetEnvironment(macCatalyst)
    @State private var macMode: MacGraphMode = .components
    @State private var selectedRepositoryId: String?
    @State private var selectedComponentId: String?
    @State private var webFailed = false
    @State private var codeFullscreen = false
    @State private var codeViewRevision = 0
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

    }

    @ViewBuilder private var graphContent: some View {
        #if targetEnvironment(macCatalyst)
        VStack(spacing: 0) {
            buildCard.padding()
            Picker(L("Graph view"), selection: $macMode) {
                ForEach(MacGraphMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented).padding(.horizontal)
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
                    MeshCyberboardView(reports: reports, failed: $webFailed) { codeFullscreen = true }
                        .id(codeViewRevision)
                } else { Spacer(minLength: 0) }
            }
        }
        .fullScreenCover(isPresented: $codeFullscreen, onDismiss: { codeViewRevision += 1 }) {
            MeshCyberboardView(reports: reports, failed: $webFailed) { codeFullscreen = false }
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button { codeFullscreen = false } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel(L("Exit full screen")).padding(12)
                }
        }
        #else
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                buildCard
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
        .refreshable { _ = await model.requestProjectGraphAnalysis(projectId: snapshot.projectId) }
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private var macComponents: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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

    private var buildCard: some View {
        ProjectGraphBuildCard(
            request: model.projectGraphRequests[snapshot.projectId], reports: reports,
            needsAnalysis: ProjectInsightReports.needsAnalysis(currentSnapshot)
        ) {
            Task { _ = await model.requestProjectGraphAnalysis(projectId: snapshot.projectId) }
        }
    }
}

#if targetEnvironment(macCatalyst)
private struct MeshCyberboardView: UIViewRepresentable {
    let reports: [ProjectRepositoryGraph]
    @Binding var failed: Bool
    var onFullscreen: () -> Void = {}

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
        context.coordinator.onFullscreen = onFullscreen
        if !webView.isLoading { context.coordinator.deliver(to: webView) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(reports: reports, failed: $failed, onFullscreen: onFullscreen) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var reports: [ProjectRepositoryGraph]
        @Binding var failed: Bool
        private var deliveredDigest: String?
        var onFullscreen: () -> Void

        init(reports: [ProjectRepositoryGraph], failed: Binding<Bool>, onFullscreen: @escaping () -> Void) {
            self.reports = reports
            _failed = failed
            self.onFullscreen = onFullscreen
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
            if message.name == "graphStatus", message.body as? String == "fullscreen" { onFullscreen() }
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
            let digest = payload + AppLocale.code
            guard deliveredDigest != digest else { return }
            deliveredDigest = digest
            webView.evaluateJavaScript("window.setMeshReports('\(payload)', '\(AppLocale.code)')") { _, error in
                if error != nil { self.deliveredDigest = nil; self.failed = true }
            }
        }
    }
}
#endif
