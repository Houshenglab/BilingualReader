import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Native text keeps selection and copy behavior while rendering persisted markups
// without modifying the source document.
struct SelectableParagraphText: NSViewRepresentable {
    let text: String
    let paragraphID: Int
    let fontSize: Double
    @ObservedObject var notebook: ResearchNotebook
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> ParagraphTextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let view = ParagraphTextView(frame: .zero, textContainer: container)
        view.isEditable = false; view.isSelectable = true
        view.isRichText = true; view.drawsBackground = false
        view.textContainerInset = .zero; container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.delegate = context.coordinator
        view.selectionAnchor = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return nil }
            return coordinator.anchor(in: view)
        }
        view.highlightAction = { [weak coordinator = context.coordinator] color, anchor in
            coordinator?.parent.notebook.selection = anchor
            coordinator?.parent.notebook.highlight(color)
        }
        view.commentAction = { [weak coordinator = context.coordinator] anchor in
            coordinator?.parent.notebook.selection = anchor
            coordinator?.parent.notebook.requestComment()
        }
        return view
    }
    func updateNSView(_ view: ParagraphTextView, context: Context) {
        context.coordinator.parent = self
        let attributed = NSMutableAttributedString(string: text)
        let whole = NSRange(location: 0, length: attributed.length)
        let style = NSMutableParagraphStyle(); style.lineSpacing = 8; style.lineBreakMode = .byWordWrapping
        let font = NSFont(name: "Georgia", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        attributed.addAttributes([.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style], range: whole)
        for note in notebook.notes.reversed() {
            guard let anchor = note.anchor, anchor.paragraphID == paragraphID,
                  let range = anchor.resolvedRange(in: text) else { continue }
            if let color = note.color { attributed.addAttribute(.backgroundColor, value: color.nsColor.withAlphaComponent(colorScheme == .dark ? 0.40 : 0.32), range: range) }
            if !note.text.isEmpty {
                attributed.addAttributes([.underlineStyle: NSUnderlineStyle.single.union(.patternDot).rawValue,
                                          .underlineColor: NSColor.controlAccentColor], range: range)
            }
        }
        guard let storage = view.textStorage, !storage.isEqual(to: attributed) else { return }
        let oldText = view.string, selectedRange = view.selectedRange()
        context.coordinator.isUpdating = true
        storage.setAttributedString(attributed)
        if oldText == text && NSMaxRange(selectedRange) <= attributed.length { view.setSelectedRange(selectedRange) }
        else { view.setSelectedRange(NSRange(location: 0, length: 0)) }
        context.coordinator.isUpdating = false
        view.invalidateIntrinsicContentSize()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ParagraphTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite, let manager = view.layoutManager,
              let container = view.textContainer else { return nil }
        // Temporarily set the width explicitly, independent of the previous view frame.
        container.widthTracksTextView = false
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = ceil(manager.usedRect(for: container).height)
        return CGSize(width: width, height: max(height, fontSize * 1.4))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableParagraphText
        var isUpdating = false
        init(parent: SelectableParagraphText) { self.parent = parent }
        func anchor(in view: NSTextView) -> ResearchAnchor? {
            let range = view.selectedRange()
            let source = view.string as NSString
            guard range.location != NSNotFound, range.length > 0,
                  range.location <= source.length, range.length <= source.length - range.location else { return nil }
            let quote = source.substring(with: range)
            let anchor = ResearchAnchor(paragraphID: parent.paragraphID, quote: quote, rangeLocation: range.location, rangeLength: range.length)
            return anchor.valid ? anchor : nil
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let view = notification.object as? NSTextView else { return }
            let next = anchor(in: view)
            // Dispatch out of native selection callback to avoid modifying SwiftUI state during layout.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, self.anchor(in: view) == next else { return }
                if let next { self.parent.notebook.selection = next }
                else if self.parent.notebook.selection?.paragraphID == self.parent.paragraphID {
                    self.parent.notebook.selection = nil
                }
            }
        }
    }
}

