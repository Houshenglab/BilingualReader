import SwiftUI
import AppKit
import CryptoKit

struct ResearchPDFRegion: Codable, Hashable {
    let page: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    init(page: Int, bounds: CGRect) {
        self.page = page
        self.x = bounds.minX; self.y = bounds.minY
        self.width = bounds.width; self.height = bounds.height
    }
    var bounds: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var valid: Bool { page > 0 && [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
}

struct ResearchAnchor: Codable, Hashable {
    let paragraphID: Int?
    let quote: String
    let rangeLocation: Int?
    let rangeLength: Int?
    let pdfRegions: [ResearchPDFRegion]
    init(paragraphID: Int? = nil, quote: String, rangeLocation: Int? = nil, rangeLength: Int? = nil, pdfRegions: [ResearchPDFRegion] = []) {
        self.paragraphID = paragraphID; self.quote = quote
        self.rangeLocation = rangeLocation; self.rangeLength = rangeLength; self.pdfRegions = pdfRegions
    }
    var valid: Bool {
        !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (paragraphID.map { $0 >= 0 } ?? !pdfRegions.isEmpty) &&
        pdfRegions.allSatisfy(\.valid) &&
        ((rangeLocation == nil && rangeLength == nil) || (rangeLocation ?? -1) >= 0 && (rangeLength ?? 0) > 0)
    }
    var locationLabel: String {
        if let page = pdfRegions.first?.page { return L("第 \(page) 页", "Page \(page)") }
        if let paragraphID { return L("第 \(paragraphID + 1) 段", "Paragraph \(paragraphID + 1)") }
        return L("原文摘录", "Source excerpt")
    }
    func resolvedRange(in text: String) -> NSRange? {
        let source = text as NSString
        if let l = rangeLocation, let n = rangeLength, l >= 0, n > 0, l <= source.length, n <= source.length - l,
           source.substring(with: NSRange(location: l, length: n)) == quote {
            return NSRange(location: l, length: n)
        }
        // If an edit to paragraph layout shifts offsets, recover a unique exact quote only.
        guard !quote.isEmpty else { return nil }
        let match = source.range(of: quote)
        guard match.location != NSNotFound else { return nil }
        let end = NSMaxRange(match)
        if end < source.length, source.range(of: quote, options: [], range: NSRange(location: end, length: source.length - end)).location != NSNotFound { return nil }
        return match
    }
}

enum ResearchColor: String, Codable, CaseIterable, Identifiable {
    case yellow, green, blue, pink
    var id: String { rawValue }
    var label: String {
        switch self { case .yellow: return L("黄色", "Yellow"); case .green: return L("绿色", "Green"); case .blue: return L("蓝色", "Blue"); case .pink: return L("粉色", "Pink") }
    }
    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(red: 0.99, green: 0.78, blue: 0.16, alpha: 1)
        case .green: return NSColor(red: 0.26, green: 0.77, blue: 0.45, alpha: 1)
        case .blue: return NSColor(red: 0.31, green: 0.65, blue: 0.96, alpha: 1)
        case .pink: return NSColor(red: 0.95, green: 0.45, blue: 0.64, alpha: 1)
        }
    }
    var color: Color { Color(nsColor: nsColor) }
}

struct ResearchNote: Codable, Identifiable, Equatable {
    let id: UUID
    let anchor: ResearchAnchor?
    var color: ResearchColor?
    var text: String
    let createdAt: Date
    init(id: UUID = UUID(), anchor: ResearchAnchor? = nil, color: ResearchColor? = nil, text: String, createdAt: Date = Date()) {
        self.id = id; self.anchor = anchor; self.color = color; self.text = text; self.createdAt = createdAt
    }
}

