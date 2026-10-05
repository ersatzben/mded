import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    // macOS reports .md files as net.daringfireball.markdown (the de facto UTI,
    // declared in CoreTypes for .md/.markdown). Info.plist exports
    // com.mded.markdown-variant, conforming to it, for .mdown/.mkd/.mkdn.
    // public.markdown isn't Apple's — some apps (e.g. Word) import it — so it's
    // only an extra readable type.
    static let markdown: UTType = UTType("net.daringfireball.markdown") ?? .plainText
    static let markdownVariant: UTType = UTType("com.mded.markdown-variant") ?? .plainText
    static let publicMarkdown: UTType = UTType("public.markdown") ?? .plainText
}

enum MarkdownFile {
    /// Extensions mded claims; mirrored in Info.plist's type declarations.
    static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    static func isMarkdown(_ url: URL) -> Bool {
        if extensions.contains(url.pathExtension.lowercased()) { return true }
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .markdown)
    }
}

// `@unchecked Sendable` is the documented pattern for ReferenceFileDocument types
// with mutable `@Published` state: SwiftUI mediates access (snapshot on main,
// fileWrapper on a background queue with an immutable snapshot value), but the
// protocol's isolation isn't expressible cleanly in Swift's concurrency model.
final class MarkdownDocument: ReferenceFileDocument, @unchecked Sendable {
    struct Snapshot: Sendable {
        var text: String
        var format: TextFormat
    }

    @Published var text: String
    /// The file's on-disk encoding, so saving doesn't silently convert it.
    let format: TextFormat

    static var readableContentTypes: [UTType] { [.markdown, .markdownVariant, .publicMarkdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown] }

    init(text: String = "") {
        self.text = text
        self.format = .utf8
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let decoded = TextCodec.decode(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = decoded.text
        self.format = decoded.format
    }

    func snapshot(contentType: UTType) throws -> Snapshot {
        Snapshot(text: text, format: format)
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: TextCodec.encode(snapshot.text, as: snapshot.format))
    }
}
