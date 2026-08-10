import SwiftUI

struct HomeView: View {
    @Environment(PaperStore.self) private var store
    @Environment(PlayerService.self) private var player
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var showingReader = false
    @State private var showingKeySetup = false
    @State private var importError: String?
    /// Mirrors the Keychain, so the import button knows whether to ask for a key.
    @State private var hasKey = AppConfig.geminiAPIKey != nil
    /// Set when the key sheet was opened by tapping +, so saving a key continues
    /// on to the file picker instead of dead-ending.
    @State private var importAfterKeySetup = false

    var body: some View {
        NavigationStack {
            Group {
                if store.papers.isEmpty {
                    emptyState
                } else {
                    paperList
                }
            }
            .navigationTitle("My Papers")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        startImport()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                MiniPlayerView { showingReader = true }
            }
            .task {
                // No key gate on first launch — the bundled sample is playable
                // straight away, and the key is asked for when it's first needed.
                SampleLibrary.installIfNeeded(into: store)
                store.resumeUnfinished()
            }
            .sheet(isPresented: $showingKeySetup) {
                APIKeySetupView(cancelTitle: "Not Now")
            }
            .onChange(of: showingKeySetup) { _, isShowing in
                guard !isShowing else { return }
                refreshKeyState()
                // Saved a key on the way to importing — carry on to the picker.
                if hasKey && importAfterKeySetup { showingImporter = true }
                importAfterKeySetup = false
            }
            .onChange(of: showingSettings) { refreshKeyState() }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url):
                    store.importPDF(from: url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showingReader) {
                ReaderView()
            }
            .alert("Import Failed", isPresented: .init(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func refreshKeyState() {
        hasKey = AppConfig.geminiAPIKey != nil
    }

    /// Importing is the first thing that actually needs the API key, so that's
    /// where it's asked for — not behind a gate on first launch.
    private func startImport() {
        refreshKeyState()
        if hasKey {
            showingImporter = true
        } else {
            importAfterKeySetup = true
            showingKeySetup = true
        }
    }

    private var paperList: some View {
        List {
            ForEach(store.papers) { paper in
                row(for: paper)
                .swipeActions(edge: .leading) {
                    if paper.status.isFailed {
                        Button("Retry") { store.retry(paper.id) }
                            .tint(.orange)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    store.delete(store.papers[index])
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: UUID.self) { paperID in
            RawTextView(paperID: paperID)
        }
    }

    /// Ready papers open the reader; papers still in the pipeline open the
    /// raw-text debug view.
    @ViewBuilder
    private func row(for paper: Paper) -> some View {
        if paper.status == .ready {
            Button {
                player.load(paper.id)
                showingReader = true
            } label: {
                PaperCardView(paper: paper)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: paper.id) {
                PaperCardView(paper: paper)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Papers Yet", systemImage: "doc.text")
        } description: {
            Text("Tap + to add a research paper PDF from your files.")
        } actions: {
            Button("Add a Paper") { showingImporter = true }
                .buttonStyle(.borderedProminent)
        }
    }
}
