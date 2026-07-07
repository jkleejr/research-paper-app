import SwiftUI

struct HomeView: View {
    @Environment(PaperStore.self) private var store
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var importError: String?

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
                        showingImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                store.resumeUnfinished()
            }
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

    private var paperList: some View {
        List {
            ForEach(store.papers) { paper in
                NavigationLink(value: paper.id) {
                    PaperCardView(paper: paper)
                }
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