final class ParagraphTextView: NSTextView {
    var selectionAnchor: (() -> ResearchAnchor?)?
    var highlightAction: ((ResearchColor, ResearchAnchor) -> Void)?
    var commentAction: ((ResearchAnchor) -> Void)?
    private var menuAnchor: ResearchAnchor?
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let anchor = selectionAnchor?() else { return super.menu(for: event) }
        menuAnchor = anchor
        let menu = NSMenu()
        for color in ResearchColor.allCases {
            let item = NSMenuItem(title: L("\(color.label)高亮", "\(color.label) highlight"), action: #selector(highlightFromMenu(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = color.rawValue
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let comment = NSMenuItem(title: L("添加批注", "Add annotation"), action: #selector(commentFromMenu(_:)), keyEquivalent: "")
        comment.target = self; menu.addItem(comment)
        let copyItem = NSMenuItem(title: L("复制", "Copy"), action: #selector(copy(_:)), keyEquivalent: "")
        copyItem.target = self; menu.addItem(copyItem)
        return menu
    }
    @objc private func highlightFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let color = ResearchColor(rawValue: name), let anchor = menuAnchor else { return }
        highlightAction?(color, anchor)
    }
    @objc private func commentFromMenu(_ sender: NSMenuItem) {
        guard let anchor = menuAnchor else { return }; commentAction?(anchor)
    }
}

struct ResearchNotesView: View {
    @ObservedObject var notebook: ResearchNotebook
    @State private var query = ""
    @State private var pendingDelete: ResearchNote?
    private var filteredNotes: [ResearchNote] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return notebook.notes.filter { q.isEmpty || $0.text.localizedCaseInsensitiveContains(q) || ($0.anchor?.quote.localizedCaseInsensitiveContains(q) ?? false) }
    }
    private var anchor: ResearchAnchor? {
        if let id = notebook.editingNoteID { return notebook.notes.first(where: { $0.id == id })?.anchor }
        return notebook.standaloneDraft ? nil : (notebook.draftAnchor ?? notebook.selection)
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = notebook.error {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Color.orange)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let selected = notebook.selection { selectionCard(selected) }
            composer
            Divider()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("搜索笔记和原文", "Search notes and source"), text: $query).textFieldStyle(.plain)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help(L("清空搜索", "Clear search")) }
            }.padding(9).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7)).padding(12)
            if filteredNotes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "note.text").font(.system(size: 29, weight: .light)).foregroundStyle(.secondary)
                    Text(query.isEmpty ? L("记录你的阅读发现", "Capture your discoveries") : L("没有匹配的笔记", "No matching notes")).font(.subheadline.weight(.semibold))
                    Text(query.isEmpty ? L("选中文字高亮或添加批注，也可以随时写下独立笔记。", "Select text to highlight or annotate, or write a standalone note.") : L("试试其他关键词。", "Try another search.")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filteredNotes) { note in noteCard(note) }
                    }.padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: notebook.activeBookID) { _ in query = ""; pendingDelete = nil }
        .confirmationDialog(L("删除这条笔记？", "Delete this note?"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button(L("删除", "Delete"), role: .destructive) { if let note = pendingDelete { notebook.delete(note.id) }; pendingDelete = nil }
            Button(L("取消", "Cancel"), role: .cancel) { pendingDelete = nil }
        } message: { Text(L("笔记与对应高亮会一起移除，原始文献不会改变。", "The note and its highlight will be removed. The original document stays unchanged.")) }
    }
    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("文献笔记", "Research notes")).font(.system(size: 16, weight: .semibold))
                Text(L("\(notebook.notes.count) 条记录 · 本机保存", "\(notebook.notes.count) notes · Stored locally")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                notebook.cancelEditing(); notebook.standaloneDraft = true; notebook.draftAnchor = nil
            } label: { Image(systemName: "square.and.pencil").frame(width: 26, height: 26) }
                .buttonStyle(.borderless).help(L("新建独立笔记", "New standalone note")).accessibilityLabel(L("新建独立笔记", "New standalone note"))
                .disabled(notebook.activeBookID == nil || !notebook.draft.isEmpty)
            Button(action: export) { Image(systemName: "square.and.arrow.up").frame(width: 26, height: 26) }
                .buttonStyle(.borderless).help(L("导出 Markdown", "Export Markdown")).accessibilityLabel(L("导出笔记", "Export notes")).disabled(notebook.notes.isEmpty)
        }.padding(14)
    }
    private func selectionCard(_ selected: ResearchAnchor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L("选中原文 · \(selected.locationLabel)", "Selected text · \(selected.locationLabel)"), systemImage: "text.cursor").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { notebook.selection = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help(L("清除选中文本", "Clear selection"))
            }
            Text(selected.quote).font(.system(size: 12, design: .serif)).lineLimit(2).textSelection(.enabled)
        }.padding(12).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 9)).padding([.horizontal, .top], 12)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(notebook.editingNoteID != nil ? L("编辑记录", "Edit note") : (anchor == nil ? L("独立笔记", "Standalone note") : L("批注 · \(anchor!.locationLabel)", "Annotation · \(anchor!.locationLabel)")), systemImage: anchor == nil ? "square.and.pencil" : "text.bubble")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if notebook.editingNoteID != nil || !notebook.draft.isEmpty || notebook.standaloneDraft {
                    Button(L("取消", "Cancel")) { notebook.cancelEditing(); notebook.standaloneDraft = false; notebook.draftAnchor = nil }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            TextEditor(text: $notebook.draft)
                .font(.system(size: 13)).scrollContentBackground(.hidden)
                .frame(height: 56)
                .padding(5)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.10), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if notebook.draft.isEmpty { Text(L("写下想法、问题或发现…", "Write a thought, question, or finding…")).foregroundStyle(.tertiary).font(.system(size: 13)).padding(.top, 7).padding(.leading, 10).allowsHitTesting(false) }
                }
                .onChange(of: notebook.draft) { next in
                    if notebook.editingNoteID == nil, !next.isEmpty, notebook.draftAnchor == nil, !notebook.standaloneDraft {
                        if let selected = notebook.selection { notebook.draftAnchor = selected }
                        else { notebook.standaloneDraft = true }
                    }
                }
            HStack {
                Spacer()
                Button(notebook.editingNoteID == nil ? L("保存笔记", "Save note") : L("保存修改", "Save changes")) {
                    let saved: Bool
                    if let id = notebook.editingNoteID { saved = notebook.update(id, text: notebook.draft) }
                    else { saved = notebook.addNote(text: notebook.draft, anchor: anchor) }
                    if saved { notebook.cancelEditing(); notebook.draftAnchor = nil; notebook.standaloneDraft = false }
                }.buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(notebook.activeBookID == nil || notebook.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(12)
    }
    private func noteCard(_ note: ResearchNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: note.anchor == nil ? "note.text" : (note.text.isEmpty ? "highlighter" : "text.bubble"))
                    .foregroundStyle(note.color?.color ?? Color.accentColor)
                Text(note.anchor?.locationLabel ?? L("独立笔记", "Standalone note")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Menu {
                    if note.anchor != nil { Button(L("回到原文", "Go to source")) { notebook.requestedJump = note } }
                    Button(L("编辑笔记", "Edit note")) { notebook.beginEditing(note) }
                    Button(L("删除记录", "Delete note"), role: .destructive) { pendingDelete = note }
                } label: { Image(systemName: "ellipsis").frame(width: 17, height: 17) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("笔记操作", "Note actions"))
                    .disabled(!notebook.draft.isEmpty && notebook.editingNoteID != note.id)
            }
            if let source = note.anchor?.quote {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(note.color?.color ?? Color.accentColor.opacity(0.55)).frame(width: 3)
                    Text(source).font(.system(size: 12, design: .serif)).lineSpacing(3).lineLimit(6).textSelection(.enabled)
                }.fixedSize(horizontal: false, vertical: true)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
            }
            if !note.text.isEmpty { Text(note.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if note.anchor != nil { Button { notebook.requestedJump = note } label: { Label(L("回到原文", "Go to source"), systemImage: "arrow.up.left") }.font(.caption).buttonStyle(.plain).foregroundStyle(Color.accentColor) }
            }
        }.padding(11).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = L("文献笔记.md", "Research Notes.md")
        let content = notebook.markdown()
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do { try content.write(to: url, atomically: true, encoding: .utf8) }
            catch { notebook.error = L("导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)") }
        }
    }
}
