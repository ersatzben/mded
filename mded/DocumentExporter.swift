import AppKit
import WebKit

/// Renders a document offscreen for printing and export: light theme, actual
/// size, fully rendered, independent of the window's preview (which may be
/// hidden, zoomed, dark or mid-render).
@MainActor
final class DocumentExporter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    // WebKit prints most reliably from a view that's in a window; this one is
    // never shown.
    private let window: NSWindow
    private var pageLoad: CheckedContinuation<Void, Error>?
    private var printCompletion: ((Bool) -> Void)?

    private override init() {
        let size = NSRect(x: 0, y: 0, width: 816, height: 1056)
        webView = WKWebView(frame: size, configuration: MarkdownRenderer.makeConfiguration(bundle: .main))
        webView.appearance = NSAppearance(named: .aqua)
        window = NSWindow(contentRect: size, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    /// Loads and renders `markdown`, resolving relative images in `directory`.
    static func prepare(markdown: String, directory: URL?, literalUnderscores: Bool) async throws -> DocumentExporter {
        let exporter = DocumentExporter()
        try await withCheckedThrowingContinuation { continuation in
            exporter.pageLoad = continuation
            exporter.webView.loadHTMLString(MarkdownRenderer.pageHTML(bundle: .main),
                                            baseURL: MarkdownRenderer.pageBaseURL(forDirectory: directory))
        }
        if !literalUnderscores {
            MarkdownRenderer.setOptions(["literalUnderscores": false], in: exporter.webView)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            MarkdownRenderer.render(markdown, in: exporter.webView) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        await MarkdownRenderer.whenImagesLoaded(in: exporter.webView)
        return exporter
    }

    /// A self-contained HTML file: styles inlined, local images embedded.
    func standaloneHTML(title: String) async throws -> String {
        let body = try await MarkdownRenderer.exportBodyHTML(in: webView)
        return MarkdownRenderer.pageHTML(bundle: .main, title: title, body: body)
    }

    /// Prints with the standard panel as a sheet on `window`, or straight to a
    /// paginated PDF at `pdfURL`.
    func print(attachedTo window: NSWindow, savingPDFTo pdfURL: URL? = nil, completion: @escaping (Bool) -> Void) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        if let pdfURL {
            info.jobDisposition = .save
            info.dictionary().setObject(pdfURL, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue as NSString)
        }

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = pdfURL == nil
        operation.showsProgressPanel = true
        // Without a frame, WebKit's print view lays out at zero size and prints blank pages.
        operation.view?.frame = webView.bounds
        printCompletion = completion
        operation.runModal(for: window, delegate: self,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool,
                                            contextInfo: UnsafeMutableRawPointer?) {
        printCompletion?(success)
        printCompletion = nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoad?.resume()
        pageLoad = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pageLoad?.resume(throwing: error)
        pageLoad = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pageLoad?.resume(throwing: error)
        pageLoad = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // Only the page load itself; nothing in the document navigates.
        decisionHandler(pageLoad != nil && action.navigationType == .other ? .allow : .cancel)
    }
}
