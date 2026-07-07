import Foundation

struct Paper: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var originalFilename: String
    var addedAt: Date
    var status: PaperStatus
    var pageCount: Int
    /// Raw per-page text from PDFKit, kept so script generation can resume/re-run.
    var extractedPages: [String]?
    /// Per-chunk LLM cleanup results; nil entry = chunk not yet processed (resume support).
    var cleanedChunks: [String?]?
    var sentences: [ScriptSentence]
    var chunks: [ChunkPlan]
    var playback: PlaybackState

    /// Synthesized-audio progress in chunks: (cached, total).
    var audioProgress: (done: Int, total: Int) {
        let done = chunks.count { chunk in
            if case .cached = chunk.audioStatus { return true }
            return false
        }
        return (done, chunks.count)
    }

    init(id: UUID = UUID(), title: String, originalFilename: String) {
        self.id = id
        self.title = title
        self.originalFilename = originalFilename
        self.addedAt = Date()
        self.status = .extracting
        self.pageCount = 0
        self.extractedPages = nil
        self.cleanedChunks = nil
        self.sentences = []
        self.chunks = []
        self.playback = PlaybackState()
    }
}

enum PaperStatus: Codable, Equatable {
    /// Text extracted, script not yet generated.
    case imported
    case extracting
    case generatingScript(done: Int, total: Int)
    /// Script ready — playable.
    case ready
    case failed(String)

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct ScriptSentence: Codable, Equatable, Identifiable {
    let index: Int
    let text: String
    var id: Int { index }
}

/// Maps a contiguous run of sentences to one synthesized audio file.
struct ChunkPlan: Codable, Equatable {
    let index: Int
    let sentenceRange: ClosedRange<Int>
    var audioStatus: AudioStatus
    /// Estimated seconds per sentence within this chunk (character-proportional).
    var sentenceDurations: [Double]?
}

enum AudioStatus: Codable, Equatable {
    case none
    case synthesizing
    case cached(duration: Double)
}

struct PlaybackState: Codable, Equatable {
    var sentenceIndex: Int = 0
    var completed: Bool = false
}
