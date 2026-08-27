import SwiftUI

struct PlayerControlsView: View {
    @Environment(PlayerService.self) private var player

    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var isTypingSpeed = false
    @State private var typedSpeed = ""

    private static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(spacing: 10) {
            statusLine
            scrubber
            HStack {
                speedMenu
                Spacer()
                Button { player.skip(sentences: -1) } label: {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                }
                Spacer()
                playPauseButton
                Spacer()
                Button { player.skip(sentences: 1) } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                Spacer()
                // Balances the speed menu so play/pause stays centered.
                Color.clear.frame(width: 54, height: 1)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .glassCard(in: RoundedRectangle(cornerRadius: 28))
        .alert("Narration Speed", isPresented: $isTypingSpeed) {
            TextField("1.0", text: $typedSpeed)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") { applyTypedSpeed() }
        } message: {
            Text("Enter any speed from \(label(for: PlayerService.rateRange.lowerBound))"
                 + " to \(label(for: PlayerService.rateRange.upperBound)).")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if player.isBuffering {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(bufferingLabel(now: context.date))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                }
            }
        } else if let error = player.playbackError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .lineLimit(2)
                .padding(.horizontal)
        }
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubPosition : player.progress },
                    set: { scrubPosition = $0 }
                ),
                in: 0...1
            ) { editing in
                if editing {
                    scrubPosition = player.progress
                    isScrubbing = true
                } else {
                    isScrubbing = false
                    if let count = player.paper?.sentences.count, count > 1 {
                        player.seek(toSentence: Int((scrubPosition * Double(count - 1)).rounded()))
                    }
                }
            }
            bufferedBar
            HStack {
                Text(sentenceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 24)
    }

    /// Thin tint showing how far ahead audio has been synthesized.
    private var bufferedBar: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 1)
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.tertiary)
                        .frame(width: geo.size.width * bufferedFraction)
                }
        }
        .frame(height: 2)
    }

    private var bufferedFraction: Double {
        guard let paper = player.paper, !paper.sentences.isEmpty else { return 0 }
        var lastCoveredSentence = -1
        for chunk in paper.chunks {
            guard case .cached = chunk.audioStatus else { break }
            lastCoveredSentence = chunk.sentenceRange.upperBound
        }
        return Double(lastCoveredSentence + 1) / Double(paper.sentences.count)
    }

    private var sentenceLabel: String {
        guard let paper = player.paper, !paper.sentences.isEmpty else { return "" }
        return "Sentence \(player.currentSentenceIndex + 1) of \(paper.sentences.count)"
    }

    private var playPauseButton: some View {
        Button { player.toggle() } label: {
            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 52))
        }
        .disabled(player.paper == nil)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(menuSpeeds, id: \.self) { speed in
                Button {
                    player.playbackRate = speed
                } label: {
                    if player.playbackRate == speed {
                        Label(label(for: speed), systemImage: "checkmark")
                    } else {
                        Text(label(for: speed))
                    }
                }
            }
            Divider()
            Button("Custom Speed…") {
                typedSpeed = Self.speedText(for: player.playbackRate)
                isTypingSpeed = true
            }
        } label: {
            Text(label(for: player.playbackRate))
                .font(.subheadline.weight(.semibold))
                .frame(width: 54)
        }
    }

    /// The presets, plus a typed speed of the user's own so it still shows up
    /// ticked in the list rather than vanishing from it.
    private var menuSpeeds: [Float] {
        let current = player.playbackRate
        guard !Self.speeds.contains(current) else { return Self.speeds }
        return (Self.speeds + [current]).sorted()
    }

    private func applyTypedSpeed() {
        // A decimal pad hands back the locale's separator, which Float(_:) only
        // reads as a point.
        let typed = typedSpeed.replacingOccurrences(of: ",", with: ".")
        guard let value = Float(typed), value > 0 else { return }
        // Two decimals: finer than that is below what anyone can hear, and it
        // keeps the button's label short.
        player.playbackRate = (value * 100).rounded() / 100
    }

    private func label(for speed: Float) -> String {
        Self.speedText(for: speed) + "×"
    }

    /// "1", "1.1", "1.25" — no trailing zeros, no × so it can seed a text field.
    private static func speedText(for speed: Float) -> String {
        String(format: "%g", speed)
    }

    private func bufferingLabel(now: Date) -> String {
        guard let remaining = player.bufferingRemainingSeconds(now: now), remaining > 2 else {
            return "Generating audio… almost done"
        }
        return "Generating audio… about \(remaining)s"
    }
}
