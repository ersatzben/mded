import AppKit
import SwiftUI

/// Sends menu actions to the focused window's SplitEditorController.
enum EditorActions {
    @MainActor
    static func send(_ action: Selector, tag: Int = 0) {
        let sender = NSMenuItem()
        sender.tag = tag
        // The controller is in the responder chain whenever one of its panes has
        // focus. If nothing in the window does, find it directly.
        if NSApp.sendAction(action, to: nil, from: sender) { return }
        if let controller = keyWindowController() {
            NSApp.sendAction(action, to: controller, from: sender)
        }
    }

    @MainActor
    private static func keyWindowController() -> SplitEditorController? {
        func search(_ view: NSView) -> SplitEditorController? {
            if let controller = view.nextResponder as? SplitEditorController { return controller }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        guard let content = NSApp.keyWindow?.contentView else { return nil }
        return search(content)
    }
}

/// View menu: layout, zoom, status bar.
///
/// Items stay enabled rather than tracking state with `.disabled`: SwiftUI
/// doesn't refresh a command's enabled state before handling its shortcut, so a
/// stale "disabled" would swallow the key press.
struct ViewCommands: Commands {
    @ObservedObject private var keyWindow = KeyWindowState.shared
    @AppStorage(DefaultsKey.zoom) private var zoom = 1.0
    @AppStorage(DefaultsKey.showStatusBar) private var showStatusBar = true

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Section {
                ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { index, mode in
                    Toggle(mode.label, isOn: Binding(
                        get: { keyWindow.viewMode == mode },
                        set: { _ in EditorActions.send(#selector(SplitEditorController.showViewMode(_:)), tag: index) }
                    ))
                    .keyboardShortcut(mode.shortcut, modifiers: .command)
                }
            }
            Section {
                Button("Actual Size") { zoom = 1 }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Zoom In") { zoom = Zoom.larger(than: zoom) ?? zoom }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { zoom = Zoom.smaller(than: zoom) ?? zoom }
                    .keyboardShortcut("-", modifiers: .command)
            }
            Section {
                Toggle("Show Status Bar", isOn: $showStatusBar)
            }
        }
    }
}

/// File menu: export and print the rendered document.
struct ExportCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export as HTML…") {
                EditorActions.send(#selector(SplitEditorController.exportHTML(_:)))
            }
            Button("Export as PDF…") {
                EditorActions.send(#selector(SplitEditorController.exportPDF(_:)))
            }
        }
        CommandGroup(replacing: .printItem) {
            Button("Page Setup…") { NSApp.runPageLayout(nil) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Print…") {
                EditorActions.send(#selector(SplitEditorController.printMarkdown(_:)))
            }
            .keyboardShortcut("p", modifiers: .command)
        }
    }
}
