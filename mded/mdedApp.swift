import SwiftUI

@main
struct mdedApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { config in
            DocumentWindow(document: config.document, fileURL: config.fileURL)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 1350, height: 850)
        .commands {
            AppearanceCommands()
            FindCommands()
            ViewCommands()
            ExportCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
