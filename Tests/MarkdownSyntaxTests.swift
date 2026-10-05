import XCTest

final class MarkdownSyntaxTests: XCTestCase {
    /// The text covered by each span of `kind`.
    private func texts(_ kind: MarkdownSyntax.Kind, in source: String) -> [String] {
        let ns = source as NSString
        return MarkdownSyntax.spans(in: ns).filter { $0.kind == kind }.map { ns.substring(with: $0.range) }
    }

    func testHeadingsAndMarkers() {
        let source = "# Title\n\n- item\n1. first\n- [ ] task\n\n---\n#notaheading"
        XCTAssertEqual(texts(.heading, in: source), ["# Title"])
        XCTAssertEqual(texts(.marker, in: source), ["---", "-", "1.", "- [ ]"])
    }

    func testInlineConstructs() {
        let source = "Some **bold**, *em*, `code`, [link](https://x.com) and <b>html</b>."
        XCTAssertEqual(texts(.emphasis, in: source), ["**bold**", "*em*"])
        XCTAssertEqual(texts(.code, in: source), ["`code`"])
        XCTAssertEqual(texts(.link, in: source), ["[link]"])
        XCTAssertEqual(texts(.url, in: source), ["(https://x.com)"])
        XCTAssertEqual(texts(.html, in: source), ["<b>", "</b>"])
    }

    func testCodeBlocksHideMarkdown() {
        let source = "```\n# not a heading\n**not bold**\n```\n# Heading"
        XCTAssertEqual(texts(.heading, in: source), ["# Heading"])
        XCTAssertEqual(texts(.emphasis, in: source), [])
        XCTAssertEqual(texts(.code, in: source), ["```\n# not a heading\n**not bold**\n```"])
    }

    func testUnclosedFenceRunsToEnd() {
        let source = "text\n~~~\ncode"
        XCTAssertEqual(texts(.code, in: source), ["~~~\ncode"])
    }

    func testUnderscoresInIdentifiersAreNotEmphasis() {
        XCTAssertEqual(texts(.emphasis, in: "snake_case_name and file_name.md"), [])
    }
}