@MainActor final class ResearchNotebook: ObservableObject {
    @Published private(set) var notes: [ResearchNote] = []
    @Published var selection: ResearchAnchor?
    @Published var error: String?
    @Published var requestedJump: ResearchNote?
    @Published var draft = ""
    @Published var draftAnchor: ResearchAnchor?
    @Published var standaloneDraft = false
    @Published var editingNoteID: UUID?
    @Published var commentRequest: UUID?
    @Published private(set) var activeBookID: String?
    private var editable = false
    private let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BilingualReader/ResearchNotes", isDirectory: true)
    }
    // Stable IDs are hashed even if a caller uses a non-library identity. A document name
    // or malicious ID never becomes a filesystem path.
    func storageFileName(for bookID: String) -> String {
        SHA256.hash(data: Data(bookID.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }
    func open(bookID: String?) {
        activeBookID = bookID; editable = false
        notes = []; selection = nil; error = nil; requestedJump = nil; draft = ""; draftAnchor = nil; standaloneDraft = false; editingNoteID = nil; commentRequest = nil
        guard let bookID, !bookID.isEmpty else { return }
        let file = root.appendingPathComponent(storageFileName(for: bookID))
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let decoded = try JSONDecoder().decode([ResearchNote].self, from: Data(contentsOf: file))
                guard Set(decoded.map(\.id)).count == decoded.count, decoded.allSatisfy({ ($0.anchor?.valid ?? true) && ($0.color == nil || $0.anchor != nil) && ($0.color != nil || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                notes = decoded
            }
            editable = true
        } catch { self.error = L("笔记记录无法读取，原文件已保留：\(error.localizedDescription)", "Could not read notes; original file retained: \(error.localizedDescription)") }
    }
    private func save(_ value: [ResearchNote]) -> Bool {
        guard editable, let bookID = activeBookID else {
            if error == nil { error = L("请先打开文献，或重新加载笔记。", "Open a document or reload its notes first.") }; return false
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: root.appendingPathComponent(storageFileName(for: bookID)), options: .atomic)
            notes = value; error = nil; return true
        } catch { self.error = L("保存笔记失败：\(error.localizedDescription)", "Could not save notes: \(error.localizedDescription)"); return false }
    }
    @discardableResult func highlight(_ color: ResearchColor) -> Bool {
        guard let selection, selection.valid else { return false }
        var value = notes
        if let i = value.firstIndex(where: { $0.anchor == selection && $0.color != nil }) ?? value.firstIndex(where: { $0.anchor == selection }) {
            value[i].color = color
        } else { value.insert(ResearchNote(anchor: selection, color: color, text: ""), at: 0) }
        return save(value)
    }
    @discardableResult func addNote(text: String, anchor: ResearchAnchor? = nil) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, anchor?.valid ?? true else { return false }
        var value = notes
        if let anchor, let i = value.firstIndex(where: { $0.anchor == anchor && $0.text.isEmpty }) { value[i].text = clean }
        else { value.insert(ResearchNote(anchor: anchor, text: clean), at: 0) }
        return save(value)
    }
    @discardableResult func update(_ id: UUID, text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = notes
        guard let i = value.firstIndex(where: { $0.id == id }), !clean.isEmpty || value[i].color != nil else { return false }
        value[i].text = clean
        return save(value)
    }
    @discardableResult func delete(_ id: UUID) -> Bool {
        let value = notes.filter { $0.id != id }
        guard value.count != notes.count, save(value) else { return false }
        if editingNoteID == id { cancelEditing() }
        return true
    }
    func beginEditing(_ note: ResearchNote) {
        if editingNoteID == note.id { commentRequest = UUID(); return }
        guard draft.isEmpty else { error = L("请先保存或取消正在编辑的笔记。", "Save or cancel the note you are editing first."); commentRequest = UUID(); return }
        selection = note.anchor; editingNoteID = note.id; draftAnchor = note.anchor; standaloneDraft = note.anchor == nil
        draft = note.text; commentRequest = UUID()
    }
    func requestComment() {
        if draft.isEmpty && editingNoteID == nil { draftAnchor = selection; standaloneDraft = false }
        else if draftAnchor != selection { error = L("请先保存或取消正在编辑的笔记。", "Save or cancel the note you are editing first.") }
        commentRequest = UUID()
    }
    func cancelEditing() { editingNoteID = nil; draft = ""; draftAnchor = nil; standaloneDraft = false }

    func markdown() -> String {
        var output = L("# 文献笔记\n\n", "# Research notes\n\n")
        for note in notes.reversed() {
            output += "## \(note.anchor?.locationLabel ?? L("独立笔记", "Standalone note")) · \(note.createdAt.formatted(date: .abbreviated, time: .shortened))\n\n"
            if let quote = note.anchor?.quote { output += quote.components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n") + "\n\n" }
            if let color = note.color { output += L("高亮：\(color.label)\n\n", "Highlight: \(color.label)\n\n") }
            if !note.text.isEmpty { output += note.text + "\n\n" }
        }
        return output
    }
}
