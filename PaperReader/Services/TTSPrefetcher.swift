import Foundation

/// Synthesizes paper audio on demand. Two demand sources feed one sequential
/// worker (a single request in flight — friendly to rate limits): the playhead
/// window, which keeps ~3 chunks buffered ahead of playback and always takes
/// priority, and warmup jobs, which cache a single chunk at a paper's resume
/// position when its script becomes ready so tapping play starts instantly.
/// Nothing else is generated — audio is paid for roughly as it's listened to.
@MainActor
final class TTSPrefetcher {
    private let store: PaperStore
    private let tts: TTSService

    /// Fired on the main actor whenever a chunk finishes synthesizing,
    /// so the player can resume if it was waiting on that chunk.
    var onChunkReady: ((UUID, Int) -> Void)?
    var onChunkFailed: ((UUID, Int, Error) -> Void)?

    private var task: Task<Void, Never>?
    /// Single-chunk jobs: cache the resume-position chunk of a freshly
    /// ready paper without disturbing the playhead window.
    private var warmups: [(paperID: UUID, chunkIndex: Int)] = []
    /// Chunks near this position jump the queue.
    private var playhead: (paperID: UUID, chunkIndex: Int)?
    private let windowSize = 3
    private let maxAttempts = 3

    init(store: PaperStore, client: GeminiClient) {
        self.store = store
        self.tts = TTSService(client: client)
    }

    /// Cache one chunk at the paper's saved position so playback starts
    /// instantly later. No-op if it's already cached.
    func warmup(paperID: UUID) {
        guard let paper = store.paper(id: paperID), !paper.chunks.isEmpty else { return }
        let sentence = paper.playback.completed ? 0 : paper.playback.sentenceIndex
        let chunkIndex = paper.chunks.firstIndex { $0.sentenceRange.contains(sentence) } ?? 0
        if !warmups.contains(where: { $0.paperID == paperID && $0.chunkIndex == chunkIndex }) {
            warmups.append((paperID, chunkIndex))
        }
        kick()
    }

    /// Re-centers the playhead priority window.
    func ensureBuffered(paperID: UUID, around chunkIndex: Int) {
        playhead = (paperID, chunkIndex)
        kick()
    }

    /// Clears playhead priority (player unloaded); synthesis stops once any
    /// pending warmups drain.
    func stop() {
        playhead = nil
    }

    private func kick() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    private func run() async {
        while !Task.isCancelled {
            guard let work = nextWorkItem() else { break }
            await synthesize(paperID: work.paperID, chunkIndex: work.chunkIndex)
        }
        task = nil
    }

    // MARK: - Scheduling

    private struct WorkItem {
        let paperID: UUID
        let chunkIndex: Int
    }

    private func nextWorkItem() -> WorkItem? {
        // 1. The playhead window.
        if let (paperID, cursor) = playhead,
           let paper = store.paper(id: paperID), !paper.chunks.isEmpty {
            let upper = min(cursor + windowSize, paper.chunks.count - 1)
            if cursor <= upper, let i = firstUncached(in: paper, range: cursor...upper) {
                return WorkItem(paperID: paperID, chunkIndex: i)
            }
        }

        // 2. Warmup jobs, oldest first; satisfied or stale entries drain here.
        while let job = warmups.first {
            if let paper = store.paper(id: job.paperID),
               paper.chunks.indices.contains(job.chunkIndex),
               firstUncached(in: paper, range: job.chunkIndex...job.chunkIndex) != nil {
                return WorkItem(paperID: job.paperID, chunkIndex: job.chunkIndex)
            }
            warmups.removeFirst()
        }
        return nil
    }

    private func firstUncached(in paper: Paper, range: ClosedRange<Int>) -> Int? {
        for i in range {
            if case .cached = paper.chunks[i].audioStatus,
               AudioCache.exists(paperID: paper.id, chunkIndex: i) {
                continue
            }
            return i
        }
        return nil
    }

    // MARK: - Synthesis

    private func synthesize(paperID: UUID, chunkIndex: Int) async {
        guard var paper = store.paper(id: paperID) else { return }
        paper.chunks[chunkIndex].audioStatus = .synthesizing
        store.save(paper)

        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                guard let current = store.paper(id: paperID) else { return }
                let result = try await tts.synthesize(paperID: paperID,
                                                      chunk: current.chunks[chunkIndex],
                                                      sentences: current.sentences)
                guard var updated = store.paper(id: paperID) else { return }
                updated.chunks[chunkIndex].audioStatus = .cached(duration: result.duration)
                updated.chunks[chunkIndex].sentenceDurations = result.sentenceDurations
                store.save(updated)
                onChunkReady?(paperID, chunkIndex)
                return
            } catch {
                lastError = error
                if Task.isCancelled { break }
                // Transient rate limits are the common failure; back off and retry.
                if attempt < maxAttempts {
                    try? await Task.sleep(for: .seconds(Double(attempt) * 3))
                }
            }
        }

        // Out of retries: reset the chunk and drop this paper's demand so the
        // worker doesn't spin. Playing or reopening the paper tries again.
        if var updated = store.paper(id: paperID) {
            updated.chunks[chunkIndex].audioStatus = .none
            store.save(updated)
        }
        warmups.removeAll { $0.paperID == paperID }
        if playhead?.paperID == paperID { playhead = nil }
        if let lastError { onChunkFailed?(paperID, chunkIndex, lastError) }
    }
}
