import Foundation
import CryptoKit
import PDFKit
import AppKit

struct LibraryBook: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    let fileName: String
    let format: String
    let addedAt: Date
    var lastOpened: Date
    var pageCount: Int
    var translatedCount: Int
    var page: Int
}
struct ReadingSession: Codable {
    var paragraphs: [ReadingParagraph]
    var layoutPending: Bool? = nil
    var page: Int = 1
    var paragraphID: Int? = nil
    var mode: String = PDFReadingModeValue.original
    var fontSize: Double = 20
    var engine: String = TranslationEngine.google.rawValue
    var modifiedAt: Date = Date()
}
// Kept independent of the UI enum so disk/CLI checks need no SwiftUI runtime.
private enum PDFReadingModeValue { static let original = "原页模式" }

actor LibraryStore {
    private let root: URL
    private var books: [LibraryBook]?
    private var clearDate = Date.distantPast
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BilingualReader/Library", isDirectory: true)
    }
    private var index: URL { root.appendingPathComponent("index.json") }
    private func folder(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func documentURL(_ book: LibraryBook) -> URL { folder(book.id).appendingPathComponent(book.fileName) }
    func coverURL(_ book: LibraryBook) -> URL { folder(book.id).appendingPathComponent("cover.png") }
    func list() throws -> [LibraryBook] {
        if let books { return books.sorted { $0.lastOpened > $1.lastOpened } }
        if FileManager.default.fileExists(atPath: index.path) {
            do {
                let decoded = try JSONDecoder().decode([LibraryBook].self, from: Data(contentsOf: index))
                guard decoded.allSatisfy({ $0.id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil && !$0.fileName.contains("/") && !$0.fileName.contains("..") }) else { throw ReaderError.message("书库索引格式错误") }
                books = decoded
            } catch { throw ReaderError.message("无法读取书库记录，原文件已保留。请备份书库后检查 index.json：\(error.localizedDescription)") }
        } else { books = [] }
        return books!.sorted { $0.lastOpened > $1.lastOpened }
    }
    private func writeIndex(_ values: [LibraryBook]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: index, options: .atomic)
        books = values
    }
    func importDocument(_ source: URL) throws -> LibraryBook {
        var values = try list()
        let ext = source.pathExtension.lowercased()
        guard ["pdf", "docx", "txt"].contains(ext) else { throw ReaderError.message("请选择 PDF、DOCX 或 TXT 文件") }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        // Read remote/cloud files once: the bytes copied are also the bytes hashed.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".import-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let name = "document." + ext
        let copy = staging.appendingPathComponent(name)
        FileManager.default.createFile(atPath: copy.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: copy)
        defer { try? output.close() }
        var hasher = SHA256()
        while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
            try output.write(contentsOf: data)
            hasher.update(data: data)
        }
        try output.close()
        let id = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        if let existing = values.first(where: { $0.id == id }) { return existing }
        let dir = folder(id)
        guard !FileManager.default.fileExists(atPath: dir.path) else { throw ReaderError.message("书库中有未完成的同名记录，请检查书库文件夹后重试") }
        var pdf: PDFDocument?
        let paragraphs: [ReadingParagraph]
        if ext == "pdf" {
            guard let document = PDFDocument(url: copy), document.pageCount > 0 else { throw ReaderError.message("无法打开这份 PDF。") }
            guard !document.isLocked else { throw ReaderError.message("这份 PDF 有密码保护，请先解锁。") }
            pdf = document
            paragraphs = []
        } else { paragraphs = try DocumentLoader.load(copy) }
        if let first = pdf?.page(at: 0) {
            let image = first.thumbnail(of: NSSize(width: 420, height: 580), for: .cropBox)
            if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: staging.appendingPathComponent("cover.png"), options: .atomic)
            }
        }
        let book = LibraryBook(id: id, title: source.deletingPathExtension().lastPathComponent, fileName: name,
                               format: ext, addedAt: Date(), lastOpened: Date(), pageCount: pdf?.pageCount ?? 0, translatedCount: 0, page: 1)
        try JSONEncoder().encode(ReadingSession(paragraphs: paragraphs, layoutPending: ext == "pdf" ? true : nil))
            .write(to: staging.appendingPathComponent("session.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: dir)
        do {
            values.append(book); try writeIndex(values)
            return book
        } catch { try? FileManager.default.removeItem(at: dir); throw error }
    }
    func session(_ id: String) throws -> ReadingSession? {
        guard try list().contains(where: { $0.id == id }) else { return nil }
        let path = folder(id).appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return try JSONDecoder().decode(ReadingSession.self, from: Data(contentsOf: path))
    }
    func save(_ id: String, session input: ReadingSession) throws {
        var values = try list()
        guard let at = values.firstIndex(where: { $0.id == id }) else { return }
        if let previous = try session(id), previous.modifiedAt > input.modifiedAt { return }
        var clean = input
        for i in clean.paragraphs.indices {
            clean.paragraphs[i].loading = false; clean.paragraphs[i].activity = nil; clean.paragraphs[i].error = nil
            if input.modifiedAt <= clearDate { clean.paragraphs[i].translation = nil; clean.paragraphs[i].expanded = false }
        }
        try JSONEncoder().encode(clean).write(to: folder(id).appendingPathComponent("session.json"), options: .atomic)
        values[at].page = max(1, clean.page)
        values[at].translatedCount = clean.paragraphs.filter { $0.translation != nil }.count
        values[at].lastOpened = clean.modifiedAt
        try writeIndex(values)
    }
    func remove(_ id: String) throws {
        let values = try list()
        guard values.contains(where: { $0.id == id }) else { return }
        try writeIndex(values.filter { $0.id != id })
        try FileManager.default.removeItem(at: folder(id))
    }
    func clearTranslations() throws {
        clearDate = Date()
        for book in try list() {
            if var state = try session(book.id) {
                state.modifiedAt = clearDate
                for i in state.paragraphs.indices { state.paragraphs[i].translation = nil; state.paragraphs[i].expanded = false }
                try save(book.id, session: state)
            }
        }
    }
}
