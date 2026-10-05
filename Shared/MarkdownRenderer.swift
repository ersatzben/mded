import Foundation
import WebKit

/// The preview page shared by the editor and the Quick Look extension.
///
/// The page HTML carries only CSS. marked.js, highlight.js and `renderer.js`
/// run as a user script in an isolated content world, and page JavaScript is
/// switched off: HTML embedded in a document still renders, but nothing in it
/// can execute. Markdown is handed over as a `callAsyncJavaScript` argument,
/// never spliced into script source.
enum MarkdownRenderer {
    /// The isolated world the renderer lives in. Every call into it must name it.
    @MainActor static var world: WKContentWorld { .defaultClient }

    /// Message name the renderer posts the preview's scroll fraction under.
    static let scrollMessageName = "previewScroll"

    @MainActor
    static func makeConfiguration(bundle: Bundle) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LocalFileSchemeHandler.scheme)
        let source = ["marked.min", "highlight.min", "renderer"]
            .map { loadResource($0, ext: "js", bundle: bundle) }
            .joined(separator: "\n;\n")
        config.userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world)
        )
        return config
    }

    /// Base URL for the page: relative paths in the markdown resolve in
    /// `directory`, served by LocalFileSchemeHandler. Nil for untitled documents.
    static func pageBaseURL(forDirectory directory: URL?) -> URL? {
        directory.flatMap(LocalFileSchemeHandler.baseURL(forDirectory:))
    }

    /// Static page with the stylesheets inlined. The preview renders into the
    /// empty content element; exports pass the rendered body and a title.
    static func pageHTML(bundle: Bundle, title: String? = nil, body: String = "") -> String {
        let cssGitHub = loadResource("github-markdown", ext: "css", bundle: bundle)
        let cssHighlight = loadResource("github-highlight", ext: "css", bundle: bundle)
        let cssHighlightDark = loadResource("github-highlight-dark", ext: "css", bundle: bundle)

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="color-scheme" content="light dark">
            \(title.map { "<title>\(escapeHTML($0))</title>" } ?? "")
            <style>\(cssGitHub)</style>
            <style media="(prefers-color-scheme: light)">\(cssHighlight)</style>
            <style media="(prefers-color-scheme: dark)">\(cssHighlightDark)</style>
            <style>
                body {
                    margin: 0;
                    padding: 16px 24px;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
                }
                @media (prefers-color-scheme: dark) {
                    body { background-color: #0d1117; }
                }
                @media (prefers-color-scheme: light) {
                    body { background-color: #ffffff; }
                }
                .markdown-body { max-width: 980px; margin: 0 auto; }
                /* github-markdown already pads and colours <pre>; drop highlight.js's
                   second box so code blocks don't get double padding. */
                .markdown-body pre code.hljs { padding: 0; background: transparent; }

                /* Evening: charcoal on cream. Applied via a class, so it overrides the
                   media-query palette; every colour the stylesheet uses is re-tinted. */
                body.evening-mode { background-color: #f7f3df; }
                body.evening-mode .markdown-body {
                    color-scheme: light;
                    --fgColor-default: #3b3836;
                    --fgColor-muted: #6e665c;
                    --fgColor-accent: #8a4b1f;
                    --bgColor-default: #f7f3df;
                    --bgColor-muted: #efe8cf;
                    --bgColor-neutral-muted: #8a7d5c26;
                    --bgColor-attention-muted: #f6e7b0;
                    --borderColor-default: #ddd3b4;
                    --borderColor-muted: #ddd3b4b3;
                    --borderColor-neutral-muted: #ddd3b4b3;
                    --borderColor-accent-emphasis: #8a4b1f;
                    --focus-outlineColor: #8a4b1f;
                }
                body.evening-mode .hljs { color: #3b3836; }
            </style>
        </head>
        <body>
            <article class="markdown-body" id="content">\(body)</article>
        </body>
        </html>
        """
    }

    /// Renders `markdown` into a page loaded from `pageHTML(bundle:)`.
    @MainActor
    static func render(_ markdown: String, in webView: WKWebView, completion: ((Error?) -> Void)? = nil) {
        call("render(markdown)", arguments: ["markdown": markdown], in: webView, completion: completion)
    }

    @MainActor
    static func setEvening(_ on: Bool, in webView: WKWebView) {
        call("setEvening(on)", arguments: ["on": on], in: webView)
    }

    /// Scrolls so source line `line` (fractional) is at the top, or to the end.
    @MainActor
    static func scroll(toLine line: Double, atEnd: Bool, in webView: WKWebView) {
        call("scrollToLine(line, atEnd)", arguments: ["line": line, "atEnd": atEnd], in: webView)
    }

    /// Renderer options, e.g. `["literalUnderscores": false]`. Takes effect on the next render.
    @MainActor
    static func setOptions(_ options: [String: Any], in webView: WKWebView) {
        call("mdedSetOptions(options)", arguments: ["options": options], in: webView)
    }

    @MainActor
    static func selectedText(in webView: WKWebView) async -> String {
        (try? await webView.callAsyncJavaScript("return selectedText()", arguments: [:], in: nil, contentWorld: world) as? String) ?? ""
    }

    @MainActor
    static func clearSelection(in webView: WKWebView) {
        call("clearSelection()", arguments: [:], in: webView)
    }

    /// Waits until every image has loaded (or failed) and layout has settled.
    @MainActor
    static func whenImagesLoaded(in webView: WKWebView) async {
        _ = try? await webView.callAsyncJavaScript("await whenImagesLoaded()", arguments: [:], in: nil, contentWorld: world)
    }

    /// The rendered body for a standalone HTML file: images inlined, scripts removed.
    @MainActor
    static func exportBodyHTML(in webView: WKWebView) async throws -> String {
        let result = try await webView.callAsyncJavaScript("return await exportBodyHTML()", arguments: [:],
                                                           in: nil, contentWorld: world)
        return result as? String ?? ""
    }

    @MainActor
    static func scroll(toAnchor id: String, in webView: WKWebView) {
        call("scrollToAnchor(id)", arguments: ["id": id], in: webView)
    }

    @MainActor
    private static func call(_ body: String, arguments: [String: Any], in webView: WKWebView,
                             completion: ((Error?) -> Void)? = nil) {
        webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: world) { result in
            if case .failure(let error) = result {
                completion?(error)
            } else {
                completion?(nil)
            }
        }
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func loadResource(_ name: String, ext: String, bundle: Bundle) -> String {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return content
    }
}
