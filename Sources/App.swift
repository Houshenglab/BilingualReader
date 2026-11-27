import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

enum ReaderBrand {
    static let accent = Color(red: 0.06, green: 0.46, blue: 0.43)
    static let icon: NSImage = {
        if let path = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.png"), let image = NSImage(contentsOf: path) { return image }
        if let path = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns"), let image = NSImage(contentsOf: path) { return image }
        return NSImage(systemSymbolName: "book.pages.fill", accessibilityDescription: "BilingualReader") ?? NSImage()
    }()
}

struct TranslationResult: View {
    @ObservedObject var model: ReaderModel
    let paragraph: ReadingParagraph
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let translation = paragraph.translation {
                Text(translation).font(.system(size: model.fontSize)).lineSpacing(8)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if paragraph.loading {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(LStatus(paragraph.activity ?? "等待翻译…")).font(.callout).foregroundStyle(.secondary)
                    if paragraph.activity == "等待翻译…" {
                        Button(L("优先翻译", "Translate next")) { model.enqueue(paragraph.id) }.font(.caption).buttonStyle(.borderless)
                    }
                }
            } else if model.isPaused && paragraph.activity != nil {
                Label(L("翻译已暂停", "Translation paused"), systemImage: "pause.circle").foregroundStyle(.secondary)
                if let error = paragraph.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                Button(L("继续翻译", "Resume translation")) { model.resume() }.buttonStyle(.bordered)
            } else if let error = paragraph.error {
                Label(L("这一段尚未完成", "This paragraph is incomplete"), systemImage: "exclamationmark.circle").font(.callout)
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button(L("重试这一段", "Retry this paragraph")) { model.enqueue(paragraph.id) }.buttonStyle(.bordered)
            } else {
                Button(L("翻译这一段", "Translate this paragraph")) { model.enqueue(paragraph.id) }.buttonStyle(.bordered)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ParagraphView: View {
    @ObservedObject var model: ReaderModel
    let paragraph: ReadingParagraph
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SelectableParagraphText(text: paragraph.text, paragraphID: paragraph.id, fontSize: model.fontSize, notebook: model.notebook)
            let comments = model.notebook.notes.filter { $0.anchor?.paragraphID == paragraph.id && !$0.text.isEmpty }
            if !comments.isEmpty {
                HStack(spacing: 8) {
                    Button { model.notebook.beginEditing(comments[0]) } label: { Label(L("\(comments.count) 条批注", "Comments: \(comments.count)"), systemImage: "bubble.left.and.bubble.right") }
                        .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
                    Text(comments[0].text).lineLimit(1).foregroundStyle(.secondary)
                }.font(.caption).padding(8).background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
            }
            if paragraph.expanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L("中文译文", "Chinese translation")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("收起", "Hide")) { model.toggle(paragraph.id) }.buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                    }
                    TranslationResult(model: model, paragraph: paragraph)
                }.padding(16).background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Button { model.toggle(paragraph.id) } label: { Label(L("展开中文", "Show translation"), systemImage: "character.bubble") }
                    .buttonStyle(.plain).font(.callout).foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("translate-\(paragraph.id)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
        .onAppear { if model.autoTranslate { model.enqueueAutomatically(paragraph.id) } }
        .onChange(of: model.autoTranslate) { enabled in if enabled { model.enqueueAutomatically(paragraph.id) } }
    }
}

private enum ResearchPanel: String { case translation, notes, ai }

