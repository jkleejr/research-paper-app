import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Puts the spaces back into PDF text that lost them.
///
/// Some publishers' PDFs justify text by positioning each glyph instead of
/// emitting space characters, so PDFKit hands back whole lines run together —
/// "examinedbyeconomistswhogenerallydonot". Every PDFKit extraction route
/// returns the same thing, so the words have to be reconstructed.
///
/// The trick is that the same document almost always contains those words
/// spaced correctly somewhere else, so its own vocabulary makes a better
/// lexicon than any general word list: it already knows the paper's jargon,
/// author names and abbreviations. The system dictionary is consulted only for
/// runs that vocabulary can't resolve, because it is comparatively slow.
struct TextRepair {
    /// Word frequencies harvested from the document's correctly-spaced text.
    private let lexicon: [String: Int]
    private let totalWords: Double

    /// Longest word the segmenter will consider — beyond this it's a glued run.
    private static let maxWordLength = 18
    /// Alphabetic runs shorter than this are left alone; real words this long
    /// that are genuinely absent from the lexicon are rare enough to ignore.
    private static let minRunLength = 5
    /// The system dictionary is only consulted for pieces at least this long;
    /// shorter pieces are function words the document itself will have.
    private static let minDictionaryPiece = 4

    init(pages: [String]) {
        var counts: [String: Int] = [:]
        for page in pages {
            for token in page.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }) {
                // Anything longer is itself a glued run — don't learn from it.
                guard token.count <= 15 else { continue }
                counts[token.lowercased(), default: 0] += 1
            }
        }
        self.lexicon = Self.dropGluedEntries(from: counts)
        self.totalWords = Double(max(self.lexicon.values.reduce(0, +), 1))
    }

    /// Restores spaces in every glued run in the text.
    func deglued(_ text: String) -> String {
        guard let runs = try? NSRegularExpression(pattern: "\\p{L}{\(Self.minRunLength),}") else {
            return text
        }
        let ns = text as NSString
        var out = ""
        var copiedUpTo = 0
        for match in runs.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let run = ns.substring(with: match.range)
            // A word the document uses elsewhere: nothing to repair.
            if lexicon[run.lowercased()] != nil { continue }
            guard let pieces = split(run), pieces.count > 1 else { continue }
            out += ns.substring(with: NSRange(location: copiedUpTo,
                                              length: match.range.location - copiedUpTo))
            out += pieces.joined(separator: " ")
            copiedUpTo = match.range.location + match.range.length
        }
        out += ns.substring(from: copiedUpTo)
        return out
    }

    /// Cheap pass first; only pay for the system dictionary if it fails.
    private func split(_ run: String) -> [String]? {
        if let pieces = segment(run, allowDictionary: false) { return pieces }
        return segment(run, allowDictionary: true)
    }

    /// Maximises total unigram log-probability across the pieces. That
    /// objective is what prefers "in the" — two very common words — over the
    /// single rare "inthe"; minimising the number of pieces gets it backwards.
    private func segment(_ run: String, allowDictionary: Bool) -> [String]? {
        let chars = Array(run)
        let n = chars.count
        // best[i] = (score, start index of the last word) for run[0..<i]
        var best = [(score: Double, start: Int)?](repeating: nil, count: n + 1)
        best[0] = (0, 0)

        for i in 1...n {
            for j in max(0, i - Self.maxWordLength)..<i {
                guard let prior = best[j] else { continue }
                let piece = String(chars[j..<i]).lowercased()
                // Single letters only where they're real words.
                if piece.count == 1, piece != "a", piece != "i" { continue }

                var frequency = Double(lexicon[piece] ?? 0)
                if frequency == 0 {
                    guard allowDictionary, piece.count >= Self.minDictionaryPiece,
                          Self.dictionaryKnows(piece) else { continue }
                    // Below any real count, so document words always win.
                    frequency = 0.3
                }
                let candidate = (score: prior.score + log(frequency / totalWords), start: j)
                if best[i] == nil || candidate.score > best[i]!.score { best[i] = candidate }
            }
        }

        guard best[n] != nil else { return nil }
        var pieces: [String] = []
        var i = n
        while i > 0, let step = best[i] {
            pieces.append(String(chars[step.start..<i]))
            i = step.start
        }
        return pieces.reversed()
    }

    /// Glued fragments get harvested as if they were words ("inthe",
    /// "stockprices") and then win segmentations. Drop any entry that scores
    /// better split into other entries.
    private static func dropGluedEntries(from counts: [String: Int]) -> [String: Int] {
        let total = Double(max(counts.values.reduce(0, +), 1))
        var result = counts
        let repair = TextRepair(lexicon: counts, totalWords: total)
        for (word, count) in counts where word.count >= Self.minRunLength {
            guard let pieces = repair.segment(word, allowDictionary: false), pieces.count > 1 else {
                continue
            }
            let split = pieces.reduce(0.0) { $0 + log(Double(counts[$1.lowercased()] ?? 1) / total) }
            if split > log(Double(count) / total) { result[word] = nil }
        }
        return result
    }

    private init(lexicon: [String: Int], totalWords: Double) {
        self.lexicon = lexicon
        self.totalWords = totalWords
    }

    // MARK: - System dictionary

    /// Memoised across a document — the segmenter asks about the same
    /// substrings over and over, and each miss is comparatively expensive.
    private static let cache = DictionaryCache()

    private static func dictionaryKnows(_ word: String) -> Bool {
        cache.knows(word)
    }

    private final class DictionaryCache: @unchecked Sendable {
        private var known: [String: Bool] = [:]
        private let lock = NSLock()
        #if canImport(UIKit)
        private let checker = UITextChecker()
        #endif

        func knows(_ word: String) -> Bool {
            lock.lock()
            if let cached = known[word] { lock.unlock(); return cached }
            lock.unlock()

            let result = lookUp(word)
            lock.lock()
            known[word] = result
            lock.unlock()
            return result
        }

        private func lookUp(_ word: String) -> Bool {
            #if canImport(UIKit)
            let range = NSRange(location: 0, length: (word as NSString).length)
            let misspelled = checker.rangeOfMisspelledWord(
                in: word, range: range, startingAt: 0, wrap: false, language: "en_US")
            return misspelled.location == NSNotFound
            #elseif canImport(AppKit)
            let misspelled = NSSpellChecker.shared.checkSpelling(
                of: word, startingAt: 0, language: "en", wrap: false,
                inSpellDocumentWithTag: 0, wordCount: nil)
            return misspelled.location == NSNotFound
            #else
            return false
            #endif
        }
    }
}
