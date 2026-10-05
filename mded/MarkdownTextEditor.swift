import AppKit

class TextEditorController: NSViewController, NSTextViewDelegate {
    private var textView: NSTextView!
    private var scrollView: NSScrollView!
    var onTextChange: ((String) -> Void)?
    var onScrollChange: ((ScrollPosition) -> Void)?
    private var isSettingText = false
    private var isSyncingScroll = false
    private var hasLoadedText = false
    private var appliedEvening: Bool?
    private var zoom = 1.0
    private var highlighter: MarkdownSyntaxHighlighter!
    // UTF-16 offset where each source line starts; rebuilt lazily after edits.
    private var cachedLineStarts: [Int]?

    private static let baseFontSize: CGFloat = 13

    override func loadView() {
        // Built on TextKit 1 deliberately. NSTextView.scrollableTextView() returns
        // a TextKit 2 view on macOS 13+, and TextKit 2 leaves blank regions in long
        // documents after edits. (Merely reading `layoutManager` on a TextKit 2 view
        // also silently falls back to TextKit 1; asking for it up front is explicit.)
        textView = NSTextView(usingTextLayoutManager: false)
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let contentSize = scrollView.contentSize
        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        // Contiguous layout (the TextKit 1 default) keeps line positions exact,
        // which the line-based scroll sync depends on.
        textView.layoutManager?.allowsNonContiguousLayout = false
        scrollView.documentView = textView

        textView.font = NSFont.monospacedSystemFont(ofSize: Self.baseFontSize * zoom, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isEditable = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.delegate = self
        highlighter = MarkdownSyntaxHighlighter(textView: textView)

        self.view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        guard !isSyncingScroll, let position = scrollPosition else { return }
        onScrollChange?(position)
    }

    // MARK: - Scroll position as source lines

    private var lineStarts: [Int] {
        if let cached = cachedLineStarts { return cached }
        var starts = [0]
        for (offset, unit) in textView.string.utf16.enumerated() where unit == 0x0A {
            starts.append(offset + 1)
        }
        cachedLineStarts = starts
        return starts
    }

    /// The source line (0-based, fractional) at the top of the visible area.
    var scrollPosition: ScrollPosition? {
        guard isViewLoaded, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
        let visible = scrollView.contentView.bounds
        let height = textView.frame.height
        let atEnd = height - visible.height > 1 && visible.maxY >= height - 1
        let y = max(0, visible.minY - textView.textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: y), in: container)
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        let starts = lineStarts
        let line = Self.lastIndex(in: starts, notAbove: character)
        let rect = lineRect(line, starts: starts, layoutManager: layoutManager, container: container)
        let fraction = rect.height > 0 ? min(max((y - rect.minY) / rect.height, 0), 1) : 0
        return ScrollPosition(line: Double(line) + Double(fraction), atEnd: atEnd)
    }

    /// Scrolls so `position` is at the top, without echoing back to onScrollChange.
    func scroll(to position: ScrollPosition) {
        guard isViewLoaded, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let maxY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        var target = maxY
        if !position.atEnd {
            let starts = lineStarts
            let line = min(max(0, Int(position.line)), starts.count - 1)
            let rect = lineRect(line, starts: starts, layoutManager: layoutManager, container: container)
            target = rect.minY + CGFloat(position.line - Double(line)) * rect.height + textView.textContainerOrigin.y
        }
        isSyncingScroll = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, target), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        DispatchQueue.main.async { [weak self] in
            self?.isSyncingScroll = false
        }
    }

    /// Rect (in text-container coordinates) of a whole source line, wrapped or not.
    private func lineRect(_ line: Int, starts: [Int], layoutManager: NSLayoutManager, container: NSTextContainer) -> NSRect {
        let length = (textView.string as NSString).length
        let start = starts[line]
        let end = line + 1 < starts.count ? starts[line + 1] : length
        guard end > start else { return layoutManager.extraLineFragmentRect }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: start, length: end - start),
                                              actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
    }

    private static func lastIndex(in sorted: [Int], notAbove value: Int) -> Int {
        var low = 0, high = sorted.count - 1, found = 0
        while low <= high {
            let mid = (low + high) / 2
            if sorted[mid] <= value { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }

    var currentText: String {
        isViewLoaded ? textView.string : ""
    }

    /// Replaces the whole text from outside the editor: the initial load, a
    /// revert, or a reload after the file changed on disk.
    func setText(_ text: String) {
        guard isViewLoaded, textView.string != text else { return }
        isSettingText = true
        defer { isSettingText = false }

        let isReplacement = hasLoadedText
        hasLoadedText = true
        let selection = textView.selectedRange()
        let scrollOrigin = scrollView.contentView.bounds.origin

        textView.string = text
        cachedLineStarts = nil
        highlighter.highlightNow()

        if isReplacement {
            // Undo entries hold ranges into the old text; replaying them against
            // the new text would corrupt it.
            textView.undoManager?.removeAllActions()
            let length = (text as NSString).length
            let location = min(selection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
            scrollView.contentView.scroll(to: scrollOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    /// Apply theme colors to the text view. Evening uses our palette; everything
    /// else uses system colors that follow the app's effective appearance.
    func applyAppearance(_ appearance: AppearancePreference) {
        // Setting textColor re-attributes the whole text storage, so only do it
        // when the theme actually changes.
        guard isViewLoaded, appliedEvening != appearance.isEvening else { return }
        appliedEvening = appearance.isEvening
        if appearance.isEvening {
            textView.backgroundColor = EveningPalette.background
            textView.textColor = EveningPalette.text
            textView.insertionPointColor = EveningPalette.text
        } else {
            textView.backgroundColor = .textBackgroundColor
            textView.textColor = .textColor
            textView.insertionPointColor = .textColor
        }
    }

    func setZoom(_ zoom: Double) {
        guard zoom != self.zoom else { return }
        self.zoom = zoom
        guard isViewLoaded else { return }
        let position = scrollPosition
        textView.font = NSFont.monospacedSystemFont(ofSize: Self.baseFontSize * zoom, weight: .regular)
        if let position { scroll(to: position) }
    }

    func setSyntaxColouring(_ on: Bool) {
        highlighter?.isEnabled = on
    }

    // MARK: - Focus and find

    var containsFirstResponder: Bool {
        guard isViewLoaded else { return false }
        return view.window?.firstResponder === textView
    }

    func focus() {
        view.window?.makeFirstResponder(textView)
    }

    /// Forwards a Find menu action (its tag is the NSTextFinder.Action) to the text view.
    func performFind(_ sender: Any?) {
        textView.performTextFinderAction(sender)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        cachedLineStarts = nil
        highlighter.textDidChange()
        guard !isSettingText else { return }
        onTextChange?(textView.string)
    }

    /// Return continues lists and quotes; Tab and Shift-Tab indent list items.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return false }
        let text = storage.string as NSString
        let selection = textView.selectedRange()
        let edit: MarkdownEditing.Edit?
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            edit = MarkdownEditing.newline(in: text, selection: selection)
        case #selector(NSResponder.insertTab(_:)):
            edit = MarkdownEditing.indent(in: text, selection: selection, outdent: false)
        case #selector(NSResponder.insertBacktab(_:)):
            edit = MarkdownEditing.indent(in: text, selection: selection, outdent: true)
        default:
            return false
        }
        guard let edit else { return false }
        // Through shouldChangeText/didChangeText so it's undoable like typing.
        textView.breakUndoCoalescing()
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return true }
        storage.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
        return true
    }
}
