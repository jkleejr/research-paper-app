import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// Single source of truth for playback, shared by the home mini-player, paper
/// cards, and the reader screen.
///
/// Position model: chunk boundaries are exact (schedule-completion callbacks fire
/// when a chunk's audio has fully played), and position inside a chunk is
/// interpolated from wall-clock playing time × playback rate. Boundaries re-sync
/// every chunk, so interpolation error can't accumulate — well within
/// sentence-level highlighting accuracy.
@MainActor
@Observable
final class PlayerService {
    private(set) var currentPaperID: UUID?
    private(set) var isPlaying = false
    /// True when the playhead reached a chunk whose audio isn't synthesized yet.
    private(set) var isBuffering = false
    private(set) var currentSentenceIndex = 0
    private(set) var playbackError: String?

    /// What the narration speed is allowed to be, whether picked from the menu
    /// or typed in. Past 2× the voice is hard to follow, and slower than 0.75×
    /// it drags without being any easier to follow.
    static let rateRange: ClosedRange<Float> = 0.75...2.0

    /// Any speed in `rateRange`, not just the menu's presets. Values outside it
    /// are clamped rather than refused, so a typed 3 lands on 2×.
    var playbackRate: Float {
        didSet {
            let clamped = Self.clamped(playbackRate)
            // Assigning here doesn't re-run didSet, so the lines below still see
            // (and store) the clamped value.
            if clamped != playbackRate { playbackRate = clamped }
            UserDefaults.standard.set(playbackRate, forKey: "playbackRate")
            applyRate()
            updateNowPlaying()
        }
    }

    static func clamped(_ rate: Float) -> Float {
        min(max(rate, rateRange.lowerBound), rateRange.upperBound)
    }

    /// 0...1 across the whole paper, by sentence position.
    var progress: Double {
        // A single-sentence paper would divide by zero, and the NaN that comes
        // out of it traps the moment anything converts it to an Int.
        guard let paper, paper.sentences.count > 1 else { return 0 }
        return Double(currentSentenceIndex) / Double(paper.sentences.count - 1)
    }

    /// Whole percent listened — what the players label themselves with.
    var percentListened: Int { Int((progress * 100).rounded()) }

    var paper: Paper? {
        currentPaperID.flatMap { store.paper(id: $0) }
    }

    /// Rough seconds until the chunk the playhead is waiting on becomes
    /// playable, from the prefetcher's learned synthesis speed. Negative once
    /// the estimate is exceeded (retries); nil when not buffering.
    func bufferingRemainingSeconds(now: Date = Date()) -> Int? {
        guard isBuffering, let paper, paper.chunks.indices.contains(currentChunkIndex) else { return nil }
        let ours = prefetcher.estimatedSeconds(forChars: paper.charCount(ofChunk: currentChunkIndex))
        guard let job = prefetcher.activeJob else {
            return Int(ours.rounded(.up))
        }
        let jobRemaining = job.estimatedDuration - now.timeIntervalSince(job.startedAt)
        if job.paperID == paper.id && job.chunkIndex == currentChunkIndex {
            return Int(jobRemaining.rounded(.up))
        }
        // Something else is in flight; our chunk queues behind it.
        return Int((max(jobRemaining, 0) + ours).rounded(.up))
    }

    private let store: PaperStore
    private let prefetcher: TTSPrefetcher

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var engineConfigured = false

    // Playhead bookkeeping (see position model above).
    private var currentChunkIndex = 0
    private var contentElapsedInChunk: Double = 0
    private var lastTick: Date?
    private var scheduledAheadChunk: Int?
    /// True while the player node has (possibly paused) buffers queued.
    private var hasScheduledQueue = false
    /// Invalidates in-flight completion callbacks after stop/seek/load.
    private var generation = 0

    private var tickTimer: Timer?
    private var lastPersist = Date.distantPast

    init(store: PaperStore, prefetcher: TTSPrefetcher) {
        self.store = store
        self.prefetcher = prefetcher
        let saved = UserDefaults.standard.float(forKey: "playbackRate")
        self.playbackRate = saved == 0 ? 1.0 : Self.clamped(saved)

        prefetcher.onChunkReady = { [weak self] paperID, chunkIndex in
            self?.chunkBecameReady(paperID: paperID, chunkIndex: chunkIndex)
        }
        prefetcher.onChunkFailed = { [weak self] paperID, _, error in
            guard let self, self.currentPaperID == paperID else { return }
            self.playbackError = error.localizedDescription
        }

        configureRemoteCommands()
        observeSessionNotifications()
    }

    // MARK: - Public controls

    func load(_ paperID: UUID) {
        guard let target = store.paper(id: paperID), target.status == .ready else { return }
        if currentPaperID == paperID { return }

        stopPlayback(persist: true)
        currentPaperID = paperID
        playbackError = nil
        let startSentence = target.playback.completed ? 0 : target.playback.sentenceIndex
        moveTo(sentence: startSentence)
    }

