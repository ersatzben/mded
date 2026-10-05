import Cocoa
import Quartz
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var markdown = ""
    private var completionHandler: ((Error?) -> Void)?
    private var isExpectingPageLoad = false

    // Finder previews are passive, so remote content is blocked: selecting a
    // file shouldn't let anyone know it was looked at. Local images still load.
    private static let remoteBlockList = """
    [{"trigger": {"url-filter": "^(https?|wss?|ftp)://"}, "action": {"type": "block"}}]
    """

    override func loadView() {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                            configuration: MarkdownRenderer.makeConfiguration(bundle: .main))
        webView.navigationDelegate = self
        self.view = webView
    }

    // Quick Look calls this on the main thread; the protocol just doesn't say so.
    nonisolated func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        MainActor.assumeIsolated {
            preparePreview(of: url, completionHandler: handler)
        }
    }

    private func preparePreview(of url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            handler(error)
            return
        }
        guard let decoded = TextCodec.decode(data) else {
            handler(CocoaError(.fileReadInapplicableStringEncoding))
            return
        }
        markdown = decoded.text
        completionHandler = handler

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "mded.block-remote",
            encodedContentRuleList: Self.remoteBlockList
        ) { [weak self] ruleList, _ in
            guard let self else { return }
            if let ruleList {
                self.webView.configuration.userContentController.add(ruleList)
            }
            // Relative image paths resolve against the file's folder, wherever the
            // extension's sandbox allows reading them.
            self.isExpectingPageLoad = true
            self.webView.loadHTMLString(MarkdownRenderer.pageHTML(bundle: .main),
                                        baseURL: MarkdownRenderer.pageBaseURL(forDirectory: url.deletingLastPathComponent()))
        }
    }

    private func finish(_ error: Error?) {
        completionHandler?(error)
        completionHandler = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isExpectingPageLoad else { return }
        isExpectingPageLoad = false
        MarkdownRenderer.render(markdown, in: webView) { [weak self] error in
            self?.finish(error)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isExpectingPageLoad = false
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isExpectingPageLoad = false
        finish(error)
    }

    /// The preview only ever shows its own page; links and redirects go nowhere.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let isSubframe = action.targetFrame.map { !$0.isMainFrame } ?? false
        let isPageLoad = isExpectingPageLoad && action.navigationType == .other
        decisionHandler(isSubframe || isPageLoad ? .allow : .cancel)
    }
}
