import Foundation
import NaturalLanguage

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
                // Merge fragments (tokenizer artifacts like a stray "3.1" or "Dr.")
                // into the previous sentence.
                if sentence.count < 15, let last = texts.indices.last {
                    texts[last] += " " + sentence
                } else {
                    texts.append(sentence)
                }
            }
            return true
        }
        return texts.enumerated().map { ScriptSentence(index: $0.offset, text: $0.element) }
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
