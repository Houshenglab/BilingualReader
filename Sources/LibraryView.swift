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
            HStack(spacing: 20) {
                Image(systemName: "books.vertical").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("我的书架").font(.system(size: 20, weight: .semibold))
                    Text("\(model.libraryBooks.count) 份文档 · 随时继续阅读").font(.caption).foregroundStyle(.secondary)
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
            }.padding(24)
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
                VStack(spacing: 12) {
                    HStack {
                        Text("继续阅读 · 双指左右滑动翻书架").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(selectedIndex + 1) / \(books.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.padding(.horizontal, 36).padding(.top, 28)
                    GeometryReader { proxy in
                        ZStack {
                            Ellipse().fill(Color.black.opacity(0.08)).frame(width: min(proxy.size.width - 80, 760), height: 30)
                                .blur(radius: 18).offset(y: 150)
                            ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                                if abs(index - selectedIndex) <= 4 {
                                    let delta = index - selectedIndex
                                    Button {
                                        if delta == 0 { model.openBook(book) }
                                        else { withAnimation(motion) { selectedID = book.id } }
                                    } label: {
                                        BookCover(book: book, url: model.libraryCovers[book.id])
                                            .frame(width: 190, height: 265)
                                            .rotation3DEffect(.degrees(delta == 0 ? 0 : delta < 0 ? 52 : -52), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                                            .scaleEffect(delta == 0 ? 1.08 : 0.9 - Double(abs(delta)) * 0.035)
                                            .opacity(abs(delta) > 3 ? 0.5 : 1)
                                    }.buttonStyle(.plain).disabled(model.libraryBusy)
                                        .offset(x: CGFloat(delta) * min(112, proxy.size.width / 7), y: delta == 0 ? -8 : 6)
                                        .zIndex(Double(10 - abs(delta)))
                                        .accessibilityLabel("\(book.title)，\(detail(book))")
                                        .contextMenu { bookMenu(book) }
                                }
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .background(ShelfScrollInput { distance in
                                if !model.libraryBusy { move(distance) }
                            })
                            .simultaneousGesture(DragGesture(minimumDistance: 25).onEnded { value in
                                if abs(value.translation.width) > abs(value.translation.height) { move(value.translation.width < 0 ? 1 : -1) }
                            })
                    }.frame(minHeight: 310, maxHeight: 400).clipped()
                    if let book = selected {
                        VStack(spacing: 10) {
                            Text(book.title).font(.system(size: 23, weight: .medium, design: .serif)).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 620)
                            Text(detail(book)).font(.callout).foregroundStyle(.secondary)
                            HStack(spacing: 24) {
                                Button { move(-1) } label: { Image(systemName: "chevron.left") }.disabled(selectedIndex == 0).help("上一本")
                                Button { model.openBook(book) } label: { Label(book.page > 1 || book.translatedCount > 0 ? "继续阅读" : "开始阅读", systemImage: "book") }
                                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.libraryBusy)
                                Button { move(1) } label: { Image(systemName: "chevron.right") }.disabled(selectedIndex == books.count - 1).help("下一本")
                            }.padding(.top, 10)
                        }.padding(.horizontal, 32)
                    }
                    Spacer(minLength: 24)
                }
                .onMoveCommand { direction in if direction == .left { move(-1) }; if direction == .right { move(1) } }
            }
            Divider()
            HStack(spacing: 10) {
                if model.libraryBusy { ProgressView().controlSize(.small) }
                Text(model.libraryStatus.isEmpty ? "文档保存在本机 · 阅读位置自动记住" : model.libraryStatus)
                Spacer()
                Text("PDF · WORD · TXT").tracking(1)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 14)
        }
        .background(LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.035)], startPoint: .top, endPoint: .bottom))
        .onChange(of: query) { _ in selectedID = nil }
        .onChange(of: model.libraryFilter) { _ in selectedID = nil }
        .alert("从书架移除？", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), presenting: removal) { book in
            Button("取消", role: .cancel) { removal = nil }
            Button("移除", role: .destructive) { model.removeBook(book); removal = nil }
        } message: { book in Text("将移除“\(book.title)”的书库副本和阅读记录，你导入时的原文件不会被删除。") }
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
