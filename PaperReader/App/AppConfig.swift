import Foundation

enum AppConfig {
    static let textModel = "gemini-2.5-flash"
    static let ttsModel = "gemini-2.5-flash-preview-tts"
    static let ttsVoice = "Kore"
    static let apiBase = "https://generativelanguage.googleapis.com/v1beta"

    /// Gemini API key injected from Secrets.xcconfig via Info.plist. Nil when unset.
    static var geminiAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
              !key.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return key.trimmingCharacters(in: .whitespaces)
    }
}
