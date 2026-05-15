import AppKit

class SplitEditorController: NSSplitViewController {
    private(set) var textEditor: TextEditorController!
    private(set) var preview: PreviewController!
    var onTextChange: ((String) -> Void)?
    var fileURL: URL? {
        didSet {
            let newBase = fileURL?.deletingLastPathComponent()
            guard newBase != preview?.baseURL else { return }
            preview?.baseURL = newBase
            preview?.reloadIfBaseURLChanged()
        }
    }

    // Appearance applied before viewDidLoad gets stashed here and replayed.
    private var pendingAppearance: AppearancePreference?

    // Guard against editor↔preview scroll feedback loops. Set when either side
    // initiates a sync; cleared on the next runloop turn.
    private var isSyncingScroll = false

    override func viewDidLoad() {
        super.viewDidLoad()

        textEditor = TextEditorController()
        preview = PreviewController()
        preview.baseURL = fileURL?.deletingLastPathComponent()

        textEditor.onTextChange = { [weak self] text in
            self?.onTextChange?(text)
            self?.preview.renderMarkdown(text)
        }
        textEditor.onScrollChange = { [weak self] fraction in
            guard let self = self, !self.isSyncingScroll else { return }
            self.isSyncingScroll = true
            self.preview.syncScroll(fraction: fraction)
            DispatchQueue.main.async { self.isSyncingScroll = false }
        }
        preview.onScrollChange = { [weak self] fraction in
            guard let self = self, !self.isSyncingScroll else { return }
            self.isSyncingScroll = true
            self.textEditor.syncScroll(fraction: fraction)
            DispatchQueue.main.async { self.isSyncingScroll = false }
        }

        let editorItem = NSSplitViewItem(viewController: textEditor)
        editorItem.minimumThickness = 200
        editorItem.holdingPriority = .defaultLow + 1

        let previewItem = NSSplitViewItem(viewController: preview)
        previewItem.minimumThickness = 200

        addSplitViewItem(editorItem)
        addSplitViewItem(previewItem)

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        if let pending = pendingAppearance {
            applyAppearance(pending)
            pendingAppearance = nil
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        splitView.setPosition(550, ofDividerAt: 0)
    }

    func updateContent(_ text: String) {
        guard isViewLoaded else { return }
        textEditor.setText(text)
        preview.renderMarkdown(text)
    }

    func applyAppearance(_ appearance: AppearancePreference) {
        guard isViewLoaded else {
            pendingAppearance = appearance
            return
        }
        view.appearance = appearance.nsAppearance
        textEditor.applyAppearance(appearance)
        preview.applyAppearance(appearance)
    }
}