    func play() {
        guard let paper else { return }
        playbackError = nil
        configureEngineIfNeeded()
        configureAudioSession()

        guard chunkIsPlayable(currentChunkIndex, in: paper) else {
            enterBuffering()
            return
        }
        if !scheduleFromCurrentPosition() { return }
        playerNode.play()
        isPlaying = true
        isBuffering = false
        startTicking()
        prefetcher.ensureBuffered(paperID: paper.id, around: currentChunkIndex)
        updateNowPlaying()
    }

    func pause() {
        guard isPlaying else { return }
        tick()  // fold in the last partial interval before pausing
        playerNode.pause()
        isPlaying = false
        stopTicking()
        persistPosition(force: true)
        updateNowPlaying()
    }

    func toggle() {
        if isPlaying { pause() } else if isBuffering { enterBuffering() } else { resumeOrPlay() }
    }

    private func resumeOrPlay() {
        // playerNode.pause() keeps its scheduled buffers, so resuming is cheap;
        // after a seek/stop the queue is empty and play() rebuilds it.
        if hasScheduledQueue {
            configureAudioSession()
            playerNode.play()
            isPlaying = true
            startTicking()
            updateNowPlaying()
        } else {
            play()
        }
    }

    func seek(toSentence index: Int) {
        guard let paper, !paper.sentences.isEmpty else { return }
        let clamped = max(0, min(index, paper.sentences.count - 1))
        let wasPlaying = isPlaying
        stopPlayback(persist: false)
        moveTo(sentence: clamped)
        persistPosition(force: true)
        updateNowPlaying()
        if wasPlaying { play() } else if !chunkIsPlayable(currentChunkIndex, in: paper) {
            prefetcher.ensureBuffered(paperID: paper.id, around: currentChunkIndex)
        }
    }

    func skip(sentences delta: Int) {
        seek(toSentence: currentSentenceIndex + delta)
    }

    /// X button on the mini-player: stop and unload.
    func dismiss() {
        stopPlayback(persist: true)
        prefetcher.stop()
        currentPaperID = nil
        currentSentenceIndex = 0
        updateNowPlaying()
    }

    // MARK: - Scheduling

    private func moveTo(sentence index: Int) {
        guard let paper else { return }
        currentSentenceIndex = index
        currentChunkIndex = paper.chunks.firstIndex { $0.sentenceRange.contains(index) } ?? 0
        contentElapsedInChunk = offsetSeconds(toSentence: index, inChunk: currentChunkIndex, paper: paper)
    }

    /// Schedules the current chunk from the current intra-chunk offset, plus the
    /// next chunk if it's ready. Returns false if the audio file couldn't be read.
    private func scheduleFromCurrentPosition() -> Bool {
        guard let paper else { return false }
        generation += 1
        scheduledAheadChunk = nil

        do {
            try scheduleChunk(currentChunkIndex, paper: paper, fromSeconds: contentElapsedInChunk)
            scheduleNextIfReady(after: currentChunkIndex, paper: paper)
            hasScheduledQueue = true
            return true
        } catch {
            playbackError = "Couldn't read cached audio: \(error.localizedDescription)"
            return false
        }
    }

    private func scheduleChunk(_ index: Int, paper: Paper, fromSeconds offset: Double) throws {
        let url = AudioCache.url(paperID: paper.id, chunkIndex: index)
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(offset * sampleRate)
        let remaining = AVAudioFrameCount(max(0, file.length - startFrame))
        guard remaining > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: remaining) else {
            // Zero frames left (offset at chunk end) — treat as instantly completed.
            chunkFinished(index, generation: generation)
            return
        }
        file.framePosition = startFrame
        try file.read(into: buffer)

