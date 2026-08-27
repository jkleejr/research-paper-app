import Foundation

struct Paper: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var originalFilename: String
    var addedAt: Date
    var status: PaperStatus
    var pageCount: Int
    /// What kind of document this is, which decides how the text gets cleaned.
    /// Optional because papers imported before this existed have no value stored.
    var kind: DocumentKind?
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

    /// 0...1 listened fraction, from the persisted position.
    var listenedProgress: Double {
        guard !sentences.isEmpty else { return 0 }
        if playback.completed { return 1 }
        return Double(playback.sentenceIndex) / Double(max(sentences.count - 1, 1))
    }

    init(id: UUID = UUID(), title: String, originalFilename: String) {
        self.id = id
        self.title = title
        self.originalFilename = originalFilename
        self.addedAt = Date()
        self.status = .extracting
        self.pageCount = 0
        self.kind = nil
        self.extractedPages = nil
        self.cleanedChunks = nil
        self.sentences = []
        self.chunks = []
        self.playback = PlaybackState()
    }
}

// MARK: - Audio head start

extension Paper {
    /// How much audio is synthesized before a paper is offered as ready. Enough
    /// that tapping play starts sound at once, and short enough that the wait to
    /// get there is a minute's worth of narration, not the whole paper's.
    static let leadSeconds: Double = 60

    /// The chunk playback would start from right now.
    var resumeChunkIndex: Int {
        let sentence = playback.completed ? 0 : playback.sentenceIndex
        return chunks.firstIndex { $0.sentenceRange.contains(sentence) } ?? 0
    }

    /// The chunks making up that head start, always at least one. Chunks already
    /// synthesized count their measured duration, the rest an estimate, so the
    /// set settles on the real thing as audio lands.
    func leadChunks(from start: Int) -> [Int] {
        guard chunks.indices.contains(start) else { return [] }
        var indices: [Int] = []
        var seconds: Double = 0
        for index in start..<chunks.count {
            indices.append(index)
            seconds += estimatedAudioSeconds(ofChunk: index)
            if seconds >= Self.leadSeconds { break }
        }
        return indices
    }

    /// Characters of script in a chunk — what synthesis time scales with.
    func charCount(ofChunk index: Int) -> Int {
        guard chunks.indices.contains(index) else { return 0 }
        return chunks[index].sentenceRange.reduce(0) { count, i in
            sentences.indices.contains(i) ? count + sentences[i].text.count : count
        }
    }

    /// Exact once synthesized; before that, narration at roughly 150 words a
    /// minute over ~5.7 characters a word.
    private func estimatedAudioSeconds(ofChunk index: Int) -> Double {
        if case .cached(let duration) = chunks[index].audioStatus { return duration }
        return Double(charCount(ofChunk: index)) * 0.07
    }
}

/// A PDF's shape, which decides how its text has to be cleaned. A paper is prose
/// that only needs its furniture stripped; a deck is fragments that have to be
/// made speakable; a book or article sits in between.
enum DocumentKind: String, Codable, Equatable, CaseIterable {
    case researchPaper
    case slides
    case prose

    /// Used when the model can't be reached or answers with something unusable.
    /// Decks are the shape that stands out: many pages, little text on each, and
    /// lines that mostly don't end in sentence punctuation.
    static func heuristic(from pages: [String]) -> DocumentKind {
        let texts = pages.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !texts.isEmpty else { return .prose }

        let charsPerPage = texts.reduce(0) { $0 + $1.count } / texts.count
        let lines = texts
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return .prose }

        let finished = lines.count { line in line.last.map { ".!?:".contains($0) } ?? false }
        let finishedShare = Double(finished) / Double(lines.count)

        if texts.count >= 3, charsPerPage < 900, finishedShare < 0.5 { return .slides }

        let sample = texts.prefix(3).joined(separator: " ").lowercased()
        let paperMarkers = ["abstract", "et al.", "we propose", "related work", "this paper"]
        if paperMarkers.contains(where: sample.contains) { return .researchPaper }
        return .prose
    }
}

enum PaperStatus: Codable, Equatable {
    /// Text extracted, script not yet generated.
    case imported
    case extracting
    case generatingScript(done: Int, total: Int)
    /// Script done, synthesizing the head start of audio (see `Paper.leadSeconds`).
    case preparingAudio(done: Int, total: Int)
    /// Script and head start both done — tapping play makes sound immediately.
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
