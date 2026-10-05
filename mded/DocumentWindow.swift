import SwiftUI

/// One document window: the editor/preview split plus the optional status bar.
struct DocumentWindow: View {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?
    @SceneStorage("viewMode") private var viewMode: ViewMode = .split
    @AppStorage(DefaultsKey.showStatusBar) private var showStatusBar = true

    var body: some View {
        VStack(spacing: 0) {
            EditorView(document: document, fileURL: fileURL, viewMode: $viewMode)
            if showStatusBar {
                Divider()
                StatusBar(text: document.text)
            }
        }
    }
}

private struct StatusBar: View {
    let text: String
    @State private var stats = TextStats()

    var body: some View {
        HStack(spacing: 6) {
            Spacer()
            Text(summary)
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
        // Counting is O(length); wait for a pause in typing.
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(stats == TextStats() ? 0 : 250))
            guard !Task.isCancelled else { return }
            stats = TextStats(text)
        }
    }

    private var summary: String {
        let words = stats.words.formatted()
        let characters = stats.characters.formatted()
        let wordLabel = stats.words == 1 ? "word" : "words"
        let characterLabel = stats.characters == 1 ? "character" : "characters"
        return "\(words) \(wordLabel) · \(characters) \(characterLabel) · \(stats.readingMinutes) min read"
    }
}
