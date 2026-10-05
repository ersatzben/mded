import AppKit
import os

class SplitEditorController: NSSplitViewController {
    private(set) var textEditor: TextEditorController!
    private(set) var preview: PreviewController!
    private var editorItem: NSSplitViewItem!
    private var previewItem: NSSplitViewItem!
    var onTextChange: ((String) -> Void)?
    /// Called when the user collapses a pane by dragging the divider.
    var onViewModeChange: ((ViewMode) -> Void)?
    var fileURL: URL? {
        didSet {
            guard fileURL != oldValue else { return }
            watchFile()
            let newBase = fileURL?.deletingLastPathComponent()
            guard newBase != preview?.baseURL else { return }
            preview?.baseURL = newBase
            preview?.reloadIfBaseURLChanged()
        }
    }

    // Settings that arrive before viewDidLoad are stashed and replayed.
    private var pendingText: String?
    private var pendingAppearance: AppearancePreference?
    private var appliedAppearance: AppearancePreference?
    private var pendingViewMode: ViewMode?
    private var isApplyingViewMode = false
    // The editor's share of the width while both panes show. Restored when
    // returning to split view: left to itself, the split view gives the
    // reappearing pane only what the other (higher holding priority) pane
    // doesn't keep, which pushes the divider far to one side.
    private var editorFraction: CGFloat?
    private var zoom = 1.0
    private var syntaxColouring = true
    private var literalUnderscores = true

    // The exact String last sent to (or received from) the editor. SwiftUI hands
    // the same value straight back on every keystroke; comparing against it hits
    // String's identical-storage fast path instead of a full comparison.
    private var lastSyncedText: String?

    // Guard against editor↔preview scroll feedback loops. Set when either side
    // initiates a sync; cleared on the next runloop turn.
    private var isSyncingScroll = false

    private static let splitAutosaveName = "mded.editorPreviewSplit"
    private static let defaultEditorWidth: CGFloat = 550
    private var didPositionDivider = false

    private var fileMonitor: FileChangeMonitor?
    private var activeExporter: DocumentExporter?
    private static let log = Logger(subsystem: "com.mded.app", category: "document")

