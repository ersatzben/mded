import XCTest

final class MarkdownEditingTests: XCTestCase {
    /// Applies the edit for Return at the `|` in `text`; returns the result with `|` at the new cursor.
    private func pressReturn(_ text: String) -> String? {
        let (source, selection) = split(text)
        guard let edit = MarkdownEditing.newline(in: source as NSString, selection: selection) else { return nil }
        return apply(edit, to: source)
    }

    private func pressTab(_ text: String, outdent: Bool = false) -> String? {
        let (source, selection) = split(text)
        guard let edit = MarkdownEditing.indent(in: source as NSString, selection: selection, outdent: outdent) else { return nil }
        return apply(edit, to: source)
    }

    /// `|` marks a cursor; `[` … `]` a selection.
    private func split(_ text: String) -> (String, NSRange) {
        if let bar = text.range(of: "|") {
            let location = text.utf16.distance(from: text.startIndex, to: bar.lowerBound)
            return (text.replacingCharacters(in: bar, with: ""), NSRange(location: location, length: 0))
        }
        let open = text.range(of: "[")!
        let start = text.utf16.distance(from: text.startIndex, to: open.lowerBound)
        let stripped = text.replacingCharacters(in: open, with: "")
        let close = stripped.range(of: "]")!
        let end = stripped.utf16.distance(from: stripped.startIndex, to: close.lowerBound)
        return (stripped.replacingCharacters(in: close, with: ""), NSRange(location: start, length: end - start))
    }

    private func apply(_ edit: MarkdownEditing.Edit, to text: String) -> String {
        let result = NSMutableString(string: (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement))
        if edit.selection.length == 0 {
            result.insert("|", at: edit.selection.location)
        } else {
            result.insert("]", at: edit.selection.location + edit.selection.length)
            result.insert("[", at: edit.selection.location)
        }
        return result as String
    }

    // MARK: Return

    func testContinuesBulletList() {
        XCTAssertEqual(pressReturn("- one|"), "- one\n- |")
        XCTAssertEqual(pressReturn("  * nested|"), "  * nested\n  * |")
    }

    func testContinuesNumberedListIncrementing() {
        XCTAssertEqual(pressReturn("9. nine|"), "9. nine\n10. |")
        XCTAssertEqual(pressReturn("1) a|"), "1) a\n2) |")
    }

    func testContinuesTaskListUnchecked() {
        XCTAssertEqual(pressReturn("- [x] done|"), "- [x] done\n- [ ] |")
    }

    func testContinuesBlockquote() {
        XCTAssertEqual(pressReturn("> quoted|"), "> quoted\n> |")
    }

    func testSplitsItemAtCursor() {
        XCTAssertEqual(pressReturn("- one| two"), "- one\n- | two")
    }

    func testReturnOnEmptyItemEndsList() {
        XCTAssertEqual(pressReturn("- one\n- |"), "- one\n|")
        XCTAssertEqual(pressReturn("- one\n- [ ] |\nafter"), "- one\n|\nafter")
    }

    func testPlainTextIsLeftAlone() {
        XCTAssertNil(pressReturn("hello|"))
        XCTAssertNil(pressReturn("-not a list|"))
        XCTAssertNil(pressReturn("|- cursor before marker"))
    }

    // MARK: Tab

    func testTabIndentsListItemByMarkerWidth() {
        XCTAssertEqual(pressTab("- a\n- b|"), "- a\n  - b|")
        XCTAssertEqual(pressTab("1. a\n2. b|"), "1. a\n   2. b|")
    }

    func testShiftTabOutdents() {
        XCTAssertEqual(pressTab("- a\n  - b|", outdent: true), "- a\n- b|")
        XCTAssertNil(pressTab("- top|", outdent: true))
    }

    func testTabIndentsEverySelectedItem() {
        XCTAssertEqual(pressTab("[- a\n- b]"), "[  - a\n  - b]")
    }

    func testTabOutsideListsIsLeftAlone() {
        XCTAssertNil(pressTab("plain|"))
        XCTAssertNil(pressTab("[- a\nplain]"))
    }

    // MARK: Stats

    func testWordCount() {
        XCTAssertEqual(TextStats("# Hello, world!\n\n- don't panic\n- well-known *fact*").words, 6)
        XCTAssertEqual(TextStats("").words, 0)
        XCTAssertEqual(TextStats("café 2024").words, 2)
        XCTAssertEqual(TextStats("👍🏽 ok").characters, 4)
    }

    func testReadingTime() {
        XCTAssertEqual(TextStats(words: 0).readingMinutes, 0)
        XCTAssertEqual(TextStats(words: 10).readingMinutes, 1)
        XCTAssertEqual(TextStats(words: 2300).readingMinutes, 10)
    }
}
