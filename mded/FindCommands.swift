import SwiftUI
import AppKit

/// Adds Find, Find & Replace, Find Next/Previous, and Use Selection for Find
/// to the Edit menu. Each item goes to the focused window's
/// SplitEditorController, which sends it to the editor's NSTextFinder or to the
/// preview's find bar, depending on which pane has focus. The sender's `tag`
/// carries the NSTextFinder.Action.
struct FindCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Section {
                Button("Find…") { perform(.showFindInterface) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find and Replace…") { perform(.showReplaceInterface) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Find Next") { perform(.nextMatch) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { perform(.previousMatch) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Use Selection for Find") { perform(.setSearchString) }
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
    }

    private func perform(_ action: NSTextFinder.Action) {
        EditorActions.send(#selector(SplitEditorController.performFindAction(_:)), tag: action.rawValue)
    }
}