    override func viewDidLoad() {
        super.viewDidLoad()

        textEditor = TextEditorController()
        preview = PreviewController()
        preview.baseURL = fileURL?.deletingLastPathComponent()
        textEditor.setZoom(zoom)
        textEditor.setSyntaxColouring(syntaxColouring)
        preview.setZoom(zoom)
        preview.setLiteralUnderscores(literalUnderscores)

        textEditor.onTextChange = { [weak self] text in
            guard let self = self else { return }
            self.lastSyncedText = text
            self.onTextChange?(text)
            self.preview.renderMarkdown(text)
        }
        textEditor.onScrollChange = { [weak self] position in
            guard let self = self, !self.isSyncingScroll, self.viewMode == .split else { return }
            self.isSyncingScroll = true
            self.preview.syncScroll(to: position)
            DispatchQueue.main.async { self.isSyncingScroll = false }
        }
        preview.onScrollChange = { [weak self] position in
            guard let self = self, !self.isSyncingScroll, self.viewMode == .split else { return }
            self.isSyncingScroll = true
            self.textEditor.scroll(to: position)
            DispatchQueue.main.async { self.isSyncingScroll = false }
        }
        // After a reload (e.g. Save As into another folder) the preview starts at
        // the top; bring it back in line with the editor.
        preview.onPageReady = { [weak self] in
            self?.syncPreviewToEditor()
        }

        editorItem = NSSplitViewItem(viewController: textEditor)
        editorItem.minimumThickness = 200
        editorItem.holdingPriority = .defaultLow + 1
        editorItem.canCollapse = true

        previewItem = NSSplitViewItem(viewController: preview)
        previewItem.minimumThickness = 200
        previewItem.canCollapse = true

        addSplitViewItem(editorItem)
        addSplitViewItem(previewItem)

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = Self.splitAutosaveName

        if let text = pendingText {
            pendingText = nil
            updateContent(text)
        }
        if let pending = pendingAppearance {
            pendingAppearance = nil
            applyAppearance(pending)
        }
        if let mode = pendingViewMode {
            pendingViewMode = nil
            setViewMode(mode)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // viewDidAppear runs again after un-minimising and when SwiftUI re-hosts
        // the view; only position the divider the first time, and only if the
        // split view hasn't restored a user-chosen position.
        guard !didPositionDivider else { return }
        didPositionDivider = true
        let savedKey = "NSSplitView Subview Frames \(Self.splitAutosaveName)"
        if UserDefaults.standard.object(forKey: savedKey) == nil {
            splitView.setPosition(Self.defaultEditorWidth, ofDividerAt: 0)
        }
        watchFile()
        if viewMode == .previewOnly { preview.focus() } else { textEditor.focus() }
        if let window = view.window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey(_:)),
                                                   name: NSWindow.didBecomeKeyNotification, object: window)
        }
        publishViewMode()
    }

    func updateContent(_ text: String) {
        guard isViewLoaded else {
            pendingText = text
            return
        }
        // Echo of the editor's own change: nothing to do.
        if let last = lastSyncedText, text == last { return }
        lastSyncedText = text
        textEditor.setText(text)
        preview.renderMarkdown(text)
    }

    func applyAppearance(_ appearance: AppearancePreference) {
        guard isViewLoaded else {
            pendingAppearance = appearance
            return
        }
        guard appearance != appliedAppearance else { return }
        appliedAppearance = appearance
        textEditor.applyAppearance(appearance)
        preview.applyAppearance(appearance)
    }

    func setZoom(_ zoom: Double) {
        guard zoom != self.zoom else { return }
        self.zoom = zoom
        guard isViewLoaded else { return }
        textEditor.setZoom(zoom)
        preview.setZoom(zoom)
    }

    func setSyntaxColouring(_ on: Bool) {
        guard on != syntaxColouring else { return }
        syntaxColouring = on
        if isViewLoaded { textEditor.setSyntaxColouring(on) }
    }

    func setLiteralUnderscores(_ on: Bool) {
        guard on != literalUnderscores else { return }
        literalUnderscores = on
        if isViewLoaded { preview.setLiteralUnderscores(on) }
    }

    // MARK: - View modes

    /// What's actually showing, which can differ from the last requested mode if
    /// the user dragged a pane closed.
    var viewMode: ViewMode {
        guard isViewLoaded else { return pendingViewMode ?? .split }
        if editorItem.isCollapsed { return .previewOnly }
        if previewItem.isCollapsed { return .editorOnly }
        return .split
    }

    func setViewMode(_ mode: ViewMode) {
        guard isViewLoaded else {
            pendingViewMode = mode
            return
        }
        guard mode != viewMode else { return }
        let editorHadFocus = textEditor.containsFirstResponder
        let previewHadFocus = preview.containsFirstResponder

        let wasSplit = viewMode == .split
        if wasSplit { recordEditorFraction() }

        isApplyingViewMode = true
        editorItem.isCollapsed = mode == .previewOnly
        previewItem.isCollapsed = mode == .editorOnly
        if mode == .split { restoreEditorFraction() }
        isApplyingViewMode = false
        preview.isActive = mode != .editorOnly
        if mode == .split {
            // The split view can finish laying out the reappearing pane on the
            // next pass; apply the position again once it has.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.viewMode == .split else { return }
                self.isApplyingViewMode = true
                self.restoreEditorFraction()
                self.isApplyingViewMode = false
            }
        }

        switch mode {
        case .previewOnly where editorHadFocus: preview.focus()
        case .editorOnly where previewHadFocus: textEditor.focus()
        case .split: syncPreviewToEditor()
        default: break
        }
        publishViewMode()
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard !isApplyingViewMode, isViewLoaded, editorItem != nil, previewItem != nil else { return }
        if viewMode == .split { recordEditorFraction() }
        preview.isActive = !previewItem.isCollapsed
        onViewModeChange?(viewMode)
        publishViewMode()
    }

    private var splitWidth: CGFloat {
        splitView.bounds.width - splitView.dividerThickness
    }

    private func recordEditorFraction() {
        guard splitWidth > 0 else { return }
        editorFraction = textEditor.view.frame.width / splitWidth
    }

    private func restoreEditorFraction() {
        splitView.layoutSubtreeIfNeeded()
        guard splitWidth > 0 else { return }
        let fraction = editorFraction ?? Self.defaultEditorWidth / splitWidth
        splitView.setPosition((splitWidth * fraction).rounded(), ofDividerAt: 0)
    }

    /// From the View menu; the sender's tag indexes ViewMode.allCases.
    @objc func showViewMode(_ sender: NSMenuItem) {
        guard ViewMode.allCases.indices.contains(sender.tag) else { return }
        let mode = ViewMode.allCases[sender.tag]
        setViewMode(mode)
        onViewModeChange?(mode)
        publishViewMode()
    }

    /// Lets the View menu show this window's mode while it's the key window.
    private func publishViewMode() {
        guard isViewLoaded, view.window?.isKeyWindow == true else { return }
        KeyWindowState.shared.viewMode = viewMode
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        publishViewMode()
    }

    private func syncPreviewToEditor() {
        guard viewMode == .split, let position = textEditor.scrollPosition else { return }
        preview.syncScroll(to: position)
    }

    // MARK: - Find

    /// From the Find menu (the sender's tag is the NSTextFinder.Action). Goes to
    /// the preview's find bar when the preview has focus or is all that's
    /// showing, otherwise to the editor's.
    @objc func performFindAction(_ sender: NSMenuItem) {
        guard let action = NSTextFinder.Action(rawValue: sender.tag) else { return }
        if viewMode == .previewOnly || (viewMode == .split && preview.containsFirstResponder) {
            preview.performFind(action)
        } else {
            if !textEditor.containsFirstResponder { textEditor.focus() }
            textEditor.performFind(sender)
        }
    }

    // MARK: - Export and print

    @objc func exportHTML(_ sender: Any?) {
        export(.html)
    }

    @objc func exportPDF(_ sender: Any?) {
        export(.pdf)
    }

    @objc func printMarkdown(_ sender: Any?) {
        export(.print)
    }

    private enum Output { case html, pdf, print }

    private func export(_ output: Output) {
        guard let window = view.window, activeExporter == nil else {
            NSSound.beep()
            return
        }
        let markdown = textEditor.currentText
        let title = fileURL?.deletingPathExtension().lastPathComponent ?? document?.displayName ?? "Untitled"
        let directory = fileURL?.deletingLastPathComponent()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var destination: URL?
                if output != .print {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [output == .pdf ? .pdf : .html]
                    panel.nameFieldStringValue = title
                    panel.directoryURL = directory
                    panel.canCreateDirectories = true
                    guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
                    destination = url
                }
                let exporter = try await DocumentExporter.prepare(markdown: markdown, directory: directory,
                                                                  literalUnderscores: literalUnderscores)
                switch output {
                case .html:
                    let html = try await exporter.standaloneHTML(title: title)
                    try html.write(to: destination!, atomically: true, encoding: .utf8)
                case .pdf, .print:
                    activeExporter = exporter // keep it alive until printing finishes
                    exporter.print(attachedTo: window, savingPDFTo: destination) { [weak self] _ in
                        self?.activeExporter = nil
                    }
                }
            } catch {
                activeExporter = nil
                window.presentError(error)
            }
        }
    }

    // MARK: - External changes

    private var document: NSDocument? {
        guard let window = view.window else { return nil }
        return NSDocumentController.shared.document(for: window)
    }

    private func watchFile() {
        guard isViewLoaded, view.window != nil, let url = fileURL else {
            fileMonitor = nil
            return
        }
        if let document, type(of: document).autosavesInPlace {
            // DisableAutosave.m finds SwiftUI's private document classes at launch.
            Self.log.fault("autosave-in-place hook no longer matches \(String(describing: type(of: document)), privacy: .public)")
        }
        fileMonitor = FileChangeMonitor(url: url) { [weak self] in
            self?.fileDidChangeOnDisk()
        }
    }

    /// Reloads the document when another app changed the file and there are no
    /// unsaved edits here. With edits pending, AppKit's save-time conflict
    /// check takes over.
    private func fileDidChangeOnDisk() {
        guard let document, !document.isDocumentEdited,
              let url = document.fileURL, let type = document.fileType,
              let known = document.fileModificationDate,
              let onDisk = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              onDisk > known else { return }
        do {
            try document.revert(toContentsOf: url, ofType: type)
        } catch {
            Self.log.error("reload after external change failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
