import Foundation

/// Markdown-aware editing commands, as pure functions over the text and the
/// selection. The editor applies the returned edit through NSTextView so it is
/// undoable like typing.
enum MarkdownEditing {
    struct Edit: Equatable {
        /// Range of the original text to replace.
        var range: NSRange
        var replacement: String
        /// Selection afterwards, in the edited text.
        var selection: NSRange
    }

    // Leading indent, then a bullet or number marker, its spacing, and an optional task box.
    private static let listItem = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let blockquote = try! NSRegularExpression(pattern: #"^[ \t]*(?:>[ \t]?)+"#)

    /// Return inside a list item or blockquote: continue it on the next line
    /// (numbering on, task boxes unchecked). Return on an empty item ends the
    /// list instead, leaving a blank line. Nil means "do the normal thing".
    static func newline(in text: NSString, selection: NSRange) -> Edit? {
        guard selection.length == 0 else { return nil }
        let cursor = selection.location
        let lineRange = contentRange(ofLineAt: cursor, in: text)
        let line = text.substring(with: lineRange)
        let lineNS = line as NSString
        let whole = NSRange(location: 0, length: lineNS.length)

        let prefix: String
        let prefixLength: Int
        if let m = listItem.firstMatch(in: line, range: whole) {
            let indent = lineNS.substring(with: m.range(at: 1))
            let spacing = lineNS.substring(with: m.range(at: 5))
            let task = m.range(at: 6).location != NSNotFound ? "[ ] " : ""
            if m.range(at: 2).location != NSNotFound {
                prefix = indent + lineNS.substring(with: m.range(at: 2)) + spacing + task
            } else {
                let number = (Int(lineNS.substring(with: m.range(at: 3))) ?? 0) + 1
                prefix = indent + String(number) + lineNS.substring(with: m.range(at: 4)) + spacing + task
            }
            prefixLength = m.range.length
        } else if let m = blockquote.firstMatch(in: line, range: whole) {
            prefix = lineNS.substring(with: m.range)
            prefixLength = m.range.length
        } else {
            return nil
        }

        // Cursor inside the marker itself: leave Return alone.
        guard cursor >= lineRange.location + prefixLength else { return nil }

        let body = lineNS.substring(from: prefixLength)
        if body.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item: end the list by clearing the marker.
            return Edit(range: lineRange, replacement: "",
                        selection: NSRange(location: lineRange.location, length: 0))
        }
        let insertion = "\n" + prefix
        return Edit(range: selection, replacement: insertion,
                    selection: NSRange(location: cursor + (insertion as NSString).length, length: 0))
    }

    /// Tab / Shift-Tab on list items: indent or outdent every selected line by
    /// its marker's width (2 for "- ", 3 for "1. "). Only applies when all
    /// selected lines are list items; nil otherwise.
    static func indent(in text: NSString, selection: NSRange, outdent: Bool) -> Edit? {
        var lines: [NSRange] = []
        var location = selection.location
        let end = selection.location + selection.length
        repeat {
            let line = contentRange(ofLineAt: location, in: text)
            lines.append(line)
            let full = text.lineRange(for: NSRange(location: location, length: 0))
            location = full.location + full.length
        } while location < end && location < text.length

        var replacements: [String] = []
        var deltas: [Int] = []
        for line in lines {
            let content = text.substring(with: line)
            let ns = content as NSString
            guard let m = listItem.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)) else {
                return nil
            }
            let width = m.range.length - m.range(at: 1).length - (m.range(at: 6).location != NSNotFound ? m.range(at: 6).length : 0)
            if outdent {
                let leading = ns.substring(with: m.range(at: 1))
                let removed: Int
                if leading.hasPrefix("\t") {
                    removed = 1
                } else {
                    removed = min(width, leading.prefix(while: { $0 == " " }).count)
                }
                replacements.append(ns.substring(from: removed))
                deltas.append(-removed)
            } else {
                replacements.append(String(repeating: " ", count: width) + content)
                deltas.append(width)
            }
        }
        if outdent, deltas.allSatisfy({ $0 == 0 }) { return nil }

        let first = lines[0], last = lines[lines.count - 1]
        let range = NSRange(location: first.location, length: last.location + last.length - first.location)
        let joined = zip(lines.indices, replacements).map { index, replacement -> String in
            guard index < lines.count - 1 else { return replacement }
            // Keep whatever line break separated this line from the next.
            let gapStart = lines[index].location + lines[index].length
            return replacement + text.substring(with: NSRange(location: gapStart, length: lines[index + 1].location - gapStart))
        }.joined()

        // A selection that starts at the line start keeps starting there, so it
        // covers the new indentation too.
        let start = selection.location == first.location ? first.location : max(first.location, selection.location + deltas[0])
        let total = deltas.reduce(0, +)
        let length = max(0, selection.length + total - (start - selection.location))
        return Edit(range: range, replacement: joined,
                    selection: NSRange(location: start, length: selection.length == 0 ? 0 : length))
    }

    /// The line containing `location`, without its line terminator.
    private static func contentRange(ofLineAt location: Int, in text: NSString) -> NSRange {
        var start = 0, contentsEnd = 0
        text.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }
}

/// Counts for the status bar.
struct TextStats: Equatable, Sendable {
    var words = 0
    var characters = 0

    /// Minutes at ~230 words per minute, at least 1 for any text.
    var readingMinutes: Int { words == 0 ? 0 : max(1, Int((Double(words) / 230).rounded())) }

    init(words: Int = 0, characters: Int = 0) {
        self.words = words
        self.characters = characters
    }

    /// A word is a run of letters, digits, or apostrophes/hyphens inside a word,
    /// so Markdown punctuation (#, *, -, >) isn't counted.
    init(_ text: String) {
        var inWord = false
        var words = 0
        var characters = 0
        var previousJoiner = false
        for character in text {
            characters += 1
            let isWordCharacter = character.isLetter || character.isNumber
            let isJoiner = character == "'" || character == "’" || character == "-"
            if isWordCharacter {
                if !inWord { words += 1 }
                inWord = true
                previousJoiner = false
            } else if isJoiner && inWord && !previousJoiner {
                previousJoiner = true // "don't", "well-known" stay one word
            } else {
                inWord = false
                previousJoiner = false
            }
        }
        self.words = words
        self.characters = characters
    }
}
