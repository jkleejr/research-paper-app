import SwiftUI

/// Temporary pipeline-debug view: shows the cleaned script (sentence-segmented)
/// for ready papers, or the raw extracted text otherwise.
/// Replaced by ReaderView once playback exists.
struct RawTextView: View {
    @Environment(PaperStore.self) private var store
    let paperID: UUID

    private var paper: Paper? { store.paper(id: paperID) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let paper {
                    if paper.status == .ready {
                        scriptView(paper)
                    } else {
                        rawView(paper)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(paper?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func scriptView(_ paper: Paper) -> some View {
        Text("\(paper.sentences.count) sentences · \(paper.chunks.count) audio chunks")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
        ForEach(paper.sentences) { sentence in
            Text(sentence.text)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func rawView(_ paper: Paper) -> some View {
        if let pages = paper.extractedPages {
            Text("Raw extracted text (script not generated yet)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Page \(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(page)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        } else {
            Text("No text extracted yet.")
                .foregroundStyle(.secondary)
        }
    }
}