/// Keep SwiftUI content below the real system title bar. On the new macOS window
/// style the content view otherwise extends 32 points behind the traffic lights.
struct ReaderWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) { view.configure() }
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        func configure() {
            guard let window, window.sheetParent == nil, !window.styleMask.contains(.fullScreen) else { return }
            if window.styleMask.contains(.fullSizeContentView) { window.styleMask.remove(.fullSizeContentView) }
            if window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = false }
            if window.titleVisibility != .visible { window.titleVisibility = .visible }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct ReaderView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var restoringAnchor = false
    @State private var panel: ResearchPanel? = .translation
    @StateObject private var floatingAI = FloatingResearchAIController()
    @AppStorage("reader.sidebar.aiWidth") private var aiWidth = 420.0
    @AppStorage("reader.sidebar.notesWidth") private var notesWidth = 360.0
    @AppStorage("reader.sidebar.translationWidth") private var translationWidth = 360.0
    private var panelWidth: Binding<Double> {
        switch panel { case .ai: return $aiWidth; case .notes: return $notesWidth; default: return $translationWidth }
    }
    private var hasSidebar: Bool { panel == .notes || panel == .ai || (panel == .translation && isPDF && model.pdfMode == .original) }
    private var isPDF: Bool { model.documentURL?.pathExtension.lowercased() == "pdf" }
    var body: some View {
        VStack(spacing: 0) {
            if model.library != nil && model.showingLibrary && !model.importing {
                LibraryView(model: model).transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.97)))
            } else {
            toolbar
            if model.documentURL != nil && !model.importing {
                Divider()
                researchNavigation
                ResearchSelectionBar(notebook: model.notebook, showNotes: { panel = .notes }, askAI: {
                    model.researchAI.scope = .selection
                    model.researchAI.question = L("请解释选中的这段文字及其在文献中的含义。", "Explain the selected text and its meaning in the article.")
                    if floatingAI.active { floatingAI.bringForward() } else { panel = .ai }
                })
            }
            Divider()
            if model.importing {
                VStack(spacing: 16) { ProgressView(); Text(L("正在读取文档…", "Opening document…")).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.paragraphs.isEmpty && !(isPDF && model.pdfLayoutPending) { welcome }
            else {
                documentWorkspace
            }
            Divider()
            footer
            }
        }
        .background(ReaderWindowChrome())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.showingLibrary)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in model.saveReadingSession() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in model.saveReadingSession() }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(nsColor: .textBackgroundColor))
        .tint(ReaderBrand.accent)
        .accentColor(ReaderBrand.accent)
        .onChange(of: model.documentID) { _ in panel = isPDF && model.pdfMode == .original ? .translation : nil }
        .onChange(of: model.showingLibrary) { showing in if showing { floatingAI.close() } }
        .onDisappear { floatingAI.close() }
        .onChange(of: model.pdfMode) { mode in
            if mode == PDFReadingMode.original && panel == nil { panel = ResearchPanel.translation }
            if mode == PDFReadingMode.paragraphs && panel == ResearchPanel.translation { panel = nil }
        }
        .onChange(of: model.notebook.commentRequest) { value in if value != nil { panel = .notes } }
        .onChange(of: model.notebook.requestedJump) { note in
            if let anchor = note?.anchor, isPDF, !anchor.pdfRegions.isEmpty && model.pdfMode == .paragraphs { model.pdfMode = .original }
        }
        .onChange(of: model.engine) { _ in model.changeEngine() }
        .sheet(isPresented: $model.showingSettings) { ReaderSettings(model: model) }
        .alert(L("无法完成操作", "Unable to complete the operation"), isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button(L("好", "OK"), role: .cancel) { model.alert = nil }
        } message: { Text(model.alert ?? "") }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard !providers.isEmpty else { return false }
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                            if let data = item as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                            else { continuation.resume(returning: item as? URL) }
                        }
                    }
                    if let url { urls.append(url) }
                }
                if model.library != nil { model.importDocuments(urls) }
                else if let first = urls.first { model.open(first) }
            }
            return true
        }
        .onOpenURL { model.open($0) }
    }
    private var documentWorkspace: some View {
        ReaderResizableSplit(presented: hasSidebar, preferredWidth: panelWidth) { documentContent } side: { researchSidebar }
    }
    @ViewBuilder private var documentContent: some View {
        if let url = model.documentURL, url.pathExtension.lowercased() == "docx" {
            WordView(model: model, url: url).id(model.documentID)
        } else if let url = model.documentURL, isPDF, model.pdfMode == .original {
            LinkedPDF(model: model, url: url).id(model.documentID)
        } else { readingBody }
    }
    @ViewBuilder private var researchSidebar: some View {
        if let panel {
            switch panel {
            case .translation:
                if isPDF && model.pdfMode == .original { PDFTranslationPanel(model: model) }
            case .notes:
                ResearchNotesView(notebook: model.notebook)
            case .ai:
                ResearchAIView(ai: model.researchAI, title: model.documentTitle, paragraphs: model.paragraphs.map(\.text), selectedText: model.notebook.selection?.quote, saveNote: saveAIAnswer, onDetach: detachAI)
            }
        }
    }
    private func saveAIAnswer(_ answer: String) {
        if model.notebook.addNote(text: answer) { model.status = L("AI 回答已保存为文献笔记", "AI response saved as a research note") }
        else { model.alert = model.notebook.error ?? L("笔记保存失败", "Could not save note") }
    }
    private func detachAI() {
        floatingAI.present(model: model, onDock: { panel = ResearchPanel.ai })
        panel = nil
    }
    private var researchNavigation: some View {
        HStack(spacing: 12) {
            Label(L("文献工作台", "Research workspace"), systemImage: "book.pages").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            Spacer()
            if isPDF && model.pdfMode == .original { panelButton(.translation, title: L("译文", "Translation"), icon: "character.bubble") }
            panelButton(.notes, title: model.notebook.notes.isEmpty ? L("笔记", "Notes") : L("笔记 · \(model.notebook.notes.count)", "Notes · \(model.notebook.notes.count)"), icon: "note.text")
            panelButton(.ai, title: L("AI 助手", "AI assistant"), icon: "sparkles")
        }.padding(.horizontal, 20).padding(.vertical, 7)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    private func panelButton(_ target: ResearchPanel, title: String, icon: String) -> some View {
        Button {
            if target == .ai && floatingAI.active { floatingAI.bringForward(); return }
            panel = panel == target ? nil : target
        } label: {
            Label(title, systemImage: icon).font(.callout.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle((panel == target || target == .ai && floatingAI.active) ? Color.accentColor : Color.primary)
                .background((panel == target || target == .ai && floatingAI.active) ? Color.accentColor.opacity(0.11) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).help(panel == target ? L("收起\(title)", "Hide \(title)") : L("打开\(title)", "Show \(title)"))
            .accessibilityAddTraits(panel == target || target == .ai && floatingAI.active ? .isSelected : [])
    }
    private var toolbar: some View {
        HStack(spacing: 16) {
            if model.library != nil {
                Button { model.returnToLibrary() } label: { Label(L("书架", "Library"), systemImage: "chevron.left") }
                    .help(L("返回书架，保存阅读位置", "Return to library and save reading position"))
            }
            Button { model.chooseFile() } label: { Image(systemName: "plus") }
                .help(L("打开或更换文档（⌘O）", "Open or switch document (⌘O)")).accessibilityLabel(L("打开文档", "Open document"))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.documentTitle)
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    .help(model.documentURL?.lastPathComponent ?? "BilingualReader")
                Text(model.documentURL == nil ? L("本地文档 · 中英对照", "Local document · Bilingual view") : isPDF ? (model.pdfLayoutPending ? L("PDF · 原页阅读", "PDF · Original pages") : L("PDF · \(model.pages.count) 页", "PDF · \(model.pages.count) pages")) : L("\(model.documentURL!.pathExtension.uppercased()) · 段落对照", "\(model.documentURL!.pathExtension.uppercased()) · Paragraph view"))
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            if isPDF && !model.importing {
                Picker(L("阅读方式", "Reading mode"), selection: $model.pdfMode) {
                    Text(L("原页阅读", "Original")).tag(PDFReadingMode.original)
                    Text(L("段落对照", "Bilingual")).tag(PDFReadingMode.paragraphs)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 192).disabled(model.pdfLayoutPending)
                    .onChange(of: model.pdfMode) { mode in
                        if mode == .paragraphs, let id = model.selectedPDFParagraph,
                           model.paragraphs.indices.contains(id), ["metadata", "figure"].contains(model.paragraphs[id].kind) { model.showPDFDetails = true }
                    }
            }
            if model.documentURL != nil {
                readingMenu
                if model.isPaused {
                    Button { model.resume() } label: { Label(L("继续翻译", "Resume translation"), systemImage: "play.fill") }.buttonStyle(.borderedProminent)
                } else if model.busy {
                    Button { model.pause() } label: { Label(L("暂停翻译", "Pause translation"), systemImage: "pause") }
                } else {
                    Button { model.translateAll() } label: { Label(L("翻译全文", "Translate all"), systemImage: "character.bubble") }
                        .buttonStyle(.borderedProminent).disabled(!model.documentReady || model.importing || model.clearingCache)
                }
            }
            Button { model.showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .help(L("设置翻译服务与缓存", "Translation services and cache")).accessibilityLabel(L("设置", "Settings"))
        }.controlSize(.regular).padding(.horizontal, 20).padding(.vertical, 11)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    private var readingMenu: some View {
        Menu {
            if !isPDF || model.pdfMode == .paragraphs {
                Toggle(L("随阅读翻译", "Translate while reading"), isOn: $model.autoTranslate).disabled(!model.documentReady || model.isPaused)
            }
            Button(L("翻译全部未完成段落", "Translate all remaining paragraphs")) { model.translateAll() }
                .disabled(!model.documentReady || model.importing || model.clearingCache)
            Button(L("收起全部译文", "Hide all translations")) { model.collapseAll() }
            if model.busy || model.isPaused { Button(L("停止并清空待翻译队列", "Stop and clear translation queue")) { model.stop() } }
            Divider()
            Button(L("增大阅读字号", "Increase text size")) { model.fontSize = min(28, model.fontSize + 2) }
            Button(L("减小阅读字号", "Decrease text size")) { model.fontSize = max(16, model.fontSize - 2) }
            Button(L("恢复默认字号", "Reset text size")) { model.fontSize = 20 }
            if isPDF { Toggle(L("显示辅助文字", "Show supporting text"), isOn: $model.showPDFDetails) }
            Divider()
            Button(L("导出中英对照…", "Export bilingual text…")) { model.export() }
        } label: { Text(L("阅读", "Reading")) }.fixedSize()
    }
    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isPaused ? "pause.circle" : model.busy ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                .foregroundStyle(model.isPaused ? Color.orange : Color.secondary)
            Text(model.status).lineLimit(1).help(model.status)
            Spacer(minLength: 16)
            if model.pendingCount > 0 { Text(L("待完成 \(model.pendingCount)", "Pending: \(model.pendingCount)")).monospacedDigit() }
            if model.documentURL != nil { Text(L("已译 \(model.translatedCount) 段", "Translated: \(model.translatedCount)")).monospacedDigit() }
            Text(LStatus(model.engine.rawValue)).foregroundStyle(.tertiary)
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(nsImage: ReaderBrand.icon).resizable().frame(width: 80, height: 80)
            VStack(spacing: 12) {
                Text(L("让理解，跟上阅读。", "Read with greater understanding.")) .font(.system(size: 30, weight: .semibold))
                Text(L("保留原文，在需要时展开中文。", "Read the original. Reveal the translation when needed."))
                    .font(.system(size: 16)).foregroundStyle(.secondary)
            }
            Button { model.chooseFile() } label: { Label(L("打开文档", "Open document"), systemImage: "folder") }
                .buttonStyle(.borderedProminent).controlSize(.large)
            HStack(spacing: 24) {
                Label(L("PDF 原页与段落对照", "Original PDF pages and paragraph view"), systemImage: "doc.richtext")
                Label(L("Word 段落内翻译", "Inline Word translations"), systemImage: "text.alignleft")
            }.font(.callout).foregroundStyle(.secondary)
            Text(L("也可拖入 PDF、DOCX 或 TXT", "Or drop PDF, DOCX or TXT files")).font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Text(L("文档在本机读取，仅待翻译文字发送至所选服务。", "Documents are read locally. Only text to be translated is sent to the chosen service."))
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 24)
        }.frame(maxWidth: .infinity)
    }
    var readingBody: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                if !model.pages.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            Text(L("页码", "Pages")).font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
                            ForEach(model.pages, id: \.self) { page in
                                Button("\(page)") {
                                    if let paragraph = model.readingParagraphs.first(where: { $0.sourceRegions.contains { $0.page == page } || $0.page == page }) { proxy.scrollTo(paragraph.id, anchor: .top) }
                                }.buttonStyle(.plain).font(.callout.monospacedDigit())
                                    .frame(width: 32, height: 32)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }.padding(16)
                    }.frame(width: 64).background(Color(nsColor: .windowBackgroundColor))
                    Divider()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.readingParagraphs) { paragraph in
                            if let page = paragraph.page, paragraph.id == 0 || model.paragraphs[paragraph.id - 1].page != page {
                                Text(L("第 \(page) 页", "Page \(page)")).font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.top, 24)
                            }
                            if isPDF {
                                HStack {
                                    Text(paragraph.kind == "heading" ? L("标题", "Heading") : paragraph.kind == "caption" ? L("图表说明", "Caption") : paragraph.kind == "reference" ? L("参考文献", "Reference") : L("英文原文", "English original"))
                                        .font(.caption).foregroundStyle(.tertiary)
                                    Spacer()
                                    Button { model.selectedPDFParagraph = paragraph.id; model.pdfMode = .original } label: { Label(L("查看原页", "View original page"), systemImage: "arrow.up.left.square") }
                                        .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                                }.padding(.top, 24)
                            }
                            ParagraphView(model: model, paragraph: paragraph).id(paragraph.id)
                                .background(GeometryReader { geometry in Color.clear.preference(key: ReadingPositionKey.self, value: [paragraph.id: geometry.frame(in: .named("readingScroll"))]) })
                            Divider().opacity(0.5)
                        }
                    }.frame(maxWidth: 760).padding(.horizontal, 40).padding(.vertical, 24).frame(maxWidth: .infinity)
                }.coordinateSpace(name: "readingScroll").id(model.documentID)
                .onPreferenceChange(ReadingPositionKey.self) { positions in
                    guard !restoringAnchor, let top = ReaderModel.visibleParagraph(in: positions) else { return }
                    model.readingParagraphID = top
                }
                .onChange(of: model.notebook.requestedJump) { note in
                    if let anchor = note?.anchor, anchor.pdfRegions.isEmpty, let id = anchor.paragraphID, model.paragraphs.indices.contains(id) {
                        if model.readingParagraphs.contains(where: { $0.id == id }) {
                            proxy.scrollTo(id, anchor: .center)
                            DispatchQueue.main.async { model.notebook.requestedJump = nil }
                        } else { model.showPDFDetails = true; DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center); model.notebook.requestedJump = nil } }
                    }
                }
                .onAppear {
                    restoringAnchor = true
                    let target = model.selectedPDFParagraph ?? model.readingParagraphID
                    DispatchQueue.main.async {
                        if let target { proxy.scrollTo(target, anchor: .top) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { restoringAnchor = false }
                    }
                }
            }
        }
    }
}

