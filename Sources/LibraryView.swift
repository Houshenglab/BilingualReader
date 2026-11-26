import SwiftUI
import AppKit

struct LibraryView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("libraryDisplay") private var display = "shelf"
    @State private var query = ""
    @State private var selectedID: String?
    @State private var removal: LibraryBook?
    private var books: [LibraryBook] { model.matchingBooks(query: query) }
    private var selectedIndex: Int { books.firstIndex { $0.id == selectedID } ?? 0 }
    private var selected: LibraryBook? { books.indices.contains(selectedIndex) ? books[selectedIndex] : nil }
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.82) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "books.vertical").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("文献书架").font(.system(size: 20, weight: .semibold))
                    Text("\(model.libraryBooks.count) 份文档 · 阅读、笔记与 AI 助手").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("搜索书名或文档", text: $query).textFieldStyle(.roundedBorder).frame(width: 210)
                    .accessibilityLabel("搜索书架")
                Picker("书架显示方式", selection: $display) {
                    Image(systemName: "rectangle.stack").tag("shelf")
                    Image(systemName: "square.grid.2x2").tag("grid")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 86).help("立体书架 / 封面网格")
                Button { model.chooseFile() } label: { Label("导入文档", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).disabled(model.libraryBusy)
            }.padding(.horizontal, 24).padding(.vertical, 14)
            Divider()
            LibraryCategoryBar(model: model, visibleBooks: books)
            Divider()
            if model.libraryBooks.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "books.vertical").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(Color.accentColor)
                    Text("把想读的，放在这里。") .font(.system(size: 29, weight: .medium, design: .serif))
                    Text("拖入 PDF、Word 或 TXT，下次从上次读到的地方继续。") .foregroundStyle(.secondary)
                    Button("导入第一份文档") { model.chooseFile() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.libraryBusy)
                    Text("可一次选择多份文件 · 原文件保留不变").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if books.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: query.isEmpty ? "folder" : "magnifyingglass").font(.largeTitle)
                    Text(query.isEmpty ? "“\(model.libraryFilterTitle)”里还没有文档" : "这个分类中没有找到匹配文档")
                    if query.isEmpty {
                        Button("导入文档到这里") { model.chooseFile() }.buttonStyle(.borderedProminent).disabled(model.libraryBusy)
                        Button("查看全部文档") { model.libraryFilter = .all }
                    } else { Button("清除搜索") { query = "" } }
                }
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if display == "grid" {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 32)], alignment: .leading, spacing: 36) {
                        ForEach(books) { book in
                            Button { model.openBook(book) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    BookCover(book: book, url: model.libraryCovers[book.id]).frame(width: 160, height: 222)
                                    Text(book.title).font(.system(size: 14, weight: .medium)).lineLimit(2).frame(height: 38, alignment: .topLeading)
                                    Text(detail(book)).font(.caption).foregroundStyle(.secondary)
                                }.frame(width: 180, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(model.libraryBusy).contextMenu { bookMenu(book) }
                        }
                    }.padding(36)
                }
            } else {
                GeometryReader { proxy in
                    if proxy.size.width >= 900 {
                        HStack(spacing: 24) {
                            if let book = selected { readingCard(book, compact: false).frame(width: min(292, max(228, proxy.size.width * 0.24))) }
                            shelfStage
                        }.padding(24)
                    } else {
                        VStack(spacing: 12) {
                            shelfStage
                            if let book = selected { readingCard(book, compact: true) }
                        }.padding(16)
                    }
                }
                .onMoveCommand { direction in if direction == .left { move(-1) }; if direction == .right { move(1) } }
            }
            Divider()
            HStack(spacing: 10) {
                if model.libraryBusy { ProgressView().controlSize(.small) }
                Text(model.libraryStatus.isEmpty ? "文档与笔记保存在本机 · 阅读位置自动记住" : model.libraryStatus)
                Spacer()
                Text("PDF · WORD · TXT").tracking(1)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 9)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: query) { _ in selectedID = nil }
        .onChange(of: model.libraryFilter) { _ in selectedID = nil }
        .alert("从书架移除？", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), presenting: removal) { book in
            Button("取消", role: .cancel) { removal = nil }
            Button("移除", role: .destructive) { model.removeBook(book); removal = nil }
        } message: { book in Text("将移除“\(book.title)”的书库副本和阅读记录，你导入时的原文件不会被删除。") }
    }
    private var shelfStage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("立体书架", systemImage: "rectangle.stack").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(selectedIndex + 1) / \(books.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.top, 16)
            GeometryReader { proxy in
                let layout = ShelfGeometry(count: books.count, selected: selectedIndex, width: proxy.size.width, height: proxy.size.height)
                ZStack {
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                        if layout.indices.contains(index) {
                            let delta = index - selectedIndex
                            Button {
                                if delta == 0 { model.openBook(book) }
                                else { withAnimation(motion) { selectedID = book.id } }
                            } label: {
                                BookCover(book: book, url: model.libraryCovers[book.id])
                                    .frame(width: layout.coverWidth, height: layout.coverHeight)
                                    .compositingGroup()
                                    .rotation3DEffect(.degrees(delta == 0 ? 0 : delta < 0 ? 33 : -33), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
                                    .scaleEffect(delta == 0 ? 1.08 : max(0.78, 0.96 - Double(abs(delta)) * 0.035))
                                    .opacity(delta == 0 ? 1 : 0.999)
                            }.buttonStyle(.plain).disabled(model.libraryBusy)
                                .offset(x: layout.x(for: index), y: delta == 0 ? -3 : 5)
                                .zIndex(Double(10 - abs(delta)))
                                .accessibilityLabel("\(book.title)，\(detail(book))")
                                .contextMenu { bookMenu(book) }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .background(ShelfScrollInput { distance in if !model.libraryBusy { move(distance) } })
                    .simultaneousGesture(DragGesture(minimumDistance: 25).onEnded { value in
                        if abs(value.translation.width) > abs(value.translation.height) { move(value.translation.width < 0 ? 1 : -1) }
                    })
            }.clipped()
            Label("双指左右滑动，或点击封面切换", systemImage: "hand.draw").font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 14)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }
    private func readingCard(_ book: LibraryBook, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 18) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill").foregroundStyle(Color.accentColor)
                Text(book.page > 1 || book.translatedCount > 0 ? "继续阅读" : "准备阅读").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(book.format.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8)
                    .padding(.horizontal, 7).padding(.vertical, 4).background(Color.accentColor.opacity(0.1), in: Capsule()).foregroundStyle(Color.accentColor)
            }
            Text(book.title).font(.system(size: compact ? 17 : 22, weight: .semibold)).lineLimit(compact ? 1 : 4)
                .multilineTextAlignment(.leading).help(book.title).fixedSize(horizontal: false, vertical: true)
            if book.pageCount > 0 {
                ProgressView(value: Double(min(max(1,book.page),book.pageCount)), total: Double(book.pageCount)).tint(Color.accentColor)
            }
            Text(detail(book)).font(.callout).foregroundStyle(.secondary)
            if !compact { Spacer(minLength: 0) }
            VStack(spacing: 8) {
                Button { model.openBook(book) } label: {
                    Label(book.page > 1 || book.translatedCount > 0 ? "继续阅读" : "开始阅读", systemImage: "book").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.libraryBusy)
                HStack(spacing: 8) {
                    Button { move(-1) } label: { Label("上一篇", systemImage: "chevron.left").frame(maxWidth: .infinity) }.disabled(selectedIndex == 0).help("上一篇")
                    Button { move(1) } label: { HStack(spacing: 4) { Text("下一篇"); Image(systemName: "chevron.right") }.frame(maxWidth: .infinity) }.disabled(selectedIndex == books.count - 1).help("下一篇")
                }.controlSize(.regular)
            }
        }.padding(compact ? 14 : 22).frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }
    @ViewBuilder private func bookMenu(_ book: LibraryBook) -> some View {
        Button("打开阅读") { model.openBook(book) }.disabled(model.libraryBusy)
        Menu("移动到分类") {
            Button { moveBook(book, to: nil) } label: {
                if model.libraryOrganization.assignments[book.id] == nil { Label("未分类", systemImage: "checkmark") }
                else { Text("未分类") }
            }
            ForEach(model.libraryOrganization.categories) { category in
                Button { moveBook(book, to: category.id) } label: {
                    if model.libraryOrganization.assignments[book.id] == category.id { Label(category.name, systemImage: "checkmark") }
                    else { Text(category.name) }
                }
            }
        }.disabled(model.libraryBusy)
        Divider()
        Button("从书架移除…", role: .destructive) { removal = book }.disabled(model.libraryBusy)
    }
    private func moveBook(_ book: LibraryBook, to categoryID: String?) {
        Task {
            do { try await model.assignLibraryCategory([book.id], to: categoryID) }
            catch { model.alert = error.localizedDescription }
        }
    }
    private func detail(_ book: LibraryBook) -> String {
        let pages = book.pageCount > 0 ? "第 \(book.page) / \(book.pageCount) 页" : book.format.uppercased()
        return pages + " · 已译 \(book.translatedCount) 段"
    }
    private func move(_ distance: Int) {
        guard !books.isEmpty else { return }
        let index = min(books.count - 1, max(0, selectedIndex + distance))
        withAnimation(motion) { selectedID = books[index].id }
    }
}

