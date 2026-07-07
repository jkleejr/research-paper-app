import Foundation

/// Synthesizes one ChunkPlan's sentences into a cached WAV via Gemini TTS.
struct TTSService {
    let client: GeminiClient

    /// Kept short and imperative — the docs warn that vague framing can make the
    /// model read the instruction aloud.
    static let stylePrefix = "Read aloud in a calm, clear narrator voice: "

    struct Result {
        let duration: Double
        let sentenceDurations: [Double]
    }

    func synthesize(paperID: UUID, chunk: ChunkPlan, sentences: [ScriptSentence]) async throws -> Result {
        let chunkSentences = chunk.sentenceRange.map { sentences[$0] }
        let text = chunkSentences.map(\.text).joined(separator: " ")

        let audio = try await client.generateAudio(
            model: AppConfig.ttsModel,
            prompt: Self.stylePrefix + text,
            voiceName: AppConfig.ttsVoice
        )

        guard let pcm = Data(base64Encoded: audio.data) else {
            throw GeminiError.emptyResponse
        }
        let sampleRate = Self.sampleRate(fromMimeType: audio.mimeType)
        let duration = try AudioCache.saveWAV(pcm16Data: pcm, sampleRate: sampleRate,
                                              paperID: paperID, chunkIndex: chunk.index)

        // No timestamps from the API: apportion the (exact) chunk duration across
        // sentences proportionally to character count — accurate enough for
        // sentence-level highlighting.
        let charCounts = chunkSentences.map { Double($0.text.count) }
        let totalChars = charCounts.reduce(0, +)
        let sentenceDurations = charCounts.map { duration * $0 / max(totalChars, 1) }

        return Result(duration: duration, sentenceDurations: sentenceDurations)
    }

    /// "audio/L16;codec=pcm;rate=24000" -> 24000
    static func sampleRate(fromMimeType mimeType: String) -> Int {
        if let regex = try? Regex("rate=(\\d+)"),
           let match = mimeType.firstMatch(of: regex),
           let rateString = match[1].substring,
           let rate = Int(rateString) {
            return rate
        }
        return 24_000
    }
}
