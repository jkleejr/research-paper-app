import Foundation

/// Turns raw extracted PDF text into a clean read-aloud script via chunked Gemini calls.
struct ScriptGenerator {
    let client: GeminiClient

    /// Split page texts into LLM-sized input chunks, breaking at paragraph boundaries.
    static func inputChunks(from pages: [String], maxChars: Int = 10_000) -> [String] {
        let paragraphs = joinSentencesSplitByPageBreaks(
            pages
                .flatMap { $0.components(separatedBy: "\n\n") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

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

    /// A sentence running across a page break arrives as the tail of one page and
    /// the head of the next — two separate paragraphs. Joining them with a blank
    /// line would tell the model they're unrelated, and worse, the seam can land
    /// on a chunk boundary, where no single call can see both halves to repair.
    private static func joinSentencesSplitByPageBreaks(_ paragraphs: [String]) -> [String] {
        var joined: [String] = []
        for paragraph in paragraphs {
            guard let previous = joined.last,
                  !endsSentence(previous),
                  paragraph.first?.isLowercase == true else {
                joined.append(paragraph)
                continue
            }
            joined[joined.count - 1] = previous + " " + paragraph
        }
        return joined
    }

    /// True when the text ends the way a finished sentence does. Headings, which
    /// end without punctuation, are followed by a capital and so never merge.
    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return true }
        if ".!?".contains(last) { return true }
        // A closing quote or bracket still ends the sentence it wraps.
        if "\"'’”)]".contains(last) {
            return text.dropLast().last.map { ".!?".contains($0) } ?? false
        }
        return false
    }

    /// Rules that hold whatever the document is: the extraction artifacts and
    /// the page furniture are the same everywhere.
    private static let sharedRules = """
    Output ONLY the cleaned text, with no preamble, headers you invent, or commentary.

    Remove entirely:
    - Page headers, footers, page numbers, and slide numbers
    - Watermarks, copyright and license notices, confidentiality banners
    - URLs and email addresses that stand on their own
    - Stray characters left by the layout: arrows (—>, <—), bullet glyphs, rule lines, \
    and single letters or numbers stranded on their own line

    Convert notation for listening: spell out Greek letters, symbols, and simple math so they \
    read naturally, and expand abbreviations that would be read as letters when they are meant \
    as words.

    PDF extraction sometimes drops spaces, so a few words may arrive run together \
    ("themagnitudeofthesebubbles") or split mid-word across a line ("man agers"). Restore the \
    correct spacing.

    If the excerpt is entirely material that should be removed, output an empty response.
    """

    private static func systemInstruction(for kind: DocumentKind) -> String {
        switch kind {
        case .researchPaper:
            return """
            You convert research-paper excerpts into a read-aloud script.

            \(sharedRules)

            Also remove:
            - Author names and affiliations
            - Figure and table captions, and table contents
            - Inline citations such as [12], [3, 4], or (Smith et al., 2020) — keep the sentence \
            flowing naturally without them
            - Footnote markers and footnote text
            - The references/bibliography section
            - Acknowledgments and funding statements

            Keep all substantive prose otherwise verbatim, including the abstract. Keep section \
            titles as short plain lines. "et al." becomes "and colleagues". Do not reword anything \
            beyond the fixes above.
            """

        case .slides:
            return """
            You convert presentation slides into a read-aloud script. Slides are written to be \
            looked at while someone talks, so the text arrives as fragments that do not read \
            aloud on their own. Your job is to turn each slide into speakable sentences.

            \(sharedRules)

            Also remove:
            - Labels that only make sense against a picture: axis names, units on their own \
            ("(dB)", "(ms)"), legend keys, callouts, and numbers scattered by a diagram
            - Speaker-note artifacts, template placeholder text, and logos or company names \
            repeated on every slide

            Then, for the slides that remain:
            - Keep each slide's title as a short plain line of its own
            - Join that slide's fragments into complete sentences. A title followed by a fragment \
            usually means the fragment is about the title: "VCA" then "relatively clean and \
            accurate response" becomes "VCA compressors have a relatively clean and accurate \
            response."
            - Turn terse bullet lists into flowing prose, keeping every point and its order
            - Where a fragment is a definition ("Threshold : Level at which..."), read it as one: \
            "Threshold is the level at which..."

            Add only the words needed to make fragments grammatical. Never invent facts, \
            examples, or explanations that are not on the slide.
            """

        case .prose:
            return """
            You convert a document — a story, article, report, or book chapter — into a \
            read-aloud script.

            \(sharedRules)

            Also remove:
            - Running heads, chapter/section numbers that stand alone on a line
            - Footnotes, endnote markers, and marginalia
            - Tables of contents, indexes, and figure captions

            Keep the text otherwise verbatim — the wording is the point. Keep chapter and section \
            titles as short plain lines. Keep dialogue and paragraph breaks intact.
            """
        }
    }

    func cleanChunk(_ chunk: String, index: Int, total: Int,
                    kind: DocumentKind) async throws -> String {
        let noun = kind == .slides ? "deck" : "document"
        let prompt = "This is part \(index + 1) of \(total) of the \(noun). Do not add an introduction or summary.\n\n---\n\n\(chunk)"
        do {
            let cleaned = try await client.generateText(
                model: AppConfig.textModel,
                systemInstruction: Self.systemInstruction(for: kind),
                prompt: prompt
            )
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch GeminiError.emptyResponse {
            // Model was told to return nothing for pure-references chunks.
            return ""
        }
    }

    struct Identification {
        var title: String?
        var kind: DocumentKind
    }

    /// Title and document kind in one call — the kind decides which cleanup rules
    /// the rest of the run uses, and asking for it here costs no extra request.
    /// Falls back to the heuristic whenever the answer is missing or unusable.
    func identify(pages: [String]) async throws -> Identification {
        let fallback = DocumentKind.heuristic(from: pages)
        // First pages carry the title; a page count and per-page length tell decks
        // from documents better than any single page can.
        let opening = pages.prefix(3).map { $0.prefix(1500) }.joined(separator: "\n\n--- next page ---\n\n")
        let averageChars = pages.isEmpty ? 0 : pages.reduce(0) { $0 + $1.count } / pages.count
        let prompt = """
        Identify this PDF from its opening pages.

        It has \(pages.count) pages, averaging \(averageChars) characters of text per page.

        "kind" must be one of:
        - "researchPaper" — an academic paper or preprint
        - "slides" — a presentation deck, where pages are mostly short fragments meant to be \
        spoken over
        - "prose" — anything else written to be read: a story, article, report, manual, or book

        "title" is the document's own title, or null if the text doesn't state one. Do not use \
        the file name.

        Respond with JSON only: {"title": "...", "kind": "..."}

        \(opening)
        """
        let json = try await client.generateText(
            model: AppConfig.textModel,
            prompt: prompt,
            responseMimeType: "application/json"
        )
        struct Response: Decodable {
            var title: String?
            var kind: String?
        }
        let decoded = try? JSONDecoder().decode(Response.self, from: Data(json.utf8))
        let title = decoded?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = decoded?.kind.flatMap(DocumentKind.init(rawValue:)) ?? fallback
        return Identification(title: (title?.isEmpty == false) ? title : nil, kind: kind)
    }
}
