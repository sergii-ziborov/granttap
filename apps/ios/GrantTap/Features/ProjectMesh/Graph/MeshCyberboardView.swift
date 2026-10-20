import SwiftUI
import WebKit

struct MeshCyberboardView: UIViewRepresentable {
    let reports: [ProjectRepositoryGraph]
    @Binding var failed: Bool
    var onFullscreen: () -> Void = {}

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "graphStatus")
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_GRAPH_RENDER_FAILURE"] == "1" {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "window.graphFailure(new Error('Injected rendering failure'))",
                injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        #endif
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.scrollView.delaysContentTouches = false
        webView.accessibilityIdentifier = "code-towers.web"
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

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "graphStatus")
    }

    func makeCoordinator() -> Coordinator { Coordinator(reports: reports, failed: $failed, onFullscreen: onFullscreen) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var reports: [ProjectRepositoryGraph]
        @Binding var failed: Bool
        private var deliveredReports: [ProjectRepositoryGraph]?
        private var deliveredLanguage: String?
        private var deliveryGeneration = 0
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

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failed = true }

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
            let language = AppLocale.code
            // JSON key order is not identity. Equal reports must preserve the
            // renderer, source search and camera through native layout updates.
            guard deliveredReports != reports || deliveredLanguage != language else { return }
            guard let data = try? JSONEncoder().encode(reports) else { return }
            let payload = data.base64EncodedString()
            deliveredReports = reports
            deliveredLanguage = language
            deliveryGeneration += 1
            let generation = deliveryGeneration
            webView.evaluateJavaScript("window.setMeshReports('\(payload)', '\(language)')") { _, error in
                guard error != nil, self.deliveryGeneration == generation else { return }
                self.deliveredReports = nil
                self.deliveredLanguage = nil
                self.failed = true
            }
        }
    }
}
