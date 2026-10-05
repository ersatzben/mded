import WebKit
import XCTest

/// Loads the real preview page and renderer in a WKWebView, configured exactly
/// as the app and Quick Look extension configure it.
@MainActor
final class PreviewPageTests: XCTestCase {
    private var webView: WKWebView!
    private var loadDelegate: LoadDelegate!
    private var folder: URL!

    override func setUp() async throws {
        let bundle = Bundle(for: Self.self)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.onePixelPNG.write(to: folder.appendingPathComponent("pixel.png"))

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                            configuration: MarkdownRenderer.makeConfiguration(bundle: bundle))
        loadDelegate = LoadDelegate()
        webView.navigationDelegate = loadDelegate
        let loaded = expectation(description: "page loaded")
        loadDelegate.onFinish = { loaded.fulfill() }
        webView.loadHTMLString(MarkdownRenderer.pageHTML(bundle: bundle),
                               baseURL: MarkdownRenderer.pageBaseURL(forDirectory: folder))
        await fulfillment(of: [loaded], timeout: 10)
    }

    override func tearDown() async throws {
        webView = nil
        try? FileManager.default.removeItem(at: folder)
    }

    private func render(_ markdown: String) async throws {
        let done = expectation(description: "rendered")
        var renderError: Error?
        MarkdownRenderer.render(markdown, in: webView) { error in
            renderError = error
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 10)
        if let renderError { throw renderError }
    }

    /// Evaluates `body` (a function body; use `return`) in the renderer's world.
    private func value(_ body: String) async throws -> Any? {
        try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: MarkdownRenderer.world)
    }

    // MARK: Tests

    func testRendersMarkdownWithHeadingIds() async throws {
        try await render("# Title\n\nSome *text*.")
        let id = try await value("return document.querySelector('h1').id")
        XCTAssertEqual(id as? String, "title")
    }

    func testEmbeddedScriptDoesNotRun() async throws {
        try await render("""
        <script>document.body.dataset.inline = 'ran'</script>
        <img src="missing.png" onerror="document.body.dataset.handler = 'ran'">
        <iframe srcdoc="<script>parent.document.body.dataset.frame = 'ran'</script>"></iframe>
        """)
        try await Task.sleep(for: .milliseconds(500))
        let ran = try await value("return JSON.stringify(document.body.dataset)")
        XCTAssertEqual(ran as? String, "{}")
    }

    func testRelativeImagesLoad() async throws {
        try await render("![pixel](pixel.png)")
        try await Task.sleep(for: .milliseconds(500))
        let width = try await value("return document.querySelector('img').naturalWidth")
        XCTAssertEqual(width as? Int, 1)
    }

    func testAbsoluteFileImagesLoad() async throws {
        let path = folder.appendingPathComponent("pixel.png")
        try await render("![a](\(path.path)) ![b](\(path.absoluteString))")
        try await Task.sleep(for: .milliseconds(500))
        let widths = try await value("return Array.from(document.querySelectorAll('img')).map(i => i.naturalWidth).join(',')")
        XCTAssertEqual(widths as? String, "1,1")
    }

    func testNonMediaFilesAreNotServed() async throws {
        try FileManager.default.copyItem(at: folder.appendingPathComponent("pixel.png"),
                                         to: folder.appendingPathComponent("pixel.txt"))
        try await render("![t](pixel.txt)")
        try await Task.sleep(for: .milliseconds(500))
        let width = try await value("return document.querySelector('img').naturalWidth")
        XCTAssertEqual(width as? Int, 0)
    }

    func testRerenderKeepsUnchangedElements() async throws {
        try await render("Intro\n\n![pixel](pixel.png)\n\n<details><summary>More</summary>Hidden</details>")
        _ = try await value("""
        document.querySelector('img').mdedMarker = 'original'; // a JS property: invisible to the DOM diff
        document.querySelector('details').open = true;
        return null;
        """)
        // Insert a paragraph above, edit the intro: the image and details survive.
        try await render("New first line\n\nIntro, edited\n\n![pixel](pixel.png)\n\n<details><summary>More</summary>Hidden</details>")
        let marker = try await value("return document.querySelector('img').mdedMarker || 'recreated'")
        let open = try await value("return document.querySelector('details').open")
        let text = try await value("return document.getElementById('content').innerText")
        XCTAssertEqual(marker as? String, "original")
        XCTAssertEqual(open as? Bool, true)
        XCTAssertTrue((text as? String)?.contains("Intro, edited") == true)
        XCTAssertTrue((text as? String)?.hasPrefix("New first line") == true)
    }

    func testRerenderMatchesFreshRender() async throws {
        let first = "# A\n\n- one\n- two\n\n```swift\nlet x = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |"
        let second = "# A changed\n\n- one\n- three\n- two\n\n```swift\nlet x = 2\n```\n\nNew para\n\n| a | b |\n|---|---|\n| 1 | 2 |"
        try await render(first)
        try await render(second)
        let morphed = try await value("return document.getElementById('content').innerHTML")
        try await render("")
        try await render(second)
        let fresh = try await value("return document.getElementById('content').innerHTML")
        XCTAssertEqual(morphed as? String, fresh as? String)
    }

    func testBlocksCarrySourceLines() async throws {
        try await render("# A\n\npara\n\n- x\n- y")
        let lines = try await value("return Array.from(document.getElementById('content').children).map(e => e.dataset.line).join(',')")
        XCTAssertEqual(lines as? String, "0,2,4")
    }

    func testEditingAboveShiftsLinesButKeepsElements() async throws {
        try await render("Intro\n\n![pixel](pixel.png)")
        _ = try await value("document.querySelector('img').mdedMarker = 'original'; return null")
        try await render("Intro\n\nNew line\n\n![pixel](pixel.png)")
        let marker = try await value("return document.querySelector('img').mdedMarker || 'recreated'")
        let line = try await value("return document.querySelector('img').parentElement.dataset.line")
        XCTAssertEqual(marker as? String, "original")
        XCTAssertEqual(line as? String, "4")
    }

    func testScrollToLineLandsOnThatBlock() async throws {
        let paragraphs = (0..<120).map { "Paragraph \($0)" }.joined(separator: "\n\n")
        try await render(paragraphs)
        // Paragraph 60 is on source line 120.
        _ = try await value("scrollToLine(120, false); return null")
        let top = try await value("""
        const p = Array.from(document.querySelectorAll('p')).find(e => e.textContent === 'Paragraph 60');
        return Math.round(p.getBoundingClientRect().top);
        """)
        XCTAssertEqual(Double((top as? Int) ?? 999), 0, accuracy: 2)
    }

    func testWaitingForImagesCompletesInAnOffscreenView() async throws {
        // The test web view isn't in a window, like the exporter's: no animation frames.
        try await render("![pixel](pixel.png) ![missing](missing.png)")
        await MarkdownRenderer.whenImagesLoaded(in: webView)
        let complete = try await value("return Array.from(document.images).every(i => i.complete)")
        XCTAssertEqual(complete as? Bool, true)
    }

    func testExportInlinesImagesAndStripsScripts() async throws {
        try await render("# Doc\n\n![pixel](pixel.png)\n\n<a href=\"javascript:alert(1)\" onclick=\"x()\">link</a><script>bad()</script>")
        try await Task.sleep(for: .milliseconds(300))
        let html = try await MarkdownRenderer.exportBodyHTML(in: webView)
        XCTAssertTrue(html.contains("src=\"data:image/png;base64,"), html)
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertFalse(html.contains("onclick"))
        XCTAssertFalse(html.contains("data-line"))
        XCTAssertTrue(html.contains(#"<h1 id="doc">Doc</h1>"#), html)
    }

    func testAnchorScrolling() async throws {
        let tall = (1...200).map { "Line \($0)\n" }.joined(separator: "\n")
        try await render("# Top\n\n\(tall)\n## Bottom Part\n\nEnd")
        let found = try await value("return scrollToAnchor('bottom-part')")
        XCTAssertEqual(found as? Bool, true)
        let top = try await value("return document.documentElement.scrollTop")
        XCTAssertGreaterThan((top as? Double) ?? Double((top as? Int) ?? 0), 0)
    }

    // MARK: Fixtures

    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        var onFinish: (() -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinish?()
            onFinish = nil
        }
    }

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")!
}
