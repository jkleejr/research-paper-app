import SwiftUI

struct HomeView: View {
    @Environment(PaperStore.self) private var store
    @Environment(PlayerService.self) private var player
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var showingReader = false
    @State private var showingKeySetup = false
    @State private var importError: String?
    /// Mirrors the Keychain so the banner reacts to the key being added or removed.
    @State private var hasKey = AppConfig.geminiAPIKey != nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !hasKey { keyBanner }
                if store.papers.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
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
                        showingImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                MiniPlayerView { showingReader = true }
            }
            .task {
                // Offer the key screen once; after that the banner carries the
                // prompt, so declining doesn't mean a sheet on every launch.
                if !hasKey && !UserDefaults.standard.bool(forKey: "didOfferKeySetup") {
                    UserDefaults.standard.set(true, forKey: "didOfferKeySetup")
                    showingKeySetup = true
                }
                store.resumeUnfinished()
            }
            .sheet(isPresented: $showingKeySetup) {
                APIKeySetupView(cancelTitle: "Not Now")
            }
            .onChange(of: showingKeySetup) { refreshKeyState() }
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

    /// Papers can be imported and read without a key, but nothing can be
    /// cleaned up or narrated — say so up front instead of failing later.
    private var keyBanner: some View {
        Button {
            showingKeySetup = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add your Gemini API key")
                        .font(.subheadline.weight(.semibold))
                    Text("Needed to turn papers into audio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
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
