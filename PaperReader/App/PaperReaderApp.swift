import SwiftUI

@main
struct PaperReaderApp: App {
    @State private var store = PaperStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
        }
    }
}
