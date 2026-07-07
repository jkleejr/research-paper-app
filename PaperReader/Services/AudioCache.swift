import Foundation

/// Synthesized audio chunks on disk, one WAV per ChunkPlan.
/// WAV (not raw PCM) so files are self-describing and AVAudioFile can read them.
enum AudioCache {
    static func url(paperID: UUID, chunkIndex: Int) -> URL {
        PaperStore.audioDirectoryURL(for: paperID)
            .appendingPathComponent(String(format: "chunk-%04d.wav", chunkIndex))
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

        try wav.write(to: url(paperID: paperID, chunkIndex: chunkIndex), options: .atomic)
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

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
