import SwiftUI

/// Temporary M1 debug view: shows the raw extracted text per page.
/// Replaced by ReaderView once script generation and playback exist.
struct RawTextView: View {
    let paper: Paper

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let pages = paper.extractedPages {
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
            .padding()
        }
        .navigationTitle(paper.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
