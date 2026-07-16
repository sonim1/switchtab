import Foundation

extension String {
    private static let switcherReadableTextBoundaryWhitespace = CharacterSet.whitespacesAndNewlines

    func switcherReadableText(fallback: @autoclosure () -> String) -> String {
        guard !isEmpty else {
            return fallback()
        }

        let utf8 = self.utf8
        guard let firstByte = utf8.first,
              let lastByte = utf8.last else {
            return fallback()
        }

        if Self.isASCIIWhitespace(firstByte) || Self.isASCIIWhitespace(lastByte) {
            let trimmedText = trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedText.isEmpty ? fallback() : trimmedText
        }

        guard firstByte >= 128 || lastByte >= 128 else {
            return self
        }

        guard Self.hasBoundaryWhitespace(self) else {
            return self
        }

        let trimmedText = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? fallback() : trimmedText
    }

    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        switch byte {
        case 9...13, 32:
            return true
        default:
            return false
        }
    }

    private static func hasBoundaryWhitespace(_ text: String) -> Bool {
        guard let firstScalar = text.unicodeScalars.first,
              let lastScalar = text.unicodeScalars.last else {
            return false
        }

        return Self.switcherReadableTextBoundaryWhitespace.contains(firstScalar)
            || Self.switcherReadableTextBoundaryWhitespace.contains(lastScalar)
    }
}
