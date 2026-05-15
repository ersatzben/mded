import SwiftUI

struct EditorView: NSViewControllerRepresentable {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?
    @AppStorage("appearance") private var appearanceRaw: String = AppearancePreference.system.rawValue

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    func makeNSViewController(context: Context) -> SplitEditorController {
        let controller = SplitEditorController()
        controller.fileURL = fileURL
        controller.onTextChange = { [weak document] text in
            document?.text = text
        }
        controller.applyAppearance(appearance)
        return controller
    }

    func updateNSViewController(_ controller: SplitEditorController, context: Context) {
        controller.fileURL = fileURL
        controller.updateContent(document.text)
        controller.applyAppearance(appearance)
    }
}
