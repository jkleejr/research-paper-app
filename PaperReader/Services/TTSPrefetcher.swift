import Foundation

/// Keeps a window of audio chunks synthesized ahead of the playhead.
/// Sequential synthesis (one request in flight) — friendly to free-tier rate limits.
@MainActor
final class TTSPrefetcher {
    private let store: PaperStore
    private let tts: TTSService

    /// Fired on the main actor whenever a chunk finishes synthesizing,
    /// so the player can resume if it was waiting on that chunk.
    var onChunkReady: ((UUID, Int) -> Void)?
    var onChunkFailed: ((UUID, Int, Error) -> Void)?

    private var task: Task<Void, Never>?
    private var targetPaperID: UUID?
    private var targetChunkIndex = 0
    private let windowSize = 3

    init(store: PaperStore, client: GeminiClient) {
        self.store = store
        self.tts = TTSService(client: client)
    }

    /// Re-centers the prefetch window. Restarts the worker if it moved.
    func ensureBuffered(paperID: UUID, around chunkIndex: Int) {
        let moved = targetPaperID != paperID || targetChunkIndex != chunkIndex
        targetPaperID = paperID
        targetChunkIndex = chunkIndex
        guard moved || task == nil || task!.isCancelled else { return }

        task?.cancel()
        task = Task { await run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        targetPaperID = nil
    }

    private func run() async {
        while !Task.isCancelled {
            guard let paperID = targetPaperID,
                  let next = nextUncachedIndex(paperID: paperID) else { return }

            guard var paper = store.paper(id: paperID) else { return }
            paper.chunks[next].audioStatus = .synthesizing
            store.save(paper)

            do {
                let chunk = paper.chunks[next]
                let result = try await tts.synthesize(paperID: paperID, chunk: chunk,
                                                      sentences: paper.sentences)
                guard !Task.isCancelled else { return }
                guard var updated = store.paper(id: paperID) else { return }
                updated.chunks[next].audioStatus = .cached(duration: result.duration)
                updated.chunks[next].sentenceDurations = result.sentenceDurations
                store.save(updated)
                onChunkReady?(paperID, next)
            } catch {
                guard !Task.isCancelled else { return }
                if var updated = store.paper(id: paperID) {
                    updated.chunks[next].audioStatus = .none
                    store.save(updated)
                }
                onChunkFailed?(paperID, next, error)
                return
            }
        }
    }

    /// First chunk in [target, target+window] that isn't cached on disk.
    private func nextUncachedIndex(paperID: UUID) -> Int? {
        guard let paper = store.paper(id: paperID), !paper.chunks.isEmpty else { return nil }
        let upper = min(targetChunkIndex + windowSize, paper.chunks.count - 1)
        guard targetChunkIndex <= upper else { return nil }
        for i in targetChunkIndex...upper {
            if case .cached = paper.chunks[i].audioStatus, AudioCache.exists(paperID: paperID, chunkIndex: i) {
                continue
            }
            return i
        }
        return nil
    }
}
