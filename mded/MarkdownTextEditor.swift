import AppKit

class TextEditorController: NSViewController, NSTextViewDelegate {
    private var textView: NSTextView!
    private var scrollView: NSScrollView!
    var onTextChange: ((String) -> Void)?
    var onScrollChange: ((Double) -> Void)?
    private var isSettingText = false
    private var isSyncingScroll = false

    override func loadView() {
        scrollView = NSTextView.scrollableTextView()
        textView = (scrollView.documentView as! NSTextView)

        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isEditable = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.delegate = self

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
        guard !isSyncingScroll else { return }
        let contentView = scrollView.contentView
        let docHeight = scrollView.documentView?.frame.height ?? 0
        let visibleHeight = contentView.bounds.height
        let maxScroll = docHeight - visibleHeight
        guard maxScroll > 0 else { return }
        let fraction = contentView.bounds.origin.y / maxScroll
        onScrollChange?(min(max(fraction, 0), 1))
    }

    var currentText: String {
        isViewLoaded ? textView.string : ""
    }

    func setText(_ text: String) {
        guard isViewLoaded, textView.string != text else { return }
        isSettingText = true
        // External updates shouldn't pollute the undo stack — they aren't user edits.
        textView.undoManager?.disableUndoRegistration()
        textView.string = text
        textView.undoManager?.enableUndoRegistration()
        isSettingText = false
    }

    /// Apply theme colors to the text view. Evening uses our palette; everything
    /// else falls back to system text colors that adapt to the effective appearance.
    func applyAppearance(_ appearance: AppearancePreference) {
        guard isViewLoaded else { return }
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

    /// Programmatically scroll to a fraction without firing onScrollChange.
    func syncScroll(fraction: Double) {
        guard isViewLoaded else { return }
        let docHeight = scrollView.documentView?.frame.height ?? 0
        let visibleHeight = scrollView.contentView.bounds.height
        let maxScroll = docHeight - visibleHeight
        guard maxScroll > 0 else { return }
        let targetY = max(0, min(maxScroll, fraction * maxScroll))
        isSyncingScroll = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        DispatchQueue.main.async { [weak self] in
            self?.isSyncingScroll = false
        }
    }

    func textDidChange(_ notification: Notification) {
        guard !isSettingText else { return }
        onTextChange?(textView.string)
    }
}
