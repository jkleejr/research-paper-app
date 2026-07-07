import Foundation

/// Synthesizes paper audio in the background. Two demand sources feed one
/// sequential worker (a single request in flight — friendly to rate limits):
/// full-paper jobs enqueued when a script finishes generating, and a playhead
/// window that always takes priority so taps and seeks start playing as soon
/// as possible. Once the window is satisfied the worker keeps going until the
/// whole paper is on disk.
@MainActor
final class TTSPrefetcher {
    private let store: PaperStore
    private let tts: TTSService

    /// Fired on the main actor whenever a chunk finishes synthesizing,
    /// so the player can resume if it was waiting on that chunk.
    var onChunkReady: ((UUID, Int) -> Void)?
    var onChunkFailed: ((UUID, Int, Error) -> Void)?

    private var task: Task<Void, Never>?
    /// Papers queued for full synthesis, oldest first.
    private var fullJobs: [UUID] = []
    /// Chunks near this position jump the queue.
    private var playhead: (paperID: UUID, chunkIndex: Int)?
    private let windowSize = 3
    private let maxAttempts = 3

    init(store: PaperStore, client: GeminiClient) {
        self.store = store
        self.tts = TTSService(client: client)
    }

    /// Enqueue full-paper synthesis (script just became ready, or app relaunch
    /// found a paper with missing audio).
    func synthesizeAll(paperID: UUID) {
        if !fullJobs.contains(paperID) { fullJobs.append(paperID) }
        kick()
    }

    /// Re-centers the playhead priority window. The playhead's paper is also
    /// promoted to a full job so it finishes even if it was never enqueued.
    func ensureBuffered(paperID: UUID, around chunkIndex: Int) {
        playhead = (paperID, chunkIndex)
        if !fullJobs.contains(paperID) { fullJobs.append(paperID) }
        kick()
    }

    /// Clears playhead priority (player unloaded). Queued full-paper jobs
    /// keep running to completion.
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
        // 1. The playhead window, then the rest of the playhead's paper
        //    (forward from the window, then anything skipped before it).
        if let (paperID, cursor) = playhead,
           let paper = store.paper(id: paperID), !paper.chunks.isEmpty {
            let last = paper.chunks.count - 1
            let upper = min(cursor + windowSize, last)
            if cursor <= upper, let i = firstUncached(in: paper, range: cursor...upper) {
                return WorkItem(paperID: paperID, chunkIndex: i)
            }
            if upper < last, let i = firstUncached(in: paper, range: (upper + 1)...last) {
                return WorkItem(paperID: paperID, chunkIndex: i)
            }
            if cursor > 0, let i = firstUncached(in: paper, range: 0...(cursor - 1)) {
                return WorkItem(paperID: paperID, chunkIndex: i)
            }
        }

        // 2. Queued full-paper jobs, oldest first. Finished or deleted papers
        //    fall out of the queue here.
        while let paperID = fullJobs.first {
            if let paper = store.paper(id: paperID), !paper.chunks.isEmpty,
               let i = firstUncached(in: paper, range: 0...(paper.chunks.count - 1)) {
                return WorkItem(paperID: paperID, chunkIndex: i)
            }
            fullJobs.removeFirst()
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

        // Out of retries: reset the chunk and park this paper so the worker
        // doesn't spin. Re-opening the paper (or relaunching) re-enqueues it.
        if var updated = store.paper(id: paperID) {
            updated.chunks[chunkIndex].audioStatus = .none
            store.save(updated)
        }
        fullJobs.removeAll { $0 == paperID }
        if playhead?.paperID == paperID { playhead = nil }
        if let lastError { onChunkFailed?(paperID, chunkIndex, lastError) }
    }
}