struct BookCover: View {
    let book: LibraryBook
    let url: URL?
    @State private var image: NSImage?
    private var tint: Color {
        let values: [Color] = [Color(red: 0.18, green: 0.34, blue: 0.40), Color(red: 0.36, green: 0.29, blue: 0.42), Color(red: 0.56, green: 0.35, blue: 0.25), Color(red: 0.25, green: 0.37, blue: 0.31)]
        return values[(Int(book.id.prefix(2), radix: 16) ?? 0) % values.count]
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if let image {
                    Color.white
                    Image(nsImage: image).resizable().scaledToFit().padding(6)
                } else {
                    tint
                    LinearGradient(colors: [tint, tint.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(alignment: .leading, spacing: 16) {
                        Text(book.format.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(3).opacity(0.65)
                        Rectangle().frame(width: 28, height: 1).opacity(0.5)
                        Text(book.title).font(.system(size: proxy.size.width * 0.12, weight: .medium, design: .serif)).lineLimit(6)
                        Spacer()
                        Image(systemName: "text.book.closed").font(.system(size: 24, weight: .ultraLight)).opacity(0.7)
                    }.foregroundStyle(.white).padding(.vertical, 24).padding(.leading, 24).padding(.trailing, 16)
                }
                LinearGradient(colors: [.black.opacity(0.28), .white.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 13)
                Rectangle().fill(.black.opacity(0.1)).frame(width: 1).offset(x: 12)
            }.clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.1)))
                .shadow(color: .black.opacity(0.19), radius: 12, x: 4, y: 9)
        }.task(id: url) { if let url { image = NSImage(contentsOf: url) } }
    }
}
