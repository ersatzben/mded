import Foundation

/// How a text file was encoded on disk, so saving writes it back the same way.
struct TextFormat: Equatable, Sendable {
    var encoding: String.Encoding
    var hasBOM: Bool

    static let utf8 = TextFormat(encoding: .utf8, hasBOM: false)
}

enum TextCodec {
    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Decodes UTF-8 (with or without a BOM), then UTF-16/32 with a BOM, then
    /// common legacy 8-bit encodings. Returns nil if nothing fits.
    static func decode(_ data: Data) -> (text: String, format: TextFormat)? {
        if data.starts(with: utf8BOM),
           let text = String(data: data.dropFirst(utf8BOM.count), encoding: .utf8) {
            return (text, TextFormat(encoding: .utf8, hasBOM: true))
        }
        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }

        var converted: NSString?
        var usedLossy: ObjCBool = false
        let suggested: [NSNumber] = [
            String.Encoding.utf16.rawValue,
            String.Encoding.utf32.rawValue,
            String.Encoding.windowsCP1252.rawValue,
            String.Encoding.isoLatin1.rawValue,
            String.Encoding.macOSRoman.rawValue,
        ].map { NSNumber(value: $0) }
        let raw = NSString.stringEncoding(
            for: data,
            encodingOptions: [.suggestedEncodingsKey: suggested, .allowLossyKey: false],
            convertedString: &converted,
            usedLossyConversion: &usedLossy
        )
        guard raw != 0, let converted, !usedLossy.boolValue else { return nil }
        let encoding = String.Encoding(rawValue: raw)
        let hasBOM = encoding == .utf16 || encoding == .utf32
        return (converted as String, TextFormat(encoding: encoding, hasBOM: hasBOM))
    }

    /// Encodes `text` in `format`. Falls back to UTF-8 when the original encoding
    /// can't represent the text (say, an emoji typed into a Latin-1 file) rather
    /// than losing characters.
    static func encode(_ text: String, as format: TextFormat) -> Data {
        if format.encoding == .utf8 {
            return format.hasBOM ? Data(utf8BOM) + Data(text.utf8) : Data(text.utf8)
        }
        // String.data(using: .utf16/.utf32) emits a BOM itself.
        return text.data(using: format.encoding, allowLossyConversion: false) ?? Data(text.utf8)
    }
}
