import Foundation

/// The sample paper shipped inside the app bundle — a real excerpt with real
/// Gemini narration, generated once by a developer (see `Tools/sample/`).
///
/// It exists so a new user, and an App Review tester, can hear exactly what the
/// app does before going and getting an API key. It costs nothing at runtime:
/// every chunk is already synthesized, so the prefetcher never calls the API,
/// and no key ships in the binary.
enum SampleLibrary {
    /// Fixed by the generator so the app can recognise the sample.
    static let paperID = UUID(uuidString: "5A3B1E00-0000-4000-8000-5A3B1E000001")!

    /// Versioned: bumping the suffix reinstalls the sample after it changes.
    private static let installedKey = "didInstallSample.v1"
    private static let directory = "SampleLibrary"

    static func isSample(_ paperID: UUID) -> Bool { paperID == Self.paperID }

    /// Adds the sample to the library on first launch only. Deleting it is
    /// permanent — the flag stays set, so it doesn't reappear next launch.
    @MainActor
    static func installIfNeeded(into store: PaperStore) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: installedKey) else { return }
        // Set first: a malformed payload shouldn't retry forever on every launch.
        defaults.set(true, forKey: installedKey)

        guard let paper = bundledPaper() else { return }
        store.save(paper)
    }

    /// Audio is read straight out of the bundle rather than copied into
    /// Application Support, so the sample costs no extra storage.
    static func bundledAudioURL(paperID: UUID, chunkIndex: Int) -> URL? {
        guard isSample(paperID) else { return nil }
        let name = String(format: "chunk-%04d", chunkIndex)
        return Bundle.main.url(forResource: name, withExtension: "wav",
                               subdirectory: "\(directory)/audio")
    }

    private static func bundledPaper() -> Paper? {
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "json",
                                        subdirectory: directory),
              let data = try? Data(contentsOf: url),
              let paper = try? JSONDecoder().decode(Paper.self, from: data) else { return nil }
        return paper
    }
}
