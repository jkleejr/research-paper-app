import Foundation

/// Turns raw extracted PDF text into a clean read-aloud script via chunked Gemini calls.
struct ScriptGenerator {
    let client: GeminiClient

    /// Split page texts into LLM-sized input chunks, breaking at paragraph boundaries.
    static func inputChunks(from pages: [String], maxChars: Int = 10_000) -> [String] {
        let paragraphs = pages
            .flatMap { $0.components(separatedBy: "\n\n") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""
        for paragraph in paragraphs {
            // Oversized single paragraph: hard-split so no chunk exceeds the limit.
            if paragraph.count > maxChars {
                if !current.isEmpty { chunks.append(current); current = "" }
                var remaining = Substring(paragraph)
                while remaining.count > maxChars {
                    let cut = remaining.index(remaining.startIndex, offsetBy: maxChars)
                    // Prefer breaking at the last sentence end before the limit.
                    let slice = remaining[..<cut]
                    let breakIndex = slice.lastIndex(of: ".").map(slice.index(after:)) ?? cut
                    chunks.append(String(remaining[..<breakIndex]))
                    remaining = remaining[breakIndex...]
                }
                current = String(remaining)
                continue
            }
            if current.count + paragraph.count + 2 > maxChars {
                chunks.append(current)
                current = paragraph
            } else {
                current = current.isEmpty ? paragraph : current + "\n\n" + paragraph
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static let systemInstruction = """
    You convert research-paper excerpts into a read-aloud script. Output ONLY the cleaned text, \
    with no preamble, headers you invent, or commentary.

    Remove entirely:
    - Author names, affiliations, and email addresses
    - Figure and table captions, and table contents
    - Inline citations such as [12], [3, 4], or (Smith et al., 2020) — keep the sentence flowing naturally without them
    - Footnote markers and footnote text
    - Page headers/footers, arXiv banners, copyright and license notices
    - The references/bibliography section
    - Acknowledgments and funding statements

    Keep all substantive prose otherwise verbatim, including the abstract. Keep section titles as \
    short plain lines. Convert notation for listening: "et al." becomes "and colleagues", spell out \
    Greek letters and simple math so they read naturally.

    PDF extraction sometimes drops spaces, so a few words may arrive run together \
    ("themagnitudeofthesebubbles") or split mid-word across a line ("man agers"). Restore the \
    correct spacing. Do not reword anything else to fix it.

    If the excerpt is entirely references, acknowledgments, or other removed material, output an \
    empty response.
    """

    func cleanChunk(_ chunk: String, index: Int, total: Int) async throws -> String {
        let prompt = "This is part \(index + 1) of \(total) of the paper. Do not add an introduction or summary.\n\n---\n\n\(chunk)"
        do {
            let cleaned = try await client.generateText(
                model: AppConfig.textModel,
                systemInstruction: Self.systemInstruction,
                prompt: prompt
            )
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch GeminiError.emptyResponse {
            // Model was told to return nothing for pure-references chunks.
            return ""
        }
    }

    func extractTitle(fromFirstPage firstPage: String) async throws -> String? {
        let prompt = """
        Extract the title of this research paper from its first-page text. \
        Respond with JSON only: {"title": "..."}

        \(firstPage.prefix(3000))
        """
        let json = try await client.generateText(
            model: AppConfig.textModel,
            prompt: prompt,
            responseMimeType: "application/json"
        )
        struct TitleResponse: Decodable { var title: String? }
        let decoded = try? JSONDecoder().decode(TitleResponse.self, from: Data(json.utf8))
        let title = decoded?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false) ? title : nil
    }
}
