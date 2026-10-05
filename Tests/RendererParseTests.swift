import JavaScriptCore
import XCTest

/// Markdown → HTML through the bundled marked.js plus renderer.js, run under
/// JavaScriptCore (no DOM), exactly as the preview configures it.
final class RendererParseTests: XCTestCase {
    private var context: JSContext!

    override func setUpWithError() throws {
        let bundle = Bundle(for: Self.self)
        context = try XCTUnwrap(JSContext())
        var jsError: String?
        context.exceptionHandler = { _, exception in jsError = exception?.toString() }
        for name in ["marked.min", "renderer"] {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "js"), "\(name).js not bundled")
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        }
        XCTAssertNil(jsError)
    }

    private func html(_ markdown: String) -> String {
        context.objectForKeyedSubscript("mdedParse")
            .call(withArguments: [markdown])
            .toString()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Underscores

    func testUnderscoresAreLiteral() {
        XCTAssertEqual(html("__init__"), "<p>__init__</p>")
        XCTAssertEqual(html("_private and __dunder__"), "<p>_private and __dunder__</p>")
        XCTAssertEqual(html("snake_case_func in /path/to/some_file.md"),
                       "<p>snake_case_func in /path/to/some_file.md</p>")
    }

    func testAsteriskEmphasisStillWorks() {
        XCTAssertEqual(html("*em* and **strong** and *a_b*"),
                       "<p><em>em</em> and <strong>strong</strong> and <em>a_b</em></p>")
    }

    func testUnderscoredEmailAfterTextLinksWhole() {
        XCTAssertEqual(
            html("Email me at first_last@example.com today"),
            #"<p>Email me at <a href="mailto:first_last@example.com">first_last@example.com</a> today</p>"#
        )
    }

    func testUnderscoredURLLinksWhole() {
        XCTAssertEqual(
            html("See https://example.com/a_b_c for more"),
            #"<p>See <a href="https://example.com/a_b_c">https://example.com/a_b_c</a> for more</p>"#
        )
    }

    func testUnderscoresInsideCodeSpans() {
        XCTAssertEqual(html("`__init__`"), "<p><code>__init__</code></p>")
    }

    // MARK: Heading ids

    func testHeadingsGetGitHubStyleIds() {
        XCTAssertEqual(html("## My Section"), #"<h2 id="my-section">My Section</h2>"#)
        XCTAssertEqual(html("# Hello, `World`!"), #"<h1 id="hello-world">Hello, <code>World</code>!</h1>"#)
        XCTAssertEqual(html("### Café déjà vu"), #"<h3 id="café-déjà-vu">Café déjà vu</h3>"#)
        XCTAssertEqual(html("## a & b"), #"<h2 id="a--b">a &amp; b</h2>"#)
    }

    func testDuplicateHeadingsAreNumbered() {
        let out = html("# Intro\n\n# Intro\n\n# Intro")
        XCTAssertTrue(out.contains(#"id="intro""#))
        XCTAssertTrue(out.contains(#"id="intro-1""#))
        XCTAssertTrue(out.contains(#"id="intro-2""#))
    }

    func testHeadingIdsResetBetweenRenders() {
        XCTAssertEqual(html("# Intro"), html("# Intro"))
    }

    // MARK: Options

    func testUnderscoreEmphasisWhenLiteralUnderscoresIsOff() {
        context.evaluateScript("mdedSetOptions({ literalUnderscores: false })")
        XCTAssertEqual(html("_em_ and __strong__"), "<p><em>em</em> and <strong>strong</strong></p>")
        context.evaluateScript("mdedSetOptions({ literalUnderscores: true })")
        XCTAssertEqual(html("_em_"), "<p>_em_</p>")
    }

    // MARK: Source lines

    /// The 0-based source line each top-level block starts on.
    private func blockLines(_ markdown: String) -> [Int] {
        let result = context.objectForKeyedSubscript("mdedParseBlocks").call(withArguments: [markdown])!
        let blocks = result.objectForKeyedSubscript("blocks")!
        let count = Int(blocks.objectForKeyedSubscript("length").toInt32())
        return (0..<count).map { Int(blocks.atIndex($0).objectForKeyedSubscript("line").toInt32()) }
    }

    func testBlocksKnowTheirSourceLines() {
        XCTAssertEqual(blockLines("# A\n\npara\nstill para\n\n```\ncode\n```\n\n- x\n- y"), [0, 2, 5, 9])
    }

    func testLinkDefinitionsDontShiftLines() {
        // marked drops link reference definitions from its token list.
        XCTAssertEqual(blockLines("[a]: https://a.example\n[b]: https://b.example\n\n# After\n\ntext"), [3, 5])
    }

    func testCRLFLineEndings() {
        XCTAssertEqual(blockLines("# A\r\n\r\npara"), [0, 2])
    }
}
