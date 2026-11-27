import SwiftUI

private struct CategoryDraft: Identifiable {
    let id = UUID()
    var category: LibraryCategory?
}

struct LibraryCategoryBar: View {
    @ObservedObject var model: ReaderModel
    let visibleBooks: [LibraryBook]
    @State private var editor: CategoryDraft?
    @State private var deletion: LibraryCategory?
    @State private var batch = false
    var body: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryButton(L("全部", "All"), filter: .all, icon: "books.vertical")
                    categoryButton(L("未分类", "Uncategorized"), filter: .uncategorized, icon: "tray")
                    ForEach(model.libraryOrganization.categories) { category in
                        categoryButton(category.name, filter: .category(category.id), icon: "folder")
                            .contextMenu {
                                Button(L("重命名…", "Rename…")) { editor = CategoryDraft(category: category) }
                                Button(L("删除分类…", "Delete category…"), role: .destructive) { deletion = category }
                            }
                    }
                }.padding(.vertical, 2)
            }
            Button { editor = CategoryDraft() } label: { Image(systemName: "folder.badge.plus") }
                .help(L("新建分类", "New category")).accessibilityLabel(L("新建分类", "New category")).accessibilityIdentifier("library-new-category")
            Button { batch = true } label: { Label(L("批量归类", "Organize"), systemImage: "checklist") }
                .disabled(visibleBooks.isEmpty).accessibilityIdentifier("library-batch-category")
        }.buttonStyle(.borderless).padding(.horizontal, 24).padding(.vertical, 8)
            .disabled(model.libraryBusy)
            .sheet(item: $editor) { draft in CategoryEditor(model: model, category: draft.category) }
            .sheet(isPresented: $batch) { LibraryBatchCategorySheet(model: model, books: visibleBooks) }
            .alert(L("删除分类？", "Delete category?"), isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), presenting: deletion) { category in
                Button(L("取消", "Cancel"), role: .cancel) { deletion = nil }
                Button(L("删除分类", "Delete category"), role: .destructive) {
                    Task {
                        do { try await model.deleteLibraryCategory(category.id) }
                        catch { model.alert = error.localizedDescription }
                        deletion = nil
                    }
                }
            } message: { category in
                Text(L("“\(category.name)”中的文档将回到“未分类”，文档、译文和阅读记录都会保留。", "Documents in “\(category.name)” will become uncategorized. Documents, translations and reading history are kept."))
            }
    }
    private func categoryButton(_ name: String, filter: LibraryFilter, icon: String) -> some View {
        Button { model.libraryFilter = filter } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(name).lineLimit(1)
                Text("\(model.matchingBooks(query: "", filter: filter).count)").monospacedDigit().foregroundStyle(.secondary)
            }.font(.callout).padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(model.libraryFilter == filter ? Color.accentColor : Color.primary)
                .background(model.libraryFilter == filter ? Color.accentColor.opacity(0.12) : Color.clear, in: Capsule())
        }.accessibilityLabel(L("\(name)，\(model.matchingBooks(query: "", filter: filter).count) 份文档", "\(name), \(model.matchingBooks(query: "", filter: filter).count) documents"))
            .accessibilityAddTraits(model.libraryFilter == filter ? .isSelected : [])
    }
}

private struct CategoryEditor: View {
    @ObservedObject var model: ReaderModel
    let category: LibraryCategory?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var error: String?
    @State private var saving = false
    init(model: ReaderModel, category: LibraryCategory?) {
        self.model = model; self.category = category
        _name = State(initialValue: category?.name ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(category == nil ? L("新建分类", "New category") : L("重命名分类", "Rename category")).font(.title2.weight(.semibold))
            TextField(L("例如：气候文献、研究方法、待读", "e.g. Climate, Methods, To read"), text: $name).textFieldStyle(.roundedBorder)
                .accessibilityLabel(L("分类名称", "Category name")).accessibilityIdentifier("category-name").onSubmit { save() }
            Text(L("每份文档归入一个分类，可随时调整。名称最多 40 个字。", "Each document belongs to one category and can be moved at any time. Names have up to 40 characters."))
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? L("保存中…", "Saving…") : L("保存", "Save")) { save() }.keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("category-save").buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }.padding(28).frame(width: 420).disabled(saving).interactiveDismissDisabled(saving)
    }
    private func save() {
        guard !saving else { return }
        saving = true; error = nil
        Task {
            do {
                if let category { try await model.renameLibraryCategory(category.id, name: name) }
                else {
                    let created = try await model.createLibraryCategory(name)
                    model.libraryFilter = .category(created.id)
                }
                dismiss()
            } catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}

struct LibraryBatchCategorySheet: View {
    @ObservedObject var model: ReaderModel
    let books: [LibraryBook]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: Set<String> = []
    @State private var destination = "choose"
    @State private var saving = false
    @State private var error: String?
    private var results: [LibraryBook] { books.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("批量归类", "Organize")).font(.title2.weight(.semibold))
            Text(L("选择当前书架中的文档，再移入目标分类。", "Choose documents from this shelf and move them to a category.")).foregroundStyle(.secondary)
            TextField(L("筛选文档", "Filter documents"), text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Button(L("全选当前结果", "Select all results")) { selected.formUnion(results.map(\.id)) }.disabled(results.isEmpty).accessibilityIdentifier("category-batch-select-all")
                Button(L("清空选择", "Clear selection")) { selected.removeAll() }.disabled(selected.isEmpty)
                Spacer()
                Text(L("已选 \(selected.count) 份", "Selected: \(selected.count)")).foregroundStyle(.secondary)
            }.font(.callout)
            List(results) { book in
                Toggle(isOn: Binding(get: { selected.contains(book.id) }, set: { if $0 { selected.insert(book.id) } else { selected.remove(book.id) } })) {
                    HStack {
                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                        Text(book.title).lineLimit(2)
                        Spacer()
                        Text(book.format.uppercased()).font(.caption).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.checkbox).padding(.vertical, 4)
            }.frame(height: 270)
            Picker(L("移入分类", "Move to category"), selection: $destination) {
                Text(L("请选择目标分类", "Choose a category")).tag("choose")
                Text(L("未分类", "Uncategorized")).tag("")
                ForEach(model.libraryOrganization.categories) { category in Text(category.name).tag(category.id) }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("category-batch-cancel")
                Button(saving ? L("正在归类…", "Moving…") : L("移动 \(selected.count) 份文档", "Move \(selected.count) documents")) { move() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty || destination == "choose" || saving).accessibilityIdentifier("category-batch-apply")
            }
        }.padding(28).frame(width: 530).disabled(saving).interactiveDismissDisabled(saving)
    }
    private func move() {
        guard !saving, !selected.isEmpty, destination != "choose" else { return }
        saving = true; error = nil
        let ids = selected, target = destination.isEmpty ? nil : destination
        Task {
            do { try await model.assignLibraryCategory(ids, to: target); dismiss() }
            catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}
