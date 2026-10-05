import SwiftUI

struct SettingsView: View {
    @AppStorage(DefaultsKey.syntaxColouring) private var syntaxColouring = true
    @AppStorage(DefaultsKey.literalUnderscores) private var literalUnderscores = true

    var body: some View {
        Form {
            Section("Editor") {
                Toggle("Colour Markdown syntax", isOn: $syntaxColouring)
            }
            Section("Preview") {
                Toggle("Treat underscores as literal characters", isOn: $literalUnderscores)
                Text("Identifiers like __init__ and snake_case stay as typed. Use *emphasis* and **bold**; with this off, _emphasis_ and __bold__ work too. Quick Look always treats underscores literally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
