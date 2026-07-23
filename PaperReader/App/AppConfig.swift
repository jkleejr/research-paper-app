import Foundation

enum AppConfig {
    // Pinned old models get blocked for newly created Google projects
    // ("no longer available to new users"), so track the latest generation.
    static let textModel = "gemini-flash-latest"
    static let ttsModel = "gemini-3.1-flash-tts-preview"
    static let ttsVoice = "Kore"
    static let apiBase = "https://generativelanguage.googleapis.com/v1beta"

    /// The user's Gemini API key from the Keychain. Nil until they add one in Settings.
    static var geminiAPIKey: String? {
        APIKeyStore.load()
    }
}
