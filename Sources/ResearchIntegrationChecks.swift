import Foundation
import SwiftUI

@main struct ResearchIntegrationChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ResearchIntegration-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let a = root.appendingPathComponent("first.txt"), b = root.appendingPathComponent("second.txt")
        try "This is the first research paragraph.\n\nA second paragraph discusses results.".write(to: a, atomically: true, encoding: .utf8)
        try "A different research paper.".write(to: b, atomically: true, encoding: .utf8)
        let store = LibraryStore(root: root.appendingPathComponent("Library"))
        let first = try await store.importDocument(a), second = try await store.importDocument(b)
        let notebook = ResearchNotebook(root: root.appendingPathComponent("Notes"))
        let ai = ResearchAI(root: root.appendingPathComponent("Chats"))
        let model = ReaderModel(translator: WebTranslator(cacheDirectory: root.appendingPathComponent("Cache")), library: store, notebook: notebook, researchAI: ai)
        func open(_ book: LibraryBook) async throws {
            model.openBook(book)
            for _ in 0..<200 where model.importing { try await Task.sleep(nanoseconds: 20_000_000) }
            precondition(model.currentBookID == book.id && notebook.activeBookID == book.id && ai.bookID == book.id)
        }
        try await open(first)
        notebook.selection = ResearchAnchor(paragraphID: 0, quote: "research", rangeLocation: 18, rangeLength: 8)
        precondition(notebook.highlight(.yellow))
        precondition(notebook.addNote(text: "my annotation", anchor: notebook.selection))
        ai.question = "unsent question"
        try await open(second)
        precondition(notebook.notes.isEmpty && notebook.selection == nil && ai.question.isEmpty)
        try await open(first)
        precondition(notebook.notes.count == 1 && notebook.notes[0].text == "my annotation")
        model.returnToLibrary()
        precondition(notebook.activeBookID == nil && ai.bookID == nil && notebook.notes.isEmpty)
        await model.flushLibrarySave()
        print("PASS: research workspace follows stable book identity and restores notes across reader navigation")
    }
}
