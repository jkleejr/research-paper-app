import SwiftUI

struct PaperCardView: View {
    @Environment(PlayerService.self) private var player
    @Environment(PaperStore.self) private var store
    let paper: Paper

    private var isCurrentAndPlaying: Bool {
        player.currentPaperID == paper.id && player.isPlaying
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(paper.title)
                    .font(.headline)
                    .lineLimit(2)
                statusLine
                if paper.status == .ready {
                    progressBar
                        .padding(.top, 2)
                }
            }
            Spacer()
            statusAccessory
        }
        .padding(.vertical, 6)
    }

    /// Listened fraction, tracking the live playhead when this paper is loaded.
    private var listenedFraction: Double {
        if player.currentPaperID == paper.id, !paper.sentences.isEmpty {
            return Double(player.currentSentenceIndex) / Double(max(paper.sentences.count - 1, 1))
        }
        return paper.listenedProgress
    }

    /// Two layers on one track: light tint = audio generated, solid = listened.
    private var progressBar: some View {
        GeometryReader { geo in
            let audio = paper.audioProgress
            let generated = audio.total == 0 ? 0 : Double(audio.done) / Double(audio.total)
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.tint.opacity(0.3))
                        .frame(width: geo.size.width * generated)
                }
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.tint)
                        .frame(width: geo.size.width * listenedFraction)
                }
                .clipShape(Capsule())
        }
        .frame(height: 4)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch paper.status {
        case .extracting:
            Text("Extracting text…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .imported:
            Text("\(paper.pageCount) pages · text extracted")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .generatingScript(let done, let total):
            Text("Cleaning section \(done + 1) of \(total)…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .ready:
            if paper.playback.completed {
                Text("Finished")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if paper.playback.sentenceIndex > 0, !paper.sentences.isEmpty {
                let pct = Int(Double(paper.playback.sentenceIndex) / Double(paper.sentences.count) * 100)
                Text("\(pct)% listened")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Ready to play")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var statusAccessory: some View {
        switch paper.status {
        case .extracting, .generatingScript:
            ProgressView()
        case .failed:
            Button {
                store.retry(paper.id)
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
        case .imported:
            Image(systemName: "doc.plaintext")
                .foregroundStyle(.secondary)
        case .ready:
            Button {
                if player.currentPaperID == paper.id {
                    player.toggle()
                } else {
                    player.load(paper.id)
                    player.play()
                }
            } label: {
                Image(systemName: isCurrentAndPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
        }
    }
}
