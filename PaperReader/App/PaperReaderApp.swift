import SwiftUI

@main
struct PaperReaderApp: App {
    @State private var store: PaperStore
    @State private var player: PlayerService

    init() {
        let client = GeminiClient()
        let store = PaperStore(client: client)
        let prefetcher = TTSPrefetcher(store: store, client: client)
        // Synthesize the opening chunk as soon as a script is done — the paper
        // isn't offered as ready until that audio exists, so playback starts
        // instantly; the rest generates on demand while listening.
        store.onWarmupNeeded = { prefetcher.warmup(paperID: $0) }
        let player = PlayerService(store: store, prefetcher: prefetcher)
        // Deleting a paper has to reach the two things holding work for it.
        store.onPaperDeleted = { [weak player] paperID in
            prefetcher.forget(paperID: paperID)
            player?.unload(paperID: paperID)
        }
        _store = State(initialValue: store)
        _player = State(initialValue: player)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(player)
        }
    }
}
