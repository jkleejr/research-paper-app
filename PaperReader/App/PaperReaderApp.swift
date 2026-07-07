import SwiftUI

@main
struct PaperReaderApp: App {
    @State private var store: PaperStore
    @State private var player: PlayerService

    init() {
        let client = GeminiClient()
        let store = PaperStore(client: client)
        _store = State(initialValue: store)
        _player = State(initialValue: PlayerService(store: store, client: client))
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(player)
        }
    }
}
