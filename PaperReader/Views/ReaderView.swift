import SwiftUI

/// Full-screen reader: script text with the currently spoken sentence
/// highlighted and kept in view, playback controls at the bottom.
struct ReaderView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss

    /// Turned off when the user scrolls manually; a pill offers to re-enable.
    @State private var autoScroll = true

    var body: some View {
        Group {
            if let paper = player.paper {
                sentenceScroll(paper)
            } else {
                VStack {
                    Spacer()
                    Text("Nothing playing")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemBackground))
        // Floating glass chrome; the script text scrolls underneath it.
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) {
            PlayerControlsView()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
    }

    private var topBar: some View {
        HStack {
            Text(player.paper?.title ?? "")
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCard(in: Capsule())
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .glassCard(in: Circle(), interactive: true)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(alignment: .top) { statusBarScrim }
    }

    /// Script text scrolling under the chrome used to run straight through the
    /// clock and battery. This covers the status bar solidly and fades out level
    /// with the title, so the chrome still floats over the script below it.
    private var statusBarScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Color(.systemBackground), location: 0),
                .init(color: Color(.systemBackground), location: 0.7),
                .init(color: Color(.systemBackground).opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private func sentenceScroll(_ paper: Paper) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(paper.sentences) { sentence in
                        SentenceView(sentence: sentence,
                                     isCurrent: sentence.index == player.currentSentenceIndex)
                            .id(sentence.index)
                            .onTapGesture {
                                player.seek(toSentence: sentence.index)
                                autoScroll = true
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .simultaneousGesture(
                DragGesture().onChanged { _ in autoScroll = false }
            )
            .onChange(of: player.currentSentenceIndex) { _, newIndex in
                guard autoScroll else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(player.currentSentenceIndex, anchor: .center)
            }
            .overlay(alignment: .bottom) {
                if !autoScroll {
                    Button {
                        autoScroll = true
                        withAnimation {
                            proxy.scrollTo(player.currentSentenceIndex, anchor: .center)
                        }
                    } label: {
                        Label("Follow along", systemImage: "text.line.first.and.arrowtriangle.forward")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .glassCard(in: Capsule(), interactive: true)
                    .padding(.bottom, 12)
                }
            }
        }
    }
}

private struct SentenceView: View {
    let sentence: ScriptSentence
    let isCurrent: Bool

    var body: some View {
        Text(sentence.text)
            .font(.system(.body, design: .serif))
            .lineSpacing(5)
            .foregroundStyle(isCurrent ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrent ? Color.accentColor.opacity(0.15) : .clear)
            )
            .animation(.easeInOut(duration: 0.25), value: isCurrent)
    }
}
