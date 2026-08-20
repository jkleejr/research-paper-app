import Foundation
import NaturalLanguage
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum SentenceSegmenter {
    /// Split the cleaned script into sentences — the app's coordinate system for
    /// highlighting, audio chunking, and saved position.
    static func sentences(from script: String) -> [ScriptSentence] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = script

        var texts: [String] = []
        tokenizer.enumerateTokens(in: script.startIndex..<script.endIndex) { range, _ in
            let sentence = script[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                // Merge fragments (tokenizer artifacts like a stray "3.1", or
                // half a sentence orphaned by a page break upstream) into the
                // previous sentence. A fragment starting with a capital is a
                // heading like "Abstract" or "Introduction", which should stand
                // on its own rather than being glued onto the end of the title.
                let isContinuation = sentence.first.map { $0.isLowercase || $0.isNumber } ?? false
                // Length alone was too blunt a test: "tion was radical." is 17
                // characters, so a word split across pages sailed past a 15-char
                // cap and reached the reader as its own sentence. An unfinished
                // sentence before it is the reliable signal.
                let previousIsUnfinished = texts.last.map { !Self.endsSentence($0) } ?? false
                if isContinuation, (sentence.count < 15 || previousIsUnfinished),
                   let last = texts.indices.last {
                    texts[last] = Self.joined(texts[last], sentence)
                } else {
                    texts.append(sentence)
                }
            }
            return true
        }
        return texts.enumerated().map { ScriptSentence(index: $0.offset, text: $0.element) }
    }

    /// Reattaches a continuation, closing the gap when the break fell inside a
    /// word rather than between two.
    private static func joined(_ previous: String, _ continuation: String) -> String {
        // An explicit hyphen is the PDF telling us the word was broken.
        if previous.hasSuffix("-") {
            return String(previous.dropLast()) + continuation
        }
        // Without one, the tell is that the fragment is only a word once closed
        // up: "interpreta" + "tion" is a word, "tion" is not. A continuation
        // that already stands alone ("upon" + "reunification") keeps its space.
        if previous.last?.isLetter == true, continuation.first?.isLetter == true,
           let tail = previous.split(whereSeparator: { !$0.isLetter }).last,
           let head = continuation.split(whereSeparator: { !$0.isLetter }).first,
           !isWord(String(head)), isWord(String(tail) + String(head)) {
            return previous + continuation
        }
        return previous + " " + continuation
    }

    /// True when the text ends the way a finished sentence does.
    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return true }
        if ".!?".contains(last) { return true }
        // A closing quote or bracket still ends the sentence it wraps.
        if "\"'’”)]".contains(last) {
            return text.dropLast().last.map { ".!?".contains($0) } ?? false
        }
        return false
    }

    /// Spell-checker lookup, memoised: the same short fragments recur across a
    /// paper and each miss is comparatively expensive.
    private static let knownWords = WordCheck()

    private static func isWord(_ candidate: String) -> Bool {
        knownWords.knows(candidate)
    }

    private final class WordCheck: @unchecked Sendable {
        private var cache: [String: Bool] = [:]
        private let lock = NSLock()
        #if canImport(UIKit)
        private let checker = UITextChecker()
        #endif

        func knows(_ word: String) -> Bool {
            guard word.count > 1 else { return false }
            lock.lock()
            if let cached = cache[word] { lock.unlock(); return cached }
            lock.unlock()

            let result = lookUp(word)
            lock.lock()
            cache[word] = result
            lock.unlock()
            return result
        }

        private func lookUp(_ word: String) -> Bool {
            #if canImport(UIKit)
            let range = NSRange(location: 0, length: (word as NSString).length)
            return checker.rangeOfMisspelledWord(
                in: word, range: range, startingAt: 0, wrap: false,
                language: "en_US").location == NSNotFound
            #elseif canImport(AppKit)
            return NSSpellChecker.shared.checkSpelling(
                of: word, startingAt: 0, language: "en", wrap: false,
                inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
            #else
            return false
            #endif
        }
    }
}

enum ChunkPlanner {
    /// Group consecutive sentences into TTS-sized chunks (~600–900 chars).
    /// Small enough that character-proportional sentence timing stays accurate,
    /// large enough for natural prosody and few API calls.
    static func plan(for sentences: [ScriptSentence], targetChars: Int = 750) -> [ChunkPlan] {
        guard !sentences.isEmpty else { return [] }
        var plans: [ChunkPlan] = []
        var start = 0
        var chars = 0

        for sentence in sentences {
            let wouldBe = chars + sentence.text.count
            if chars > 0 && wouldBe > targetChars {
                plans.append(ChunkPlan(index: plans.count,
                                       sentenceRange: start...(sentence.index - 1),
                                       audioStatus: .none,
                                       sentenceDurations: nil))
                start = sentence.index
                chars = sentence.text.count
            } else {
                chars = wouldBe
            }
        }
        plans.append(ChunkPlan(index: plans.count,
                               sentenceRange: start...(sentences.count - 1),
                               audioStatus: .none,
                               sentenceDurations: nil))
        return plans
    }
}
