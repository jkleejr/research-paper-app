import Foundation

/// Synthesized audio chunks on disk, one WAV per ChunkPlan.
/// WAV (not raw PCM) so files are self-describing and AVAudioFile can read them.
enum AudioCache {
    /// Where synthesized audio is written for a chunk.
    private static func cacheURL(paperID: UUID, chunkIndex: Int) -> URL {
        PaperStore.audioDirectoryURL(for: paperID)
            .appendingPathComponent(String(format: "chunk-%04d.wav", chunkIndex))
    }

    /// Readable location of a chunk's audio. The bundled sample paper plays
    /// straight out of the app bundle, so it costs no extra storage.
    static func url(paperID: UUID, chunkIndex: Int) -> URL {
        let cached = cacheURL(paperID: paperID, chunkIndex: chunkIndex)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        return SampleLibrary.bundledAudioURL(paperID: paperID, chunkIndex: chunkIndex) ?? cached
    }

    static func exists(paperID: UUID, chunkIndex: Int) -> Bool {
        FileManager.default.fileExists(atPath: url(paperID: paperID, chunkIndex: chunkIndex).path)
    }

    /// Wraps 16-bit little-endian mono PCM in a WAV container and writes it.
    /// Returns the audio duration in seconds.
    @discardableResult
    static func saveWAV(pcm16Data: Data, sampleRate: Int, paperID: UUID, chunkIndex: Int) throws -> Double {
        let dir = PaperStore.audioDirectoryURL(for: paperID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var wav = Data(capacity: 44 + pcm16Data.count)
        let byteRate = UInt32(sampleRate * 2)          // mono, 2 bytes/sample
        let dataSize = UInt32(pcm16Data.count)

        wav.append(contentsOf: Array("RIFF".utf8))
        wav.appendLE(UInt32(36 + dataSize))
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8))
        wav.appendLE(UInt32(16))                        // fmt chunk size
        wav.appendLE(UInt16(1))                         // PCM
        wav.appendLE(UInt16(1))                         // mono
        wav.appendLE(UInt32(sampleRate))
        wav.appendLE(byteRate)
        wav.appendLE(UInt16(2))                         // block align
        wav.appendLE(UInt16(16))                        // bits per sample
        wav.append(contentsOf: Array("data".utf8))
        wav.appendLE(dataSize)
        wav.append(pcm16Data)

        try wav.write(to: cacheURL(paperID: paperID, chunkIndex: chunkIndex), options: .atomic)
        return Double(pcm16Data.count / 2) / Double(sampleRate)
    }

    static func totalBytes(paperID: UUID) -> Int64 {
        let dir = PaperStore.audioDirectoryURL(for: paperID)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { total, file in
            total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    static func clear(paperID: UUID) {
        try? FileManager.default.removeItem(at: PaperStore.audioDirectoryURL(for: paperID))
    }
}

extension Paper {
    /// True when a chunk's audio is both recorded as synthesized and on disk.
    /// Lives here rather than on the model so `Paper` stays free of the cache
    /// (the screenshot and sample tools compile it on its own).
    func hasAudio(forChunk index: Int) -> Bool {
        guard chunks.indices.contains(index),
              case .cached = chunks[index].audioStatus else { return false }
        return AudioCache.exists(paperID: id, chunkIndex: index)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
