import Foundation

enum GeminiError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case emptyResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Gemini API key. Add yours in Settings."
        case .http(let status, let message):
            return "Gemini API error \(status): \(message)"
        case .emptyResponse:
            return "Gemini returned an empty response."
        case .network(let message):
            return "Network error: \(message)"
        }
    }
}

/// Thin REST client for the Gemini API, shared by text cleanup and TTS.
/// Owns retry/backoff so callers just await a result.
actor GeminiClient {
    struct Part: Codable {
        var text: String?
        var inlineData: InlineData?
    }

    struct InlineData: Codable {
        var mimeType: String
        var data: String
    }

    struct Content: Codable {
        var parts: [Part]
        var role: String?
    }

    struct GenerationConfig: Encodable {
        var responseMimeType: String?
        var responseModalities: [String]?
        var speechConfig: SpeechConfig?
    }

    struct SpeechConfig: Encodable {
        struct VoiceConfig: Encodable {
            struct PrebuiltVoiceConfig: Encodable { var voiceName: String }
            var prebuiltVoiceConfig: PrebuiltVoiceConfig
        }
        var voiceConfig: VoiceConfig
    }

    private struct Request: Encodable {
        var contents: [Content]
        var systemInstruction: Content?
        var generationConfig: GenerationConfig?
    }

    private struct Response: Decodable {
        struct Candidate: Decodable { var content: Content? }
        var candidates: [Candidate]?
        var error: APIError?
    }

    private struct APIError: Decodable {
        var code: Int?
        var message: String?
    }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        session = URLSession(configuration: config)
    }

    /// Text-in, text-out (script cleanup, title extraction).
    func generateText(model: String,
                      systemInstruction: String? = nil,
                      prompt: String,
                      responseMimeType: String? = nil) async throws -> String {
        let config = responseMimeType.map { GenerationConfig(responseMimeType: $0) }
        let parts = try await generate(model: model, systemInstruction: systemInstruction,
                                       prompt: prompt, generationConfig: config)
        let text = parts.compactMap(\.text).joined()
        guard !text.isEmpty else { throw GeminiError.emptyResponse }
        return text
    }

    /// Text-in, audio-out (TTS). Returns base64 audio data plus its mime type.
    func generateAudio(model: String, prompt: String, voiceName: String) async throws -> InlineData {
        let config = GenerationConfig(
            responseModalities: ["AUDIO"],
            speechConfig: .init(voiceConfig: .init(prebuiltVoiceConfig: .init(voiceName: voiceName)))
        )
        let parts = try await generate(model: model, systemInstruction: nil,
                                       prompt: prompt, generationConfig: config)
        guard let audio = parts.compactMap(\.inlineData).first else {
            throw GeminiError.emptyResponse
        }
        return audio
    }

    /// Cheap round-trip to confirm a key works before it's saved.
    func validate(apiKey: String) async throws {
        _ = try await generate(model: AppConfig.textModel, systemInstruction: nil,
                               prompt: "Reply with OK.", generationConfig: nil,
                               apiKeyOverride: apiKey)
    }

    // MARK: - Core request with retry

    private func generate(model: String,
                          systemInstruction: String?,
                          prompt: String,
                          generationConfig: GenerationConfig?,
                          apiKeyOverride: String? = nil) async throws -> [Part] {
        guard let apiKey = apiKeyOverride ?? AppConfig.geminiAPIKey else { throw GeminiError.missingAPIKey }

        var urlRequest = URLRequest(url: URL(string: "\(AppConfig.apiBase)/models/\(model):generateContent")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body = Request(
            contents: [Content(parts: [Part(text: prompt)], role: "user")],
            systemInstruction: systemInstruction.map { Content(parts: [Part(text: $0)]) },
            generationConfig: generationConfig
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let maxAttempts = 5
        var lastError: Error = GeminiError.emptyResponse

        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                let backoff = pow(2.0, Double(attempt)) + Double.random(in: 0...1)
                try await Task.sleep(for: .seconds(backoff))
            }
            do {
                let (data, response) = try await session.data(for: urlRequest)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0

                if status == 200 {
                    let decoded = try JSONDecoder().decode(Response.self, from: data)
                    guard let parts = decoded.candidates?.first?.content?.parts, !parts.isEmpty else {
                        throw GeminiError.emptyResponse
                    }
                    return parts
                }

                let message = (try? JSONDecoder().decode(Response.self, from: data))?.error?.message
                    ?? String(data: data.prefix(300), encoding: .utf8) ?? "unknown"
                let error = GeminiError.http(status: status, message: message)

                // Retry on rate limits and server errors; anything else is permanent.
                if status == 429 || (500...599).contains(status) {
                    lastError = error
                    continue
                }
                throw error
            } catch let urlError as URLError {
                lastError = GeminiError.network(urlError.localizedDescription)
                if urlError.code == .timedOut || urlError.code == .networkConnectionLost {
                    continue
                }
                throw lastError
            }
        }
        throw lastError
    }
}
