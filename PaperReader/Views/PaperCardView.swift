import SwiftUI

struct PaperCardView: View {
    @Environment(PlayerService.self) private var player
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
            }
            Spacer()
            statusAccessory
        }
        .padding(.vertical, 6)
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
            let audio = paper.audioProgress
            if audio.done < audio.total {
                Text("Generating audio · \(Int(Double(audio.done) / Double(audio.total) * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if paper.playback.completed {
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
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
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
