import Foundation
import Observation

/// Owns the paper library: JSON persistence under Application Support/Papers/<uuid>/.
@MainActor
@Observable
final class PaperStore {
    private(set) var papers: [Paper] = []

    private let gemini: GeminiClient
    /// Papers with a pipeline task currently running, to avoid double-starts.
    private var activePipelines: Set<UUID> = []

    /// Fired when a paper's script becomes ready (and for ready papers at
    /// launch), so its resume-position audio can be warmed up.
    var onScriptReady: ((UUID) -> Void)?

    nonisolated private static var rootURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Papers", isDirectory: true)
    }

    init(client: GeminiClient) {
        self.gemini = client
        load()
    }

    // MARK: - Paths

    nonisolated static func folderURL(for paperID: UUID) -> URL {
        rootURL.appendingPathComponent(paperID.uuidString, isDirectory: true)
    }

    nonisolated static func pdfURL(for paperID: UUID) -> URL {
        folderURL(for: paperID).appendingPathComponent("original.pdf")
    }

    nonisolated static func audioDirectoryURL(for paperID: UUID) -> URL {
        folderURL(for: paperID).appendingPathComponent("audio", isDirectory: true)
    }

    nonisolated private static func paperJSONURL(for paperID: UUID) -> URL {
        folderURL(for: paperID).appendingPathComponent("paper.json")
    }

    // MARK: - Load / save

    private func load() {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: Self.rootURL, includingPropertiesForKeys: nil) else {
            return
        }
        var loaded: [Paper] = []
        for folder in folders {
            let jsonURL = folder.appendingPathComponent("paper.json")
            guard let data = try? Data(contentsOf: jsonURL),
                  let paper = try? JSONDecoder().decode(Paper.self, from: data) else { continue }
            loaded.append(paper)
        }
        papers = loaded.sorted { $0.addedAt > $1.addedAt }
    }

    func save(_ paper: Paper) {
        if let i = papers.firstIndex(where: { $0.id == paper.id }) {
            papers[i] = paper
        } else {
            papers.insert(paper, at: 0)
        }
        persist(paper)
    }

    private func persist(_ paper: Paper) {
        do {
            let folder = Self.folderURL(for: paper.id)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(paper)
            try data.write(to: Self.paperJSONURL(for: paper.id), options: .atomic)
        } catch {
            print("PaperStore: failed to persist \(paper.id): \(error)")
        }
    }

    func delete(_ paper: Paper) {
        papers.removeAll { $0.id == paper.id }
        try? FileManager.default.removeItem(at: Self.folderURL(for: paper.id))
    }

    func paper(id: UUID) -> Paper? {
        papers.first { $0.id == id }
    }

    // MARK: - Import

    /// Copies a picked PDF into the library and extracts its text off the main thread.
    func importPDF(from pickedURL: URL) {
        let filename = pickedURL.lastPathComponent
        var paper = Paper(title: filename, originalFilename: filename)

        let hasAccess = pickedURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { pickedURL.stopAccessingSecurityScopedResource() } }

        do {
            let folder = Self.folderURL(for: paper.id)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: pickedURL, to: Self.pdfURL(for: paper.id))
        } catch {
            paper.status = .failed("Couldn't copy the PDF: \(error.localizedDescription)")
            save(paper)
            return
        }

        save(paper)
        extractText(for: paper.id)
    }

    /// Runs PDFKit extraction in the background and updates the paper when done.
    func extractText(for paperID: UUID) {
        guard var paper = paper(id: paperID) else { return }
        paper.status = .extracting
        save(paper)

        let pdfURL = Self.pdfURL(for: paperID)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try PDFTextExtractor.extractPages(from: pdfURL) }
            }.value

            guard var paper = self.paper(id: paperID) else { return }
            switch result {
            case .success(let extraction):
                paper.extractedPages = extraction.pages
                paper.pageCount = extraction.pageCount
                paper.status = .imported
                self.save(paper)
                self.generateScript(for: paperID)
            case .failure(let error):
                paper.status = .failed(error.localizedDescription)
                self.save(paper)
            }
        }
    }

    // MARK: - Script generation

    /// Chunked LLM cleanup with per-chunk persistence so a killed app resumes
    /// where it left off instead of re-spending tokens.
    func generateScript(for paperID: UUID) {
        guard let paper = paper(id: paperID),
              paper.extractedPages != nil,
              !activePipelines.contains(paperID) else { return }
        activePipelines.insert(paperID)

        Task {
            defer { activePipelines.remove(paperID) }
            await runScriptPipeline(paperID: paperID)
        }
    }

    private func runScriptPipeline(paperID: UUID) async {
        guard var paper = paper(id: paperID), let pages = paper.extractedPages else { return }

        let generator = ScriptGenerator(client: gemini)
        let inputChunks = ScriptGenerator.inputChunks(from: pages)
        guard !inputChunks.isEmpty else {
            paper.status = .failed("No text to process.")
            save(paper)
            return
        }

        // Resume: keep prior per-chunk results if the chunking is unchanged.
        var cleaned = paper.cleanedChunks ?? Array(repeating: nil, count: inputChunks.count)
        if cleaned.count != inputChunks.count {
            cleaned = Array(repeating: nil, count: inputChunks.count)
        }

        do {
            // Improve on the filename title once per paper.
            if paper.title == paper.originalFilename, let firstPage = pages.first {
                if let title = try? await generator.extractTitle(fromFirstPage: firstPage) {
                    paper.title = title
                }
            }

            for (i, chunk) in inputChunks.enumerated() where cleaned[i] == nil {
                paper.status = .generatingScript(done: i, total: inputChunks.count)
                paper.cleanedChunks = cleaned
                save(paper)

                cleaned[i] = try await generator.cleanChunk(chunk, index: i, total: inputChunks.count)
            }

            let script = cleaned.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            let sentences = SentenceSegmenter.sentences(from: script)
            guard !sentences.isEmpty else {
                throw GeminiError.emptyResponse
            }

            paper.cleanedChunks = cleaned
            paper.sentences = sentences
            paper.chunks = ChunkPlanner.plan(for: sentences)
            paper.playback = PlaybackState()
            paper.status = .ready
            save(paper)
            onScriptReady?(paperID)
        } catch {
            paper.cleanedChunks = cleaned
            paper.status = .failed(error.localizedDescription)
            save(paper)
        }
    }

    /// Restart the pipeline for a failed/stuck paper, reusing whatever already succeeded.
    func retry(_ paperID: UUID) {
        guard var paper = paper(id: paperID) else { return }
        if paper.extractedPages == nil {
            paper.status = .extracting
            save(paper)
            extractText(for: paperID)
        } else {
            paper.status = .imported
            save(paper)
            generateScript(for: paperID)
        }
    }

    /// Called at launch: pick up papers that were mid-pipeline when the app quit.
    func resumeUnfinished() {
        for paper in papers {
            switch paper.status {
            case .extracting:
                extractText(for: paper.id)
            case .imported, .generatingScript:
                generateScript(for: paper.id)
            case .ready:
                onScriptReady?(paper.id)
            default:
                break
            }
        }
    }
}
