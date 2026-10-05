import AppKit
import WebKit

class PreviewController: NSViewController {
    private(set) var webView: WKWebView!
    private let findBar = PreviewFindBar()
    private var webViewBelowFindBar: NSLayoutConstraint!
    private var webViewAtTop: NSLayoutConstraint!

    private var isLoaded = false
    // True between asking WebKit to load the preview page and that load
    // finishing. Any other main-frame navigation is refused (see decidePolicyFor).
    private var isExpectingPageLoad = false
    private var lastMarkdown: String?
    private var needsRender = false
    private var renderWorkItem: DispatchWorkItem?
    private var isEvening = false
    private var literalUnderscores = true
    private var zoom = 1.0
    var onScrollChange: ((ScrollPosition) -> Void)?
    /// Called after the page (re)loads and the current markdown is rendered.
    var onPageReady: (() -> Void)?
    var baseURL: URL?

    /// False while the pane is collapsed: renders wait until it's shown again.
    var isActive = true {
        didSet {
            if isActive && !oldValue { scheduleRender(after: 0) }
        }
    }

    private static let renderDebounce: TimeInterval = 0.10

    override func loadView() {
        let config = MarkdownRenderer.makeConfiguration(bundle: .main)
        // WKUserContentController retains its handlers; a proxy avoids the
        // controller → web view → configuration → controller cycle.
        config.userContentController.add(WeakScriptMessageHandler(self),
                                          contentWorld: MarkdownRenderer.world,
                                          name: MarkdownRenderer.scrollMessageName)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.pageZoom = zoom

        findBar.isHidden = true
        findBar.onFind = { [weak self] text, backwards, restart in
            self?.find(text, backwards: backwards, restart: restart)
        }
        findBar.onClose = { [weak self] in self?.hideFindBar() }

        let container = NSView()
        for subview in [findBar, webView!] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        webViewBelowFindBar = webView.topAnchor.constraint(equalTo: findBar.bottomAnchor)
        webViewAtTop = webView.topAnchor.constraint(equalTo: container.topAnchor)
        NSLayoutConstraint.activate([
            findBar.topAnchor.constraint(equalTo: container.topAnchor),
            findBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webViewAtTop,
        ])
        self.view = container
        loadPage()
    }

    private func loadPage() {
        isLoaded = false
        isExpectingPageLoad = true
        webView.loadHTMLString(MarkdownRenderer.pageHTML(bundle: .main),
                               baseURL: MarkdownRenderer.pageBaseURL(forDirectory: baseURL))
    }

    func renderMarkdown(_ markdown: String) {
        lastMarkdown = markdown
        needsRender = true
        guard isViewLoaded else { return }
        // Debounce: collapse keystroke-rate updates into one render per ~100ms.
        scheduleRender(after: Self.renderDebounce)
    }

    private func scheduleRender(after delay: TimeInterval) {
        renderWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.renderIfNeeded() }
        renderWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func renderIfNeeded() {
        guard isLoaded, isActive, needsRender, let markdown = lastMarkdown else { return }
        needsRender = false
        MarkdownRenderer.render(markdown, in: webView)
    }

    func syncScroll(to position: ScrollPosition) {
        guard isLoaded, isActive else { return }
        MarkdownRenderer.scroll(toLine: position.line, atEnd: position.atEnd, in: webView)
    }

    func applyAppearance(_ appearance: AppearancePreference) {
        guard appearance.isEvening != isEvening else { return }
        isEvening = appearance.isEvening
        if isLoaded {
            MarkdownRenderer.setEvening(isEvening, in: webView)
        }
    }

    func setZoom(_ zoom: Double) {
        guard zoom != self.zoom else { return }
        self.zoom = zoom
        if isViewLoaded { webView.pageZoom = zoom }
    }

    func setLiteralUnderscores(_ on: Bool) {
        guard on != literalUnderscores else { return }
        literalUnderscores = on
        guard isLoaded else { return }
        MarkdownRenderer.setOptions(["literalUnderscores": on], in: webView)
        needsRender = lastMarkdown != nil
        scheduleRender(after: 0)
    }

    /// Reloads the page so relative image paths resolve against the new base
    /// (after Save As or a move), then re-renders the current text.
    func reloadIfBaseURLChanged() {
        guard isViewLoaded else { return }
        needsRender = lastMarkdown != nil
        loadPage()
    }

