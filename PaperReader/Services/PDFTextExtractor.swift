import Foundation
import PDFKit

enum PDFExtractionError: LocalizedError {
    case cannotOpen
    case scannedPDF
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .cannotOpen: return "Couldn't open this file as a PDF."
        case .scannedPDF: return "This looks like a scanned PDF (no selectable text). Scanned PDFs aren't supported yet."
        case .emptyDocument: return "This PDF has no pages."
        }
    }
}

enum PDFTextExtractor {
    struct Extraction {
        let pages: [String]
        let pageCount: Int
    }

    static func extractPages(from url: URL) throws -> Extraction {
        guard let document = PDFDocument(url: url) else { throw PDFExtractionError.cannotOpen }
        guard document.pageCount > 0 else { throw PDFExtractionError.emptyDocument }

        var rawPages: [String] = []
        for i in 0..<document.pageCount {
            rawPages.append(document.page(at: i)?.string ?? "")
        }

        let totalChars = rawPages.reduce(0) { $0 + $1.count }
        if totalChars < 200 {
            throw PDFExtractionError.scannedPDF
        }

        let cleaned = clean(pages: rawPages)
        return Extraction(pages: cleaned, pageCount: document.pageCount)
    }

    // MARK: - Cleaning

    private static func clean(pages: [String]) -> [String] {
        let repeatedLines = findRepeatedLines(in: pages)
        return pages.map { page in
            var lines = page.components(separatedBy: .newlines)
            lines = lines.filter { line in
                let key = normalizeLine(line)
                return key.isEmpty || !repeatedLines.contains(key)
            }
            var text = lines.joined(separator: "\n")
            text = joinHyphenatedLineBreaks(text)
            text = collapseWhitespace(text)
            return text
        }
    }

    /// Lines appearing on more than half the pages are headers/footers.
    /// Digits are stripped from the key so changing page numbers still match.
    private static func findRepeatedLines(in pages: [String]) -> Set<String> {
        guard pages.count >= 3 else { return [] }
        var counts: [String: Int] = [:]
        for page in pages {
            let uniqueKeys = Set(page.components(separatedBy: .newlines).map(normalizeLine).filter { !$0.isEmpty })
            for key in uniqueKeys {
                counts[key, default: 0] += 1
            }
        }
        let threshold = pages.count / 2 + 1
        return Set(counts.filter { $0.value >= threshold && $0.key.count > 3 }.keys)
    }

    private static func normalizeLine(_ line: String) -> String {
        line.lowercased()
            .filter { !$0.isNumber }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "informa-\ntion" -> "information"
    private static func joinHyphenatedLineBreaks(_ text: String) -> String {
        text.replacingOccurrences(of: #"(\w)-\s*\n\s*(\w)"#, with: "$1$2", options: .regularExpression)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
