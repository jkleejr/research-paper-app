import Foundation

enum AppConfig {
    static let textModel = "gemini-2.5-flash"
    static let ttsModel = "gemini-2.5-flash-preview-tts"
    static let ttsVoice = "Kore"
    static let apiBase = "https://generativelanguage.googleapis.com/v1beta"

    /// The user's Gemini API key from the Keychain. Nil until they add one in Settings.
    static var geminiAPIKey: String? {
        APIKeyStore.load()
    }
}
