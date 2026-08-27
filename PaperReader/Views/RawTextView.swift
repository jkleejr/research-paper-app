import SwiftUI

/// What a paper that isn't playable yet opens into: the failure and what to do
/// about it if processing failed, otherwise the cleaned script or the raw
/// extracted text so there's something to look at while the pipeline runs.
struct RawTextView: View {
    @Environment(PaperStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let paperID: UUID

    private var paper: Paper? { store.paper(id: paperID) }

    var body: some View {
        Group {
            if let paper {
                switch paper.status {
                case .failed(let message):
                    // The text is beside the point once processing failed — the
                    // reason is what the tap was for.
                    failureView(message)
                case .ready, .preparingAudio:
                    textScroll { scriptView(paper) }
                default:
                    textScroll { rawView(paper) }
                }
            }
        }
        .navigationTitle(paper?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func textScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding()
        }
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Process This Paper", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 12) {
                Text(message)
                    .textSelection(.enabled)
                if let hint = hint(for: message) {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        } actions: {
            Button("Try Again") {
                store.retry(paperID)
                // Back to the library, where the row shows processing progress.
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Plain-language next step for the failures a user can actually act on.
    private func hint(for message: String) -> String? {
        let text = message.lowercased()
        if text.contains("api key") || text.contains("401") || text.contains("403")
            || text.contains("permission") {
            return "Check your API key in Settings."
        }
        if text.contains("429") || text.contains("quota") || text.contains("rate limit") {
            return "Gemini is rate-limiting your key. Wait a minute, then try again."
        }
        if text.contains("billing") {
            return "Narration needs billing enabled on your Google account."
        }
        if text.contains("no text") || text.contains("ocr") {
            return "Paper Reader reads embedded PDF text, so image-only scans won't work."
        }
        return nil
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
