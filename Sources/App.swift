import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

enum ReaderBrand {
    static let icon: NSImage = {
        if let path = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.png"), let image = NSImage(contentsOf: path) { return image }
        if let path = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns"), let image = NSImage(contentsOf: path) { return image }
        return NSImage(systemSymbolName: "book.pages.fill", accessibilityDescription: "双语阅读") ?? NSImage()
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
                    Text(paragraph.activity ?? "等待翻译…").font(.callout).foregroundStyle(.secondary)
                    if paragraph.activity == "等待翻译…" {
                        Button("优先翻译") { model.enqueue(paragraph.id) }.font(.caption).buttonStyle(.borderless)
                    }
                }
            } else if model.isPaused && paragraph.activity != nil {
                Label("翻译已暂停", systemImage: "pause.circle").foregroundStyle(.secondary)
                if let error = paragraph.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                Button("继续翻译") { model.resume() }.buttonStyle(.bordered)
            } else if let error = paragraph.error {
                Label("这一段尚未完成", systemImage: "exclamationmark.circle").font(.callout)
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("重试这一段") { model.enqueue(paragraph.id) }.buttonStyle(.bordered)
            } else {
                Button("翻译这一段") { model.enqueue(paragraph.id) }.buttonStyle(.bordered)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ParagraphView: View {
    @ObservedObject var model: ReaderModel
    let paragraph: ReadingParagraph
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(paragraph.text).font(.system(size: model.fontSize, design: .serif))
                .lineSpacing(8).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if paragraph.expanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("中文译文").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Button("收起") { model.toggle(paragraph.id) }.buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                    }
                    TranslationResult(model: model, paragraph: paragraph)
                }.padding(16).background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Button { model.toggle(paragraph.id) } label: { Label("展开中文", systemImage: "character.bubble") }
                    .buttonStyle(.plain).font(.callout).foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("translate-\(paragraph.id)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
        .onAppear { if model.autoTranslate { model.enqueueAutomatically(paragraph.id) } }
        .onChange(of: model.autoTranslate) { enabled in if enabled { model.enqueueAutomatically(paragraph.id) } }
    }
}

