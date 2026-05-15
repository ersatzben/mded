import AppKit
import WebKit

class PreviewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var isLoaded = false
    private var pendingMarkdown: String?
    private var renderWorkItem: DispatchWorkItem?
    private var isSyncingScroll = false
    private var isEvening = false
    var onScrollChange: ((Double) -> Void)?
    var baseURL: URL?

    private static let renderDebounce: TimeInterval = 0.10

    override func loadView() {
        let config = WKWebViewConfiguration()
        // Allow file:// HTML to fetch local images (resolved against baseURL).
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(self, name: "previewScroll")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        let html = MarkdownRenderer.baseHTML(in: Bundle.main)
        webView.loadHTMLString(html, baseURL: baseURL)
        self.view = webView
    }

    func renderMarkdown(_ markdown: String) {
        guard isViewLoaded else {
            pendingMarkdown = markdown
            return
        }
        // Debounce: collapse keystroke-rate updates into one render per ~100ms.
        renderWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.isLoaded {
                self.render(markdown)
            } else {
                self.pendingMarkdown = markdown
            }
        }
        renderWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.renderDebounce, execute: work)
    }

    func syncScroll(fraction: Double) {
        guard isLoaded else { return }
        isSyncingScroll = true
        webView.evaluateJavaScript(
            "window.__mdedSuppressScrollEvent = true; document.documentElement.scrollTop = \(fraction) * (document.documentElement.scrollHeight - document.documentElement.clientHeight);"
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.isSyncingScroll = false
            }
        }
    }

    func applyAppearance(_ appearance: AppearancePreference) {
        isEvening = appearance.isEvening
        applyEveningClass()
    }

    private func applyEveningClass() {
        guard isViewLoaded, isLoaded else { return }
        webView.evaluateJavaScript("setEvening(\(isEvening ? "true" : "false"))") { _, _ in }
    }

    func reloadIfBaseURLChanged() {
        guard isViewLoaded else { return }
        let html = MarkdownRenderer.baseHTML(in: Bundle.main)
        isLoaded = false
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "previewScroll",
              !isSyncingScroll,
              let fraction = message.body as? Double else { return }
        onScrollChange?(min(max(fraction, 0), 1))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        // Install scroll listener after the page is ready.
        let scrollJS = """
        (function() {
            var ticking = false;
            window.addEventListener('scroll', function() {
                if (window.__mdedSuppressScrollEvent) {
                    window.__mdedSuppressScrollEvent = false;
                    return;
                }
                if (ticking) return;
                ticking = true;
                requestAnimationFrame(function() {
                    var max = document.documentElement.scrollHeight - document.documentElement.clientHeight;
                    if (max > 0) {
                        var frac = document.documentElement.scrollTop / max;
                        window.webkit.messageHandlers.previewScroll.postMessage(frac);
                    }
                    ticking = false;
                });
            }, { passive: true });
        })();
        """
        webView.evaluateJavaScript(scrollJS) { _, _ in }
        applyEveningClass()
        if let markdown = pendingMarkdown {
            render(markdown)
            pendingMarkdown = nil
        }
    }

    private func render(_ markdown: String) {
        guard let data = try? JSONEncoder().encode(markdown),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("render(\(jsonString))") { _, _ in }
    }

    deinit {
        renderWorkItem?.cancel()
    }
}