struct ReaderSettings: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var showingAzure = false
    @AppStorage(ReaderLanguage.preferenceKey) private var interfaceLanguage = ReaderLanguage.system.rawValue
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Color.accentColor)
                Text(L("阅读设置", "Reading settings")).font(.title3.bold())
                Spacer()
                Button(L("完成", "Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            Form {
                Section {
                    Picker(L("界面语言", "Interface language"), selection: $interfaceLanguage) {
                        ForEach(ReaderLanguage.allCases) { language in Text(language.displayName).tag(language.rawValue) }
                    }
                    Text(L("重新打开应用后生效。", "Changes apply when you reopen the app.")).font(.caption).foregroundStyle(.secondary)
                } header: { Label(L("界面", "Interface"), systemImage: "globe") }
                Section {
                    Picker(L("翻译服务", "Translation service"), selection: $model.engine) { ForEach(TranslationEngine.allCases) { Text(LStatus($0.rawValue)).tag($0) } }
                    Text(L("必应和 Google 无需填写密钥。点击原文展开中文，也可以开启随阅读翻译。", "Bing and Google do not require an API key. Click the original text to show its translation, or turn on translation while reading."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L("配置微软官方翻译…", "Configure Microsoft Translator…")) { showingAzure = true }
                } header: { Label(L("联网翻译", "Online translation"), systemImage: "character.bubble") }
                Section {
                    LabeledContent(L("已缓存译文", "Cached translations"), value: L("\(model.cacheCount) 段", "\(model.cacheCount) paragraphs"))
                    LabeledContent(L("占用空间", "Disk space"), value: ByteCountFormatter.string(fromByteCount: model.cacheBytes, countStyle: .file))
                    HStack {
                        Text(L("清理翻译缓存", "Clear translation cache"))
                        Spacer()
                        if model.clearingCache { ProgressView().controlSize(.small) }
                        Button(L("清理…", "Clear…"), role: .destructive) { confirmClear = true }
                            .disabled(model.clearingCache || model.cacheCount == 0 && model.cacheBytes == 0)
                    }
                    Text(L("缓存用于再次阅读时复用译文。清理会停止翻译并收起当前中文；原文件和服务配置保留。", "Cached translations are reused when you read again. Clearing stops translation and hides current translations, keeping original files and service settings."))
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Label(L("本机缓存", "Local cache"), systemImage: "internaldrive") }
                Section {
                    LabeledContent("BilingualReader", value: "0.9.0")
                    Text(L("文档与笔记在本机保存。翻译或主动发送 AI 提问时，所选文字会发送至配置的服务。", "Documents and notes are stored locally. Selected text is sent to your configured service when you translate or send an AI question."))
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Label(L("关于", "About"), systemImage: "book.closed") }
            }.formStyle(.grouped)
        }.frame(width: 560, height: 640)
        .task { await model.refreshCacheInfo() }
        .onChange(of: model.translatedCount) { _ in Task { await model.refreshCacheInfo() } }
        .sheet(isPresented: $showingAzure) { TranslationSettings(model: model) }
        .alert(L("清理全部翻译缓存？", "Clear all cached translations?"), isPresented: $confirmClear) {
            Button(L("取消", "Cancel"), role: .cancel) { }
            Button(L("清理缓存", "Clear cache"), role: .destructive) { model.clearTranslationCache() }
        } message: { Text(L("已缓存的译文将被删除，下次展开中文时重新联网翻译。原文件不会改变。", "Cached translations will be removed. They will be fetched again when you reveal a translation. Original files stay unchanged.")) }
    }
}

