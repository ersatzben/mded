import Foundation

/// A lightweight Markdown scanner for colouring the editor. It doesn't parse
/// Markdown properly (marked.js does that for the preview); it finds the
/// constructs worth colouring, quickly, with code blocks taking precedence.
enum MarkdownSyntax {
    enum Kind: Equatable, Sendable {
        case heading, code, quote, marker, emphasis, link, url, html
    }

    struct Span: Equatable, Sendable {
        var range: NSRange
        var kind: Kind
    }

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let fence = regex(#"^ {0,3}(`{3,}|~{3,})"#)
    private static let heading = regex(#"^ {0,3}#{1,6}(?:[ \t].*)?$"#)
    private static let quote = regex(#"^ {0,3}>.*$"#)
    private static let rule = regex(#"^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$"#)
    private static let listMarker = regex(#"^[ \t]*(?:[-*+]|\d{1,9}[.)])(?=[ \t])(?:[ \t]+\[[ xX]\])?"#)
    private static let codeSpan = regex(#"(`+)(?!`).+?(?<!`)\1(?!`)"#, [])
    private static let strong = regex(#"(\*\*|__)(?=\S).+?(?<=\S)\1"#, [])
    private static let emphasis = regex(#"(?<![*\w])\*(?=[^\s*]).+?(?<=[^\s*])\*(?![*\w])"#, [])
    private static let strike = regex(#"~~(?=\S).+?(?<=\S)~~"#, [])
    private static let link = regex(#"(!?\[[^\]\n]*\])(\([^)\n]*\)|\[[^\]\n]*\])"#, [])
    // Bare URLs not already inside a link's (…), an <…> autolink or an attribute.
    private static let autolink = regex(#"<(?:https?|mailto|ftp):[^>\s]+>|(?<![(<"'=])\bhttps?://[^\s<>()]+"#, [])
    private static let html = regex(#"<!--[\s\S]*?-->|</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?/?>"#, [])

    /// Spans to colour in `text`. Later spans win where they overlap.
    static func spans(in text: NSString) -> [Span] {
        let string = text as String
        let all = NSRange(location: 0, length: text.length)
        var spans: [Span] = []

        // Fenced code blocks first; nothing inside them is Markdown.
        var codeBlocks: [NSRange] = []
        var openFence: (marker: String, start: Int)?
        var location = 0
        while location < text.length {
            var lineEnd = 0, contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let lineRange = NSRange(location: location, length: contentsEnd - location)
            if let m = fence.firstMatch(in: string, range: lineRange) {
                let marker = text.substring(with: m.range(at: 1))
                if let open = openFence {
                    if marker.first == open.marker.first && marker.count >= open.marker.count {
                        codeBlocks.append(NSRange(location: open.start, length: contentsEnd - open.start))
                        openFence = nil
                    }
                } else {
                    openFence = (marker, location)
                }
            }
            location = lineEnd
        }
        if let open = openFence {
            codeBlocks.append(NSRange(location: open.start, length: text.length - open.start))
        }

        func outsideCode(_ range: NSRange) -> Bool {
            !codeBlocks.contains { NSIntersectionRange($0, range).length > 0 }
        }
        func add(_ expression: NSRegularExpression, _ kind: Kind, group: Int = 0) {
            expression.enumerateMatches(in: string, range: all) { match, _, _ in
                guard let match else { return }
                let range = match.range(at: group)
                if range.location != NSNotFound, outsideCode(range) {
                    spans.append(Span(range: range, kind: kind))
                }
            }
        }

        add(quote, .quote)
        add(heading, .heading)
        add(rule, .marker)
        add(listMarker, .marker)
        add(html, .html)
        add(strong, .emphasis)
        add(emphasis, .emphasis)
        add(strike, .emphasis)
        add(link, .link, group: 1)
        add(link, .url, group: 2)
        add(autolink, .url)
        add(codeSpan, .code)
        spans += codeBlocks.map { Span(range: $0, kind: .code) }
        return spans
    }
}
