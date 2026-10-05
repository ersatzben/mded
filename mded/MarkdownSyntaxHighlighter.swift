import AppKit

/// Colours Markdown syntax in the editor with layout-manager temporary
/// attributes, which aren't part of the text: they don't touch the undo stack,
/// mark the document edited, or invalidate layout. Re-runs shortly after typing
/// pauses.
@MainActor
final class MarkdownSyntaxHighlighter {
    private weak var textView: NSTextView?
    private var pending: Task<Void, Never>?

    /// Beyond this, scanning on every pause in typing costs more than it's worth.
    private static let maximumLength = 2_000_000
    private static let delay: TimeInterval = 0.15

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? highlightNow() : clear()
        }
    }

    init(textView: NSTextView) {
        self.textView = textView
    }

    func textDidChange() {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.delay))
            guard !Task.isCancelled else { return }
            self?.highlightNow()
        }
    }

    func highlightNow() {
        pending?.cancel()
        guard isEnabled, let textView, let layoutManager = textView.layoutManager,
              let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: text.length))
        guard text.length <= Self.maximumLength else { return }
        for span in MarkdownSyntax.spans(in: text) {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: Self.color(for: span.kind), forCharacterRange: span.range)
        }
    }

    private func clear() {
        pending?.cancel()
        guard let textView, let layoutManager = textView.layoutManager, let storage = textView.textStorage else { return }
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: storage.length))
    }

    // System colours adapt to light, dark and Evening.
    private static func color(for kind: MarkdownSyntax.Kind) -> NSColor {
        switch kind {
        case .heading: return .systemBlue
        case .code: return .systemPink
        case .quote: return .secondaryLabelColor
        case .marker: return .systemOrange
        case .emphasis: return .systemPurple
        case .link: return .linkColor
        case .url: return .secondaryLabelColor
        case .html: return .systemTeal
        }
    }
}