struct TranslationSettings: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var region = UserDefaults.standard.string(forKey: "azureRegion") ?? "global"
    @State private var confirmed = UserDefaults.standard.bool(forKey: "azureF0Confirmed")
    @State private var message = ""
    @State private var hasSavedKey = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("配置微软官方免费翻译", "Set up Microsoft Translator (free)")).font(.title2.bold())
            Text(L("选择 Azure Translator 的 F0 免费档：每月 200 万字符，额度用完后停止。请不要选择 S1 或其他付费档。", "Choose the Azure Translator F0 free tier: 2 million characters per month. Translation stops when the quota is reached. Do not select S1 or other paid tiers."))
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Link(L("打开 Azure 控制台创建 Translator 资源", "Open Azure to create a Translator resource"), destination: URL(string: "https://portal.azure.com/#create/Microsoft.CognitiveServicesTextTranslation")!)
            Text(L("创建后，在资源的「密钥和终结点」复制密钥与区域。首次注册可能需要付款方式验证，以 Azure 页面为准。", "After creation, copy the key and region from Keys and Endpoint. Azure may require payment verification during sign-up."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SecureField(hasSavedKey ? L("已保存密钥；留空保留，填写则替换", "Key saved; leave blank to keep it") : L("粘贴 F0 资源的密钥", "Paste your F0 resource key"), text: $key).textFieldStyle(.roundedBorder)
            HStack { Text(L("区域", "Region")); TextField(L("例如 global 或 eastasia", "e.g. global or eastasia"), text: $region).textFieldStyle(.roundedBorder) }
            Text(L("Global 资源填写 global；其他资源填写页面列出的区域。密钥保存在 macOS 钥匙串，不写入文档或日志。", "Use global for Global resources, or the region shown by Azure. Keys are stored in the macOS Keychain, not in documents or logs."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle(L("我确认这个 Translator 资源使用 F0 免费档", "I confirm this Translator resource uses the F0 free tier"), isOn: $confirmed)
            Text(L("应用无法从密钥判断定价档。免费保障来自 Azure 的 F0 资源；不要把付费资源的密钥填在这里。", "The app cannot infer the pricing tier from the key. Use an Azure F0 resource; do not enter a key for a paid resource."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.red) }
            HStack {
                Button(L("移除已保存密钥", "Remove saved key")) {
                    do { try CredentialStore.remove(); UserDefaults.standard.set(false, forKey: "azureF0Confirmed"); hasSavedKey = false; confirmed = false; message = L("已移除密钥", "Key removed") }
                    catch { message = error.localizedDescription }
                }.disabled(!hasSavedKey)
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("保存并使用", "Save and use")) {
                    do {
                        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty { try CredentialStore.save(clean) }
                        UserDefaults.standard.set(region.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "azureRegion")
                        UserDefaults.standard.set(true, forKey: "azureF0Confirmed")
                        model.engine = .azure
                        dismiss()
                    } catch { message = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(!confirmed || (!hasSavedKey && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }.padding(28).frame(width: 550)
            .onAppear { hasSavedKey = CredentialStore.read() != nil }
    }
}

#if !READER_PREVIEW
@main
struct BilingualReaderApp: App {
    @NSApplicationDelegateAdaptor(ReaderAppDelegate.self) private var delegate
    @StateObject private var model = ReaderModel(library: LibraryStore())
    var body: some Scene {
        WindowGroup("BilingualReader") {
            ReaderView(model: model)
                .onAppear {
                    if model.documentURL == nil, let path = CommandLine.arguments.dropFirst().first, !path.hasPrefix("-") { model.open(URL(fileURLWithPath: path)) }
                    delegate.model = model
                    NSApp.applicationIconImage = ReaderBrand.icon
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1210, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("导入文档…", "Import documents…")) { model.chooseFile() }.keyboardShortcut("o")
                Button(L("返回书架", "Return to library")) { model.returnToLibrary() }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandMenu(L("阅读", "Reading")) {
                Button(L("导出中英对照…", "Export bilingual text…")) { model.export() }.disabled(model.paragraphs.isEmpty)
                Button(L("收起全部中文", "Hide all translations")) { model.collapseAll() }
                Button(L("翻译全文", "Translate all")) { model.translateAll() }.disabled(!model.documentReady || model.paragraphs.isEmpty)
                Button(model.isPaused ? L("继续翻译", "Resume translation") : L("暂停翻译", "Pause translation")) { if model.isPaused { model.resume() } else { model.pause() } }
                Button(L("停止翻译", "Stop translation")) { model.stop() }
                Button(L("设置与缓存…", "Settings & cache…")) { model.showingSettings = true }.keyboardShortcut(",")
            }
        }
    }
}

#endif

struct ReadingPositionKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
@MainActor final class ReaderAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ReaderModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task { await model.flushLibrarySave(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