    fileprivate func didReceiveScroll(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let line = (body["line"] as? NSNumber)?.doubleValue else { return }
        let atEnd = (body["atEnd"] as? NSNumber)?.boolValue ?? false
        onScrollChange?(ScrollPosition(line: max(0, line), atEnd: atEnd))
    }

    // MARK: - Focus and find

    var containsFirstResponder: Bool {
        guard isViewLoaded, let responder = view.window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: view)
    }

    func focus() {
        view.window?.makeFirstResponder(webView)
    }

    func performFind(_ action: NSTextFinder.Action) {
        switch action {
        case .showFindInterface, .showReplaceInterface:
            showFindBar()
        case .nextMatch, .previousMatch:
            if findBar.searchText.isEmpty {
                showFindBar()
            } else {
                find(findBar.searchText, backwards: action == .previousMatch, restart: false)
            }
        case .setSearchString:
            Task { @MainActor in
                let selection = await MarkdownRenderer.selectedText(in: webView)
                if !selection.isEmpty { findBar.searchText = selection }
            }
        case .hideFindInterface:
            hideFindBar()
        default:
            NSSound.beep()
        }
    }

    private func showFindBar() {
        if findBar.isHidden {
            findBar.isHidden = false
            webViewAtTop.isActive = false
            webViewBelowFindBar.isActive = true
        }
        findBar.focus()
    }

    private func hideFindBar() {
        guard !findBar.isHidden else { return }
        findBar.isHidden = true
        webViewBelowFindBar.isActive = false
        webViewAtTop.isActive = true
        focus()
    }

    private func find(_ text: String, backwards: Bool, restart: Bool) {
        guard !text.isEmpty else {
            findBar.showResult(found: true)
            return
        }
        // A changed search starts again from the top rather than after the last match.
        if restart { MarkdownRenderer.clearSelection(in: webView) }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(text, configuration: configuration) { [weak self] result in
            self?.findBar.showResult(found: result.matchFound)
        }
    }

    deinit {
        renderWorkItem?.cancel()
    }
}

// MARK: - Navigation

extension PreviewController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isExpectingPageLoad else { return }
        isExpectingPageLoad = false
        isLoaded = true
        if !literalUnderscores {
            MarkdownRenderer.setOptions(["literalUnderscores": false], in: webView)
        }
        if isEvening {
            MarkdownRenderer.setEvening(true, in: webView)
        }
        renderIfNeeded()
        onPageReady?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isExpectingPageLoad = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isExpectingPageLoad = false
    }

    /// The preview never navigates away from its own page. Link clicks are
    /// routed (browser, mded, Finder, or an in-page anchor); anything else a
    /// document tries, such as a meta refresh, is refused. Iframes load normally.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let frame = action.targetFrame else {
            // target="_blank": let WebKit ask for a new web view, which routes the link.
            decisionHandler(.allow)
            return
        }
        if !frame.isMainFrame || (isExpectingPageLoad && action.navigationType == .other) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated, let url = action.request.url {
            openLink(url)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.navigationType == .linkActivated, let url = action.request.url {
            openLink(url)
        }
        return nil
    }

    private func openLink(_ url: URL) {
        if let fragment = url.fragment, isCurrentPage(url) {
            MarkdownRenderer.scroll(toAnchor: fragment.removingPercentEncoding ?? fragment, in: webView)
            return
        }
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto":
            NSWorkspace.shared.open(url)
        case "file":
            openLocalFile(URL(fileURLWithPath: url.path))
        case LocalFileSchemeHandler.scheme:
            if let fileURL = LocalFileSchemeHandler.fileURL(for: url) {
                openLocalFile(fileURL)
            }
        default:
            NSSound.beep()
        }
    }

    /// `#section` links resolve against the page's own URL (the document's
    /// folder as a mded-file: URL, or about:blank for an untitled document).
    private func isCurrentPage(_ url: URL) -> Bool {
        func withoutFragment(_ url: URL?) -> String? {
            guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            parts.fragment = nil
            return parts.string
        }
        return withoutFragment(url) == withoutFragment(webView.url)
    }

    /// Markdown files open in mded. Anything else is revealed in Finder rather
    /// than opened, so a link in a document can't launch an app or script.
    private func openLocalFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        if MarkdownFile.isMarkdown(url) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - Script messages

/// Forwards script messages without retaining the receiver.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: PreviewController?

    init(_ target: PreviewController) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.didReceiveScroll(message)
    }
}
