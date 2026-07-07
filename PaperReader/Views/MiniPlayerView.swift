import SwiftUI

/// Compact bar pinned above the home list while a paper is loaded.
/// Tapping it reopens the full reader.
struct MiniPlayerView: View {
    @Environment(PlayerService.self) private var player
    let openReader: () -> Void

    var body: some View {
        if let paper = player.paper {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(paper.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(statusText(now: context.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Spacer(minLength: 8)

                if player.isBuffering {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                }

                Button {
                    player.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { progressBar }
            .contentShape(Rectangle())
            .glassCard(in: RoundedRectangle(cornerRadius: 22), interactive: true)
            .onTapGesture(perform: openReader)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }

    private func statusText(now: Date) -> String {
        guard let paper = player.paper, !paper.sentences.isEmpty else { return "" }
        if player.isBuffering {
            if let remaining = player.bufferingRemainingSeconds(now: now), remaining > 2 {
                return "Generating audio… about \(remaining)s"
            }
            return "Generating audio… almost done"
        }
        return "Sentence \(player.currentSentenceIndex + 1) of \(paper.sentences.count)"
    }

    private var progressBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.accentColor.opacity(0.8))
                .frame(width: max(6, geo.size.width * player.progress), height: 3)
        }
        .frame(height: 3)
        .padding(.horizontal, 14)
        .padding(.bottom, 5)
    }
}
