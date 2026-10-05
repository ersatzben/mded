import AppKit

/// A find bar for the preview pane: search field, previous/next, match status
/// and Done. Return finds the next match, Shift-Return the previous one, and
/// Escape closes the bar.
final class PreviewFindBar: NSView, NSSearchFieldDelegate {
    /// Called to search: the text, whether to go backwards, and whether to start
    /// again from the top (the search text changed).
    var onFind: ((_ text: String, _ backwards: Bool, _ restart: Bool) -> Void)?
    var onClose: (() -> Void)?

    let searchField = NSSearchField()
    private let navigation = NSSegmentedControl()
    private let status = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)

        searchField.placeholderString = "Find in Preview"
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)

        navigation.segmentCount = 2
        navigation.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous"), forSegment: 0)
        navigation.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next"), forSegment: 1)
        navigation.trackingMode = .momentary
        navigation.segmentStyle = .separated
        navigation.target = self
        navigation.action = #selector(navigate)

        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let done = NSButton(title: "Done", target: self, action: #selector(close))
        done.bezelStyle = .rounded
        done.controlSize = .small
        searchField.controlSize = .small
        navigation.controlSize = .small

        let stack = NSStackView(views: [searchField, navigation, status, NSView(), done])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        addSubview(separator)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    var searchText: String {
        get { searchField.stringValue }
        set { searchField.stringValue = newValue }
    }

    func showResult(found: Bool) {
        status.stringValue = searchText.isEmpty || found ? "" : "Not found"
    }

    func focus() {
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    @objc private func searchChanged() {
        onFind?(searchText, false, true)
    }

    @objc private func navigate() {
        onFind?(searchText, navigation.selectedSegment == 0, false)
    }

    @objc private func close() {
        onClose?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            onFind?(searchText, backwards, false)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }
}