struct ReaderView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var restoringAnchor = false
    private var isPDF: Bool { model.documentURL?.pathExtension.lowercased() == "pdf" }
    var body: some View {
        VStack(spacing: 0) {
            if model.library != nil && model.showingLibrary && !model.importing {
                LibraryView(model: model).transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.97)))
            } else {
            toolbar
            Divider()
            if model.importing {
                VStack(spacing: 16) { ProgressView(); Text("正在读取文档…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.paragraphs.isEmpty { welcome }
            else {
                HSplitView {
                    if let url = model.documentURL, url.pathExtension.lowercased() == "docx" {
                        WordView(model: model, url: url).id(model.documentID)
                    } else if let url = model.documentURL, isPDF, model.pdfMode == .original {
                        LinkedPDF(model: model, url: url).id(model.documentID).frame(minWidth: 420, idealWidth: 720)
                        PDFTranslationPanel(model: model).frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
                    } else { readingBody }
                }
            }
            Divider()
            footer
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.showingLibrary)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in model.saveReadingSession() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in model.saveReadingSession() }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(nsColor: .textBackgroundColor))
        .accentColor(Color(red: 0.22, green: 0.40, blue: 0.66))
        .onChange(of: model.engine) { _ in model.changeEngine() }
        .sheet(isPresented: $model.showingSettings) { ReaderSettings(model: model) }
        .alert("无法完成操作", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("好", role: .cancel) { model.alert = nil }
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
    private var toolbar: some View {
        HStack(spacing: 16) {
            if model.library != nil {
                Button { model.returnToLibrary() } label: { Label("书架", systemImage: "chevron.left") }
                    .help("返回书架，保存阅读位置")
            }
            Button { model.chooseFile() } label: { Image(systemName: "plus") }
                .help("打开或更换文档（⌘O）").accessibilityLabel("打开文档")
            VStack(alignment: .leading, spacing: 4) {
                Text(model.documentTitle)
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    .help(model.documentURL?.lastPathComponent ?? "双语阅读")
                Text(model.documentURL == nil ? "本地文档 · 中英对照" : isPDF ? "PDF · \(model.pages.count) 页" : "\(model.documentURL!.pathExtension.uppercased()) · 段落对照")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            if isPDF && !model.importing {
                Picker("阅读方式", selection: $model.pdfMode) {
                    Text("原页阅读").tag(PDFReadingMode.original)
                    Text("段落对照").tag(PDFReadingMode.paragraphs)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 192)
                    .onChange(of: model.pdfMode) { mode in
                        if mode == .paragraphs, let id = model.selectedPDFParagraph,
                           model.paragraphs.indices.contains(id), ["metadata", "figure"].contains(model.paragraphs[id].kind) { model.showPDFDetails = true }
                    }
            }
            if model.documentURL != nil {
                readingMenu
                if model.isPaused {
                    Button { model.resume() } label: { Label("继续翻译", systemImage: "play.fill") }.buttonStyle(.borderedProminent)
                } else if model.busy {
                    Button { model.pause() } label: { Label("暂停翻译", systemImage: "pause") }
                } else {
                    Button { model.translateAll() } label: { Label("翻译全文", systemImage: "character.bubble") }
                        .buttonStyle(.borderedProminent).disabled(!model.documentReady || model.importing || model.clearingCache)
                }
            }
            Button { model.showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .help("设置翻译服务与缓存").accessibilityLabel("设置")
        }.controlSize(.regular).padding(.horizontal, 24).padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    private var readingMenu: some View {
        Menu {
            if !isPDF || model.pdfMode == .paragraphs {
                Toggle("随阅读翻译", isOn: $model.autoTranslate).disabled(!model.documentReady || model.isPaused)
            }
            Button("翻译全部未完成段落") { model.translateAll() }
                .disabled(!model.documentReady || model.importing || model.clearingCache)
            Button("收起全部译文") { model.collapseAll() }
            if model.busy || model.isPaused { Button("停止并清空待翻译队列") { model.stop() } }
            Divider()
            Button("增大阅读字号") { model.fontSize = min(28, model.fontSize + 2) }
            Button("减小阅读字号") { model.fontSize = max(16, model.fontSize - 2) }
            Button("恢复默认字号") { model.fontSize = 20 }
            if isPDF { Toggle("显示辅助文字", isOn: $model.showPDFDetails) }
            Divider()
            Button("导出中英对照…") { model.export() }
        } label: { Text("阅读") }.fixedSize()
    }
    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isPaused ? "pause.circle" : model.busy ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                .foregroundStyle(model.isPaused ? Color.orange : Color.secondary)
            Text(model.status).lineLimit(1).help(model.status)
            Spacer(minLength: 16)
            if model.pendingCount > 0 { Text("待完成 \(model.pendingCount)").monospacedDigit() }
            if model.documentURL != nil { Text("已译 \(model.translatedCount) 段").monospacedDigit() }
            Text(model.engine.rawValue).foregroundStyle(.tertiary)
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(nsImage: ReaderBrand.icon).resizable().frame(width: 80, height: 80)
            VStack(spacing: 12) {
                Text("让理解，跟上阅读。") .font(.system(size: 30, weight: .semibold))
                Text("保留原文，在需要时展开中文。")
                    .font(.system(size: 16)).foregroundStyle(.secondary)
            }
            Button { model.chooseFile() } label: { Label("打开文档", systemImage: "folder") }
                .buttonStyle(.borderedProminent).controlSize(.large)
            HStack(spacing: 24) {
                Label("PDF 原页与段落对照", systemImage: "doc.richtext")
                Label("Word 段落内翻译", systemImage: "text.alignleft")
            }.font(.callout).foregroundStyle(.secondary)
            Text("也可拖入 PDF、DOCX 或 TXT").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Text("文档在本机读取，仅待翻译文字发送至所选服务。")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 24)
        }.frame(maxWidth: .infinity)
    }
    var readingBody: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                if !model.pages.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            Text("页码").font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
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
                                Text("第 \(page) 页").font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.top, 24)
                            }
                            if isPDF {
                                HStack {
                                    Text(paragraph.kind == "heading" ? "标题" : paragraph.kind == "caption" ? "图表说明" : paragraph.kind == "reference" ? "参考文献" : "英文原文")
                                        .font(.caption).foregroundStyle(.tertiary)
                                    Spacer()
                                    Button { model.selectedPDFParagraph = paragraph.id; model.pdfMode = .original } label: { Label("查看原页", systemImage: "arrow.up.left.square") }
                                        .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                                }.padding(.top, 24)
                            }
                            ParagraphView(model: model, paragraph: paragraph).id(paragraph.id)
                                .background(GeometryReader { geometry in Color.clear.preference(key: ReadingPositionKey.self, value: [paragraph.id: geometry.frame(in: .named("readingScroll")).minY]) })
                            Divider().opacity(0.5)
                        }
                    }.frame(maxWidth: 760).padding(.horizontal, 40).padding(.vertical, 24).frame(maxWidth: .infinity)
                }.coordinateSpace(name: "readingScroll").id(model.documentID)
                .onPreferenceChange(ReadingPositionKey.self) { positions in
                    guard !restoringAnchor, let top = positions.filter({ $0.value >= -30 }).min(by: { $0.value < $1.value }) else { return }
                    model.readingParagraphID = top.key
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
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Color.accentColor)
                Text("阅读设置").font(.title3.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            Form {
                Section {
                    Picker("翻译服务", selection: $model.engine) { ForEach(TranslationEngine.allCases) { Text($0.rawValue).tag($0) } }
                    Text("必应和 Google 无需填写密钥。点击原文展开中文，也可以开启随阅读翻译。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("配置微软官方翻译…") { showingAzure = true }
                } header: { Label("联网翻译", systemImage: "character.bubble") }
                Section {
                    LabeledContent("已缓存译文", value: "\(model.cacheCount) 段")
                    LabeledContent("占用空间", value: ByteCountFormatter.string(fromByteCount: model.cacheBytes, countStyle: .file))
                    HStack {
                        Text("清理翻译缓存")
                        Spacer()
                        if model.clearingCache { ProgressView().controlSize(.small) }
                        Button("清理…", role: .destructive) { confirmClear = true }
                            .disabled(model.clearingCache || model.cacheCount == 0 && model.cacheBytes == 0)
                    }
                    Text("缓存用于再次阅读时复用译文。清理会停止翻译并收起当前中文；原文件和服务配置保留。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Label("本机缓存", systemImage: "internaldrive") }
                Section {
                    LabeledContent("双语阅读", value: "0.6.0")
                    Text("文档在本机读取，仅待翻译的文字发送到所选服务。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Label("关于", systemImage: "book.closed") }
            }.formStyle(.grouped)
        }.frame(width: 510, height: 540)
        .task { await model.refreshCacheInfo() }
        .onChange(of: model.translatedCount) { _ in Task { await model.refreshCacheInfo() } }
        .sheet(isPresented: $showingAzure) { TranslationSettings(model: model) }
        .alert("清理全部翻译缓存？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) { }
            Button("清理缓存", role: .destructive) { model.clearTranslationCache() }
        } message: { Text("已缓存的译文将被删除，下次展开中文时重新联网翻译。原文件不会改变。") }
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
            Text("配置微软官方免费翻译").font(.title2.bold())
            Text("选择 Azure Translator 的 F0 免费档：每月 200 万字符，额度用完后停止。请不要选择 S1 或其他付费档。")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Link("打开 Azure 控制台创建 Translator 资源", destination: URL(string: "https://portal.azure.com/#create/Microsoft.CognitiveServicesTextTranslation")!)
            Text("创建后，在资源的「密钥和终结点」复制密钥与区域。首次注册可能需要付款方式验证，以 Azure 页面为准。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SecureField(hasSavedKey ? "已保存密钥；留空保留，填写则替换" : "粘贴 F0 资源的密钥", text: $key).textFieldStyle(.roundedBorder)
            HStack { Text("区域"); TextField("例如 global 或 eastasia", text: $region).textFieldStyle(.roundedBorder) }
            Text("Global 资源填写 global；其他资源填写页面列出的区域。密钥保存在 macOS 钥匙串，不写入文档或日志。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("我确认这个 Translator 资源使用 F0 免费档", isOn: $confirmed)
            Text("应用无法从密钥判断定价档。免费保障来自 Azure 的 F0 资源；不要把付费资源的密钥填在这里。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("移除已保存密钥") {
                    do { try CredentialStore.remove(); UserDefaults.standard.set(false, forKey: "azureF0Confirmed"); hasSavedKey = false; confirmed = false; message = "已移除密钥" }
                    catch { message = error.localizedDescription }
                }.disabled(!hasSavedKey)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存并使用") {
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
        WindowGroup("双语阅读") {
            ReaderView(model: model)
                .onAppear {
                    if model.documentURL == nil, let path = CommandLine.arguments.dropFirst().first, !path.hasPrefix("-") { model.open(URL(fileURLWithPath: path)) }
                    delegate.model = model
                    NSApp.applicationIconImage = ReaderBrand.icon
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1100, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入文档…") { model.chooseFile() }.keyboardShortcut("o")
                Button("返回书架") { model.returnToLibrary() }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandMenu("阅读") {
                Button("导出中英对照…") { model.export() }.disabled(model.paragraphs.isEmpty)
                Button("收起全部中文") { model.collapseAll() }
                Button("翻译全文") { model.translateAll() }.disabled(!model.documentReady || model.paragraphs.isEmpty)
                Button(model.isPaused ? "继续翻译" : "暂停翻译") { if model.isPaused { model.resume() } else { model.pause() } }
                Button("停止翻译") { model.stop() }
                Button("设置与缓存…") { model.showingSettings = true }.keyboardShortcut(",")
            }
        }
    }
}

#endif

struct ReadingPositionKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
@MainActor final class ReaderAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ReaderModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task { await model.flushLibrarySave(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
