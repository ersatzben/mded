import SwiftUI
import AppKit

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case evening

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .evening: return "Evening"
        }
    }

    /// Drives `.preferredColorScheme(...)` for the SwiftUI window chrome.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .evening: return .light
        case .dark: return .dark
        }
    }

    /// NSAppearance for the AppKit subtree (split view, scroll bars, find bar).
    /// Evening rides on top of aqua so the chrome stays light.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light, .evening: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    var isEvening: Bool { self == .evening }
}

// Evening palette — used by both the editor NSTextView and the WebView preview.
enum EveningPalette {
    static let background = NSColor(srgbRed: 0xF7/255.0, green: 0xF3/255.0, blue: 0xDF/255.0, alpha: 1.0)
    static let text = NSColor(srgbRed: 0x3B/255.0, green: 0x38/255.0, blue: 0x36/255.0, alpha: 1.0)
}

struct AppearanceCommands: Commands {
    @AppStorage("appearance") private var appearanceRaw: String = AppearancePreference.system.rawValue

    var body: some Commands {
        CommandMenu("Appearance") {
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(AppearancePreference.allCases) { pref in
                    Text(pref.label).tag(pref.rawValue)
                }
            }
            .pickerStyle(.inline)
        }
    }
}
