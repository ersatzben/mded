import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    // macOS reports .md files as net.daringfireball.markdown (the de facto UTI).
    // public.markdown was never actually registered by Apple; keep it as a fallback.
    static let markdown: UTType = UTType("net.daringfireball.markdown") ?? .plainText
    static let publicMarkdown: UTType = UTType("public.markdown") ?? .plainText
}

// `@unchecked Sendable` is the documented pattern for ReferenceFileDocument types
// with mutable `@Published` state: SwiftUI mediates access (snapshot on main,
// fileWrapper on a background queue with an immutable snapshot value), but the
// protocol's isolation isn't expressible cleanly in Swift's concurrency model.
final class MarkdownDocument: ReferenceFileDocument, @unchecked Sendable {
    @Published var text: String

    static var readableContentTypes: [UTType] { [.markdown, .publicMarkdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown] }

    init(text: String = "") {
        self.text = text
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    func snapshot(contentType: UTType) throws -> String {
        text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(snapshot.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
