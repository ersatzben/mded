import XCTest

final class TextCodecTests: XCTestCase {
    private func roundTrip(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> (String, TextFormat) {
        let decoded = try XCTUnwrap(TextCodec.decode(data), file: file, line: line)
        XCTAssertEqual(TextCodec.encode(decoded.text, as: decoded.format), data,
                       "re-encoding changed the bytes", file: file, line: line)
        return decoded
    }

    func testUTF8() throws {
        let (text, format) = try roundTrip(Data("# Café ☕️\n".utf8))
        XCTAssertEqual(text, "# Café ☕️\n")
        XCTAssertEqual(format, .utf8)
    }

    func testUTF8ByteOrderMarkIsKept() throws {
        let (text, format) = try roundTrip(Data([0xEF, 0xBB, 0xBF]) + Data("# Title\n".utf8))
        XCTAssertEqual(text, "# Title\n")
        XCTAssertTrue(format.hasBOM)
    }

    func testWindows1252() throws {
        let data = Data("Caf".utf8) + Data([0xE9, 0x20, 0x93, 0x71, 0x94]) // Café “q”
        let (text, format) = try roundTrip(data)
        XCTAssertEqual(text, "Café “q”")
        XCTAssertNotEqual(format.encoding, .utf8)
    }

    func testUTF16WithBOM() throws {
        let data = try XCTUnwrap("# Héllo\n".data(using: .utf16))
        let decoded = try XCTUnwrap(TextCodec.decode(data))
        XCTAssertEqual(decoded.text, "# Héllo\n")
        XCTAssertEqual(TextCodec.decode(TextCodec.encode(decoded.text, as: decoded.format))?.text, "# Héllo\n")
    }

    func testFallsBackToUTF8WhenEncodingCannotRepresentText() throws {
        let format = TextFormat(encoding: .isoLatin1, hasBOM: false)
        XCTAssertEqual(TextCodec.encode("smile 😀", as: format), Data("smile 😀".utf8))
    }
}
