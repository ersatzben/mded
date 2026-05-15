import SwiftUI

@main
struct mdedApp: App {
    @AppStorage("appearance") private var appearanceRaw: String = AppearancePreference.system.rawValue

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { config in
            EditorView(document: config.document, fileURL: config.fileURL)
                .frame(minWidth: 600, minHeight: 400)
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 1350, height: 850)
        .commands {
            AppearanceCommands()
        }
    }
}
