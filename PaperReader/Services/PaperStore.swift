import Foundation
import Observation

/// Owns the paper library: JSON persistence under Application Support/Papers/<uuid>/.
@MainActor
@Observable
final class PaperStore {
    private(set) var papers: [Paper] = []

    private static var rootURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Papers", isDirectory: true)
    }

    init() {
        load()
    }

    // MARK: - Paths

    static func folderURL(for paperID: UUID) -> URL {
        rootURL.appendingPathComponent(paperID.uuidString, isDirectory: true)
    }

    static func pdfURL(for paperID: UUID) -> URL {
        folderURL(for: paperID).appendingPathComponent("original.pdf")
    }

    static func audioDirectoryURL(for paperID: UUID) -> URL {
        folderURL(for: paperID).appendingPathComponent("audio", isDirectory: true)
    }

    private static func paperJSONURL(for paperID: UUID) -> URL {
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
            case .failure(let error):
                paper.status = .failed(error.localizedDescription)
            }
            self.save(paper)
        }
    }
}
