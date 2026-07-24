import Foundation

enum AppConfig {
    // Pinned old models get blocked for newly created Google projects
    // ("no longer available to new users"), so track the latest generation.
    static let textModel = "gemini-flash-latest"
    static let ttsModel = "gemini-3.1-flash-tts-preview"
    /// Narration voice for TTS; user-selectable in Settings. Applies to newly
    /// generated audio — already-cached chunks keep the voice they were made with.
    static var ttsVoice: String {
        get { UserDefaults.standard.string(forKey: "ttsVoice") ?? "Kore" }
        set { UserDefaults.standard.set(newValue, forKey: "ttsVoice") }
    }

    /// Curated prebuilt Gemini voices suited to reading papers aloud,
    /// with Google's style descriptors.
    static let voiceOptions: [(name: String, style: String)] = [
        ("Kore", "Firm"),
        ("Charon", "Informative"),
        ("Iapetus", "Clear"),
        ("Sulafat", "Warm"),
        ("Achernar", "Soft"),
        ("Schedar", "Even"),
        ("Gacrux", "Mature"),
        ("Zephyr", "Bright"),
    ]
    static let apiBase = "https://generativelanguage.googleapis.com/v1beta"

    /// The user's Gemini API key from the Keychain. Nil until they add one in Settings.
    static var geminiAPIKey: String? {
        APIKeyStore.load()
    }
}