        let gen = generation
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                self?.chunkFinished(index, generation: gen)
            }
        }
    }

    private func scheduleNextIfReady(after index: Int, paper: Paper) {
        let next = index + 1
        guard next < paper.chunks.count,
              scheduledAheadChunk == nil,
              chunkIsPlayable(next, in: paper) else { return }
        if (try? scheduleChunk(next, paper: paper, fromSeconds: 0)) != nil {
            scheduledAheadChunk = next
        }
    }

    private func chunkFinished(_ index: Int, generation gen: Int) {
        guard gen == generation, let paper, index == currentChunkIndex else { return }

        let next = index + 1
        if next >= paper.chunks.count {
            finishPaper()
            return
        }

        currentChunkIndex = next
        contentElapsedInChunk = 0
        currentSentenceIndex = paper.chunks[next].sentenceRange.lowerBound
        persistPosition(force: true)
        updateNowPlaying()
        prefetcher.ensureBuffered(paperID: paper.id, around: next)

        if scheduledAheadChunk == next {
            // Already playing the pre-scheduled buffer; top up the queue.
            scheduledAheadChunk = nil
            scheduleNextIfReady(after: next, paper: paper)
        } else if chunkIsPlayable(next, in: paper) {
            _ = scheduleFromCurrentPosition()
            playerNode.play()
        } else {
            enterBuffering()
        }
    }

    private func finishPaper() {
        guard var paper else { return }
        paper.playback.completed = true
        paper.playback.sentenceIndex = 0
        store.save(paper)
        stopPlayback(persist: false)
        currentSentenceIndex = paper.sentences.count - 1
        updateNowPlaying()
    }

    // MARK: - Buffering

    private func enterBuffering() {
        guard let paper else { return }
        playerNode.stop()
        generation += 1
        scheduledAheadChunk = nil
        hasScheduledQueue = false
        isPlaying = false
        isBuffering = true
        stopTicking()
        prefetcher.ensureBuffered(paperID: paper.id, around: currentChunkIndex)
    }

    private func chunkBecameReady(paperID: UUID, chunkIndex: Int) {
        guard currentPaperID == paperID else { return }
        if isBuffering && chunkIndex == currentChunkIndex {
            isBuffering = false
            play()
        } else if isPlaying, let paper, scheduledAheadChunk == nil, chunkIndex == currentChunkIndex + 1 {
            // The chunk we were about to run out of just landed — queue it.
            scheduleNextIfReady(after: currentChunkIndex, paper: paper)
        }
    }

    private func chunkIsPlayable(_ index: Int, in paper: Paper) -> Bool {
        paper.hasAudio(forChunk: index)
    }

    // MARK: - Playhead ticking

    private func startTicking() {
        lastTick = Date()
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
        lastTick = nil
    }

    private func tick() {
        guard isPlaying, let paper, let last = lastTick else { return }
        let now = Date()
        contentElapsedInChunk += now.timeIntervalSince(last) * Double(playbackRate)
        lastTick = now
        updateSentenceIndex(paper: paper)
        persistPosition(force: false)
    }

    private func updateSentenceIndex(paper: Paper) {
        guard paper.chunks.indices.contains(currentChunkIndex) else { return }
        let chunk = paper.chunks[currentChunkIndex]
        guard let durations = chunk.sentenceDurations, !durations.isEmpty else {
            currentSentenceIndex = chunk.sentenceRange.lowerBound
            return
        }
        var remaining = contentElapsedInChunk
        for (offset, duration) in durations.enumerated() {
            remaining -= duration
            if remaining < 0 {
                currentSentenceIndex = chunk.sentenceRange.lowerBound + offset
                return
            }
        }
        currentSentenceIndex = chunk.sentenceRange.upperBound
    }

    private func offsetSeconds(toSentence index: Int, inChunk chunkIndex: Int, paper: Paper) -> Double {
        guard paper.chunks.indices.contains(chunkIndex),
              let durations = paper.chunks[chunkIndex].sentenceDurations else { return 0 }
        let chunk = paper.chunks[chunkIndex]
        let position = index - chunk.sentenceRange.lowerBound
        return durations.prefix(max(0, position)).reduce(0, +)
    }

    // MARK: - Lock screen / Control Center

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.resumeOrPlay() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.toggle() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [1]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skip(sentences: 1) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [1]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skip(sentences: -1) }
            return .success
        }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let paper else {
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: paper.title,
            MPMediaItemPropertyArtist: "Paper Reader",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0,
        ]
        // Sentence position doubles as track progress; durations are only
        // exact for synthesized chunks, so expose progress in sentence units.
        if !paper.sentences.isEmpty {
            info[MPNowPlayingInfoPropertyPlaybackProgress] = progress
        }
        center.nowPlayingInfo = info
    }

    /// Pause on interruptions (calls, Siri) and when headphones disconnect;
    /// resume only when the system says the interruption ended with a resume hint.
    private func observeSessionNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let userInfo = note.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
            Task { @MainActor in
                guard let self else { return }
                switch type {
                case .began:
                    self.pause()
                case .ended where shouldResume:
                    self.resumeOrPlay()
                default:
                    break
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
                  reason == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.pause() }
        }
    }

    // MARK: - Engine / session

    private func configureEngineIfNeeded() {
        guard !engineConfigured else { return }
        engine.attach(playerNode)
        engine.attach(timePitch)
        // 24kHz mono float32 matches Gemini TTS output; AVAudioFile converts
        // WAV int16 to float on read, and the engine resamples to hardware rate.
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)
        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        applyRate()
        engine.prepare()
        engineConfigured = true
    }

    private func applyRate() {
        timePitch.rate = playbackRate
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            if !engine.isRunning { try engine.start() }
        } catch {
            playbackError = "Audio engine failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Teardown / persistence

    private func stopPlayback(persist: Bool) {
        if isPlaying { tick() }
        generation += 1
        playerNode.stop()
        scheduledAheadChunk = nil
        hasScheduledQueue = false
        isPlaying = false
        isBuffering = false
        stopTicking()
        if persist { persistPosition(force: true) }
    }

    private func persistPosition(force: Bool) {
        guard force || Date().timeIntervalSince(lastPersist) > 5 else { return }
        guard var paper else { return }
        lastPersist = Date()
        paper.playback.sentenceIndex = currentSentenceIndex
        paper.playback.completed = false
        store.save(paper)
    }
}
