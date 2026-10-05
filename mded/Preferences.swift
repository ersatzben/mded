import SwiftUI

/// UserDefaults keys for app-wide preferences (read with @AppStorage).
enum DefaultsKey {
    static let appearance = "appearance"
    static let zoom = "zoom"
    static let showStatusBar = "showStatusBar"
    static let literalUnderscores = "literalUnderscores"
    static let syntaxColouring = "syntaxColouring"
}

/// Which panes a window shows. Per window, restored with the window.
enum ViewMode: String, CaseIterable, Identifiable {
    case split
    case editorOnly
    case previewOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .split: return "Editor and Preview"
        case .editorOnly: return "Editor Only"
        case .previewOnly: return "Preview Only"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .split: return "1"
        case .editorOnly: return "2"
        case .previewOnly: return "3"
        }
    }
}

/// Zoom steps shared by both panes; 1 is actual size.
enum Zoom {
    static let steps: [Double] = [0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    static func larger(than zoom: Double) -> Double? { steps.first { $0 > zoom + 0.001 } }
    static func smaller(than zoom: Double) -> Double? { steps.last { $0 < zoom - 0.001 } }
}

/// A scroll position as a source line (fractional: 12.5 is halfway through
/// line 12's block), so the editor and preview line up on content.
struct ScrollPosition: Equatable {
    var line: Double
    var atEnd: Bool
}

/// The key window's view mode, for the View menu's checkmarks. (SwiftUI's
/// focusedSceneValue doesn't reach menu commands while an AppKit view inside a
/// representable has focus, which here is always.)
@MainActor
final class KeyWindowState: ObservableObject {
    static let shared = KeyWindowState()
    @Published var viewMode: ViewMode?
}
