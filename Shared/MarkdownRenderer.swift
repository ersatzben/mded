import Foundation

enum MarkdownRenderer {
    /// Base HTML shell with CSS/JS inlined but no content.
    /// Used by the editor preview pane — content is injected via JS.
    static func baseHTML(in bundle: Bundle) -> String {
        let cssGitHub = loadResource("github-markdown", ext: "css", bundle: bundle)
        let cssHighlight = loadResource("github-highlight", ext: "css", bundle: bundle)
        let cssHighlightDark = loadResource("github-highlight-dark", ext: "css", bundle: bundle)
        let jsMarked = loadResource("marked.min", ext: "js", bundle: bundle)
        let jsHighlight = loadResource("highlight.min", ext: "js", bundle: bundle)

        return buildHTML(cssGitHub: cssGitHub, cssHighlight: cssHighlight,
                         cssHighlightDark: cssHighlightDark,
                         jsMarked: jsMarked, jsHighlight: jsHighlight,
                         inlineScript: "")
    }

    /// Self-contained HTML with markdown pre-rendered.
    /// Used by the Quick Look extension.
    static func htmlForQuickLook(markdown: String, in bundle: Bundle) -> String {
        let cssGitHub = loadResource("github-markdown", ext: "css", bundle: bundle)
        let cssHighlight = loadResource("github-highlight", ext: "css", bundle: bundle)
        let cssHighlightDark = loadResource("github-highlight-dark", ext: "css", bundle: bundle)
        let jsMarked = loadResource("marked.min", ext: "js", bundle: bundle)
        let jsHighlight = loadResource("highlight.min", ext: "js", bundle: bundle)

        let jsonMarkdown = jsonEncode(markdown)
        let script = "render(\(jsonMarkdown));"

        return buildHTML(cssGitHub: cssGitHub, cssHighlight: cssHighlight,
                         cssHighlightDark: cssHighlightDark,
                         jsMarked: jsMarked, jsHighlight: jsHighlight,
                         inlineScript: script)
    }

    private static func buildHTML(cssGitHub: String, cssHighlight: String,
                                  cssHighlightDark: String,
                                  jsMarked: String, jsHighlight: String,
                                  inlineScript: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="color-scheme" content="light dark">
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
                /* Evening mode — applied via JS class, overrides media-query colors. */
                body.evening-mode { background-color: #f7f3df; }
                body.evening-mode .markdown-body {
                    --fgColor-default: #3B3836;
                    --bgColor-default: #f7f3df;
                }
                .markdown-body { max-width: 980px; margin: 0 auto; }
            </style>
        </head>
        <body>
            <article class="markdown-body" id="content"></article>
            <script>\(jsMarked)</script>
            <script>\(jsHighlight)</script>
            <script>
                // Treat _ as literal everywhere; only *…* and **…** mark emphasis.
                // Avoids spec-correct but unwanted formatting of identifiers like __init__.
                marked.use({
                    extensions: [{
                        name: 'literalUnderscore',
                        level: 'inline',
                        start: function(src) {
                            var idx = src.indexOf('_');
                            return idx === -1 ? undefined : idx;
                        },
                        tokenizer: function(src) {
                            var m = /^_+/.exec(src);
                            if (!m) return undefined;
                            return { type: 'text', raw: m[0], text: m[0] };
                        }
                    }]
                });
                function render(text) {
                    var content = document.getElementById('content');
                    content.innerHTML = marked.parse(text || '');
                    content.querySelectorAll('pre code').forEach(function(el) {
                        hljs.highlightElement(el);
                    });
                }
                function setEvening(on) {
                    document.body.classList.toggle('evening-mode', !!on);
                }
                \(inlineScript)
            </script>
        </body>
        </html>
        """
    }

    private static func loadResource(_ name: String, ext: String, bundle: Bundle) -> String {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return content
    }

    private static func jsonEncode(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }
}
