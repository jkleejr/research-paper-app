import Foundation

// Builds the bundled sample paper: runs a real PDF through the app's own
// extractor, cleanup prompt and TTS service, then writes the result into
// PaperReader/Resources/SampleLibrary/ for the app to install on first launch.
//
// Generated once by a developer and committed, so shipping it costs users
// nothing and exposes no API key. See Tools/sample/README.md.
//
//   GEMINI_API_KEY=... generate-sample <pdf> <firstPage> <lastPage> <outputDir>

let args = CommandLine.arguments
guard args.count >= 5,
      let firstPage = Int(args[2]),
      let lastPage = Int(args[3]) else {
    print("usage: GEMINI_API_KEY=... generate-sample <pdf> <firstPage> <lastPage> <outputDir>")
    exit(1)
}
let pdfURL = URL(fileURLWithPath: args[1])
let outputDir = URL(fileURLWithPath: args[4])

guard let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty else {
    print("error: set GEMINI_API_KEY (billing must be enabled — TTS is not on the free tier)")
    exit(1)
}
// AppConfig reads this in DEBUG builds; compile the tool with -DDEBUG.
UserDefaults.standard.set(key, forKey: "uiTestAPIKey")

/// Fixed so the app can recognise the sample (badge it, avoid reinstalling it).
let sampleID = UUID(uuidString: "5A3B1E00-0000-4000-8000-5A3B1E000001")!

/// CC BY 4.0 requires credit and a note of what was changed. Spoken up front so
/// the attribution travels with the audio, not just the on-screen text.
let preamble = """
This is a sample reading included with Paper Reader. The paper is TradingAgents: \
Multi-Agents LLM Financial Trading Framework, by Yijia Xiao, Edward Sun, Di Luo and Wei Wang, \
used under the Creative Commons Attribution 4.0 International license. What follows is an \
abridged excerpt — the abstract and introduction — cleaned up for listening and read by a \
synthetic voice. To listen to your own papers, add a Gemini API key in Settings.
"""

// MARK: - Extract

print("extracting \(pdfURL.lastPathComponent) pages \(firstPage)–\(lastPage)…")
let extraction = try PDFTextExtractor.extractPages(from: pdfURL)
let lower = max(0, firstPage - 1)
let upper = min(lastPage, extraction.pages.count)
guard lower < upper else {
    print("error: page range outside document (\(extraction.pageCount) pages)")
    exit(1)
}
let pages = Array(extraction.pages[lower..<upper])
print("  \(pages.reduce(0) { $0 + $1.count }) characters of raw text")

// MARK: - Clean

let client = GeminiClient()
let generator = ScriptGenerator(client: client)
let inputs = ScriptGenerator.inputChunks(from: pages)
print("cleaning \(inputs.count) chunk(s) with \(AppConfig.textModel)…")

var cleanedParts: [String] = []
for (i, chunk) in inputs.enumerated() {
    // The bundled sample is a paper; the tool doesn't need kind detection.
    let cleaned = try await generator.cleanChunk(chunk, index: i, total: inputs.count,
                                                 kind: .researchPaper)
    if !cleaned.isEmpty { cleanedParts.append(cleaned) }
    print("  chunk \(i + 1)/\(inputs.count): \(cleaned.count) chars")
}
let script = ([preamble] + cleanedParts).joined(separator: "\n\n")

let sentences = SentenceSegmenter.sentences(from: script)
var chunks = ChunkPlanner.plan(for: sentences)
print("script: \(sentences.count) sentences, \(chunks.count) audio chunks")

// MARK: - Narrate

let tts = TTSService(client: client)
print("synthesizing with \(AppConfig.ttsModel) (voice \(AppConfig.ttsVoice))…")
var totalSeconds = 0.0
for i in chunks.indices {
    let result = try await tts.synthesize(paperID: sampleID, chunk: chunks[i], sentences: sentences)
    chunks[i].audioStatus = .cached(duration: result.duration)
    chunks[i].sentenceDurations = result.sentenceDurations
    totalSeconds += result.duration
    print("  chunk \(i + 1)/\(chunks.count): \(String(format: "%.1f", result.duration))s")
}

// MARK: - Write the bundle payload

var paper = Paper(id: sampleID,
                  title: "TradingAgents: Multi-Agents LLM Financial Trading Framework",
                  originalFilename: "tradingagents-sample.pdf")
paper.status = .ready
paper.pageCount = extraction.pageCount
paper.sentences = sentences
paper.chunks = chunks
paper.playback = PlaybackState()

let audioOut = outputDir.appendingPathComponent("audio", isDirectory: true)
try? FileManager.default.removeItem(at: outputDir)
try FileManager.default.createDirectory(at: audioOut, withIntermediateDirectories: true)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(paper).write(to: outputDir.appendingPathComponent("sample.json"), options: .atomic)

var bytes: Int64 = 0
for chunk in chunks {
    let src = AudioCache.url(paperID: sampleID, chunkIndex: chunk.index)
    let dst = audioOut.appendingPathComponent(src.lastPathComponent)
    try FileManager.default.copyItem(at: src, to: dst)
    bytes += Int64((try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
}
// The tool's scratch copy under Application Support isn't the shipped one.
try? FileManager.default.removeItem(at: PaperStore.folderURL(for: sampleID))

let minutes = totalSeconds / 60
print("""

done → \(outputDir.path)
  \(chunks.count) chunks · \(String(format: "%.1f", minutes)) min audio · \
\(String(format: "%.1f", Double(bytes) / 1_048_576)) MB
""")
