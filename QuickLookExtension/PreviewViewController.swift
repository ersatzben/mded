import Cocoa
import Quartz
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    var webView: WKWebView!
    private var completionHandler: ((Error?) -> Void)?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.navigationDelegate = self
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let html = MarkdownRenderer.htmlForQuickLook(markdown: markdown, in: Bundle.main)
            self.completionHandler = handler
            webView.loadHTMLString(html, baseURL: nil)
        } catch {
            handler(error)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completionHandler?(nil)
        completionHandler = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completionHandler?(error)
        completionHandler = nil
    }
}
