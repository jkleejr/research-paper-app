import SwiftUI

@main
struct PaperReaderApp: App {
    @State private var store: PaperStore
    @State private var player: PlayerService

    init() {
        let client = GeminiClient()
        let store = PaperStore(client: client)
        let prefetcher = TTSPrefetcher(store: store, client: client)
        // Kick off full-paper audio synthesis as soon as a script is ready.
        store.onScriptReady = { prefetcher.synthesizeAll(paperID: $0) }
        _store = State(initialValue: store)
        _player = State(initialValue: PlayerService(store: store, prefetcher: prefetcher))
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(player)
        }
    }
}
