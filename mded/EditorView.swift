import SwiftUI

struct EditorView: NSViewControllerRepresentable {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?
    @Binding var viewMode: ViewMode
    @AppStorage(DefaultsKey.appearance) private var appearanceRaw: String = AppearancePreference.system.rawValue
    @AppStorage(DefaultsKey.zoom) private var zoom = 1.0
    @AppStorage(DefaultsKey.syntaxColouring) private var syntaxColouring = true
    @AppStorage(DefaultsKey.literalUnderscores) private var literalUnderscores = true

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    func makeNSViewController(context: Context) -> SplitEditorController {
        let controller = SplitEditorController()
        controller.fileURL = fileURL // before the view loads, so the preview loads once with the right base
        return controller
    }

    func updateNSViewController(_ controller: SplitEditorController, context: Context) {
        // Re-bound on every update: reverting (or reloading after the file changed
        // on disk) gives SwiftUI a new MarkdownDocument instance, and edits must
        // go to that one, not the instance this view was created with.
        controller.onTextChange = { [weak document] text in
            document?.text = text
        }
        let viewModeBinding = $viewMode
        controller.onViewModeChange = { mode in
            if viewModeBinding.wrappedValue != mode { viewModeBinding.wrappedValue = mode }
        }
        controller.fileURL = fileURL
        controller.updateContent(document.text)
        appearance.applyToApp()
        controller.applyAppearance(appearance)
        controller.setZoom(zoom)
        controller.setSyntaxColouring(syntaxColouring)
        controller.setLiteralUnderscores(literalUnderscores)
        controller.setViewMode(viewMode)
    }
}
