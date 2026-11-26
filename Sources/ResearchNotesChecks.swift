import Foundation
import AppKit

@main struct ResearchNotesChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reader-notes-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = ResearchAnchor(paragraphID: 3, quote: "🧪实验", rangeLocation: 4, rangeLength: 4)
        let region = ResearchPDFRegion(page: 2, bounds: CGRect(x: 10, y: 15, width: 50, height: 12))
        let pdf = ResearchAnchor(quote: "result", pdfRegions: [region])
        let store = ResearchNotebook(root: root)
        store.open(bookID: "paper-a")
        store.selection = a
        precondition(store.highlight(.yellow))
        precondition(store.notes.count == 1 && store.notes[0].anchor == a && store.notes[0].color == .yellow)
        precondition(store.highlight(.green))
        precondition(store.notes.count == 1 && store.notes[0].color == .green)
        precondition(store.addNote(text: "   注释内容  ", anchor: a))
        precondition(store.addNote(text: "独立笔记"))
        precondition(store.addNote(text: "第二页注释", anchor: pdf))
        precondition(!store.addNote(text: "  \n"))
        store.selection = a; store.requestComment(); store.draft = "still writing"
        store.selection = pdf; store.requestComment()
        precondition(store.draftAnchor == a && store.draft == "still writing")
        store.beginEditing(store.notes[0]); precondition(store.draft == "still writing" && store.editingNoteID == nil)
        store.cancelEditing(); precondition(store.draftAnchor == nil && !store.standaloneDraft)
        let saved = store.notes
        precondition(saved.count == 3 && saved.contains { $0.text == "注释内容" && $0.color == .green })
        let reopened = ResearchNotebook(root: root)
        reopened.open(bookID: "paper-a")
        precondition(reopened.notes == saved)
        precondition(reopened.notes[0].anchor?.pdfRegions.first?.bounds == region.bounds)
        precondition(reopened.update(reopened.notes[0].id, text: "更新后的内容"))
        precondition(reopened.markdown().contains("更新后的内容"))
        precondition(reopened.delete(reopened.notes[1].id))
        precondition(reopened.notes.count == 2)
        reopened.open(bookID: "paper-b")
        precondition(reopened.notes.isEmpty && reopened.selection == nil)
        precondition(reopened.addNote(text: "another"))
        reopened.open(bookID: "paper-a")
        precondition(reopened.notes.count == 2 && reopened.notes[0].text == "更新后的内容")
        let corrupted = root.appendingPathComponent(reopened.storageFileName(for: "paper-a"))
        let broken = Data("not JSON".utf8)
        try broken.write(to: corrupted, options: .atomic)
        reopened.open(bookID: "paper-a")
        precondition(reopened.error != nil && reopened.notes.isEmpty)
        precondition(!reopened.addNote(text: "must not overwrite"))
        let contents = try Data(contentsOf: corrupted)
        precondition(contents == broken)
        reopened.open(bookID: nil)
        precondition(!reopened.addNote(text: "no document"))
        let sample = "abc 🧪实验 other"
        precondition(a.resolvedRange(in: sample) == NSRange(location:4, length:4))
        precondition(a.resolvedRange(in: "extra " + sample) == NSRange(location:10,length:4))
        precondition(a.resolvedRange(in: "changed") == nil)
        print("Research notebook checks passed")
    }
}
