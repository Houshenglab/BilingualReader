import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

enum PDFReadingMode: String, CaseIterable, Identifiable {
    case original = "原页模式"
    case paragraphs = "段落对照"
    var id: String { rawValue }
}

@MainActor
final class ReaderModel: ObservableObject {
    @Published var paragraphs: [ReadingParagraph] = []
    @Published var documentURL: URL?
    @Published var documentID = UUID()
    @Published var engine: TranslationEngine = .google
    @Published var status = "打开 PDF 或 Word，点击段落即可展开中文"
    @Published var importing = false
    @Published var documentReady = true
    @Published var isPaused = false
    @Published private(set) var pendingCount = 0
    @Published var autoTranslate = false
    @Published var pdfMode: PDFReadingMode = .original
    @Published var selectedPDFParagraph: Int?
    @Published var showPDFDetails = false
    @Published var pdfVisiblePage = 1
    @Published var pdfMergeBackup: (paragraphs: [ReadingParagraph], selected: Int)?
    @Published var fontSize: Double = 20
    @Published var alert: String?
    @Published var showingSettings = false
    @Published var cacheCount = 0
    @Published var cacheBytes: Int64 = 0
    @Published var clearingCache = false
    let translator: WebTranslator
    init(translator: WebTranslator = WebTranslator()) { self.translator = translator }
    private var queue: [Int] = []
    private var activeID: Int?
    private var automaticBeforePause = false
    private var transientFailures: [Int] = []
    private var worker: Task<Void, Never>?
    private var generation = UUID()
    private var importGeneration = UUID()
    private var openPanel: NSOpenPanel?
    var busy: Bool { worker != nil && !isPaused }
    var failedCount: Int { paragraphs.filter { $0.error != nil }.count }
    var translatedCount: Int { paragraphs.filter { $0.translation != nil }.count }
    var pages: [Int] { Array(Set(paragraphs.flatMap { $0.sourceRegions.isEmpty ? [$0.page].compactMap { $0 } : $0.sourceRegions.map(\.page) })).sorted() }
    var readingParagraphs: [ReadingParagraph] {
        paragraphs.filter { p in
            if documentURL?.pathExtension.lowercased() != "pdf" { return true }
            return showPDFDetails || p.kind != "figure" && p.kind != "metadata"
        }
    }

    func chooseFile() {
        if let existing = openPanel, existing.isVisible { existing.makeKeyAndOrderFront(nil); return }
        openPanel?.close()
        openPanel = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "docx")!, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        openPanel = panel
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, self.openPanel === panel else { return }
            self.openPanel = nil
            if response == .OK, let url = panel.url { self.open(url) }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else { panel.begin(completionHandler: completion) }
    }
    func open(_ url: URL) {
        stop()
        generation = UUID()
        importGeneration = UUID()
        let version = importGeneration
        importing = true
        documentReady = false
        status = "正在读取 \(url.lastPathComponent)…"
        Task {
            do {
                let values = try await Task.detached(priority: .userInitiated) { try DocumentLoader.load(url) }.value
                guard importGeneration == version else { return }
                paragraphs = values
                documentReady = url.pathExtension.lowercased() != "docx"
                documentID = UUID()
                documentURL = url
                importing = false
                status = "\(values.count) 段 · 点击英文下方的「展开中文」"
                autoTranslate = false
                selectedPDFParagraph = nil
                pdfMergeBackup = nil
                pdfVisiblePage = 1
                showPDFDetails = false
                pdfMode = .original
                if url.pathExtension.lowercased() == "pdf" { status = "点击原页中的段落，中文显示在右侧 · 可切换段落对照" }
            } catch {
                guard importGeneration == version else { return }
                importing = false
                documentReady = documentURL != nil
                status = documentURL == nil ? "请选择可读取的 PDF 或 Word" : "已保留之前打开的文档"
                alert = error.localizedDescription
            }
        }
    }
    func selectPDFParagraph(_ id: Int) {
        guard paragraphs.indices.contains(id) else { return }
        selectedPDFParagraph = id
        enqueue(id)
    }
    func mergePDFParagraph(_ direction: Int) {
        guard let id = selectedPDFParagraph else { return }
        let ids = readingParagraphs.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + direction) else { return }
        let neighbor = ids[index + direction]
        stop()
        pdfMergeBackup = (paragraphs, id)
        paragraphs = PDFLayout.merge(paragraphs, first: id, second: neighbor)
        selectedPDFParagraph = min(id, neighbor)
        if let selectedPDFParagraph { enqueue(selectedPDFParagraph) }
    }
    func undoPDFMerge() {
        guard let backup = pdfMergeBackup else { return }
        stop()
        paragraphs = backup.paragraphs
        selectedPDFParagraph = backup.selected
        pdfMergeBackup = nil
        status = "已撤销上次段落合并"
    }
    func movePDFParagraph(_ offset: Int) {
        guard let id = selectedPDFParagraph else { return }
        let ids = readingParagraphs.map(\.id)
        let next = offset > 0 ? ids.first(where: { $0 > id }) : ids.last(where: { $0 < id })
        if let next { selectPDFParagraph(next) }
    }
    func toggle(_ id: Int) {
        guard paragraphs.indices.contains(id) else { return }
        if queue.contains(id) { enqueue(id); return }
        if paragraphs[id].expanded { paragraphs[id].expanded = false }
        else { enqueue(id) }
    }
    func acceptWordParagraphs(_ texts: [String], url: URL) {
        guard documentURL == url else { return }
        stop()
        paragraphs = texts.enumerated().map { ReadingParagraph(id: $0.offset, text: $0.element, page: nil) }
        documentReady = true
    }
    func enqueueAutomatically(_ id: Int) {
        guard !isPaused, paragraphs.indices.contains(id), paragraphs[id].error == nil else { return }
        enqueue(id, priority: false)
    }
    func enqueue(_ id: Int, priority: Bool = true) {
        guard documentReady, !importing, !clearingCache, paragraphs.indices.contains(id) else { return }
        paragraphs[id].expanded = true
        guard paragraphs[id].translation == nil, activeID != id else { return }
        if queue.contains(id) {
            if priority { queue.removeAll { $0 == id }; queue.insert(id, at: 0) }
            return
        }
        paragraphs[id].loading = !isPaused
        paragraphs[id].activity = isPaused ? "已暂停 · 等待继续" : "等待翻译…"
        paragraphs[id].error = nil
        if priority { queue.insert(id, at: 0) } else { queue.append(id) }
        updatePendingCount()
        if worker == nil && !isPaused { startWorker() }
    }
    func translateAll() {
        guard documentReady, !importing, !clearingCache else { return }
        for paragraph in readingParagraphs where paragraph.translation == nil { enqueue(paragraph.id, priority: false) }
        if isPaused { resume() }
    }
    private func updatePendingCount() { pendingCount = queue.count + (activeID == nil ? 0 : 1) }
    private func startWorker() {
        let version = generation
        let selectedEngine = engine
        worker = Task { [self] in
            while !queue.isEmpty && !Task.isCancelled && generation == version && !isPaused {
                let id = queue.removeFirst()
                activeID = id
                updatePendingCount()
                let text = paragraphs[id].text
                status = "正在翻译第 \(id + 1) 段 · \(selectedEngine.rawValue)"
                do {
                    let result = try await translator.translate(text, engine: selectedEngine) { [weak self] message in
                        await self?.reportProgress(message, id: id, generation: version)
                    }
                    guard !Task.isCancelled && generation == version else { return }
                    paragraphs[id].translation = result
                    paragraphs[id].error = nil
                    paragraphs[id].loading = false
                    paragraphs[id].activity = nil
                    transientFailures.removeAll()
                } catch {
                    guard !Task.isCancelled && generation == version else { return }
                    paragraphs[id].error = error.localizedDescription
                    paragraphs[id].loading = false
                    paragraphs[id].activity = nil
                    let failure = error as? TranslationFailure
                    if failure?.isTransient == true { transientFailures.append(id) }
                    else { transientFailures.removeAll() }
                    if failure?.shouldPause == true || transientFailures.count >= 3 {
                        let retryIDs = transientFailures.isEmpty ? [id] : transientFailures
                        activeID = nil
                        queue.insert(contentsOf: retryIDs.filter { !queue.contains($0) }, at: 0)
                        pause(reason: error.localizedDescription)
                        return
                    }
                }
                activeID = nil
                updatePendingCount()
                if !queue.isEmpty { try? await Task.sleep(nanoseconds: 400_000_000) }
            }
            guard generation == version else { return }
            worker = nil
            updatePendingCount()
            status = failedCount > 0 ? "已完成 \(translatedCount) 段 · \(failedCount) 段失败，可点击重试" : "已完成 \(translatedCount) 段 · 译文已缓存在本机"
        }
    }
    private func reportProgress(_ message: String, id: Int, generation version: UUID) {
        guard generation == version, activeID == id, paragraphs.indices.contains(id) else { return }
        paragraphs[id].activity = message
    }
    func pause(reason: String = "翻译已暂停，待翻译内容已保留") {
        if !isPaused { automaticBeforePause = autoTranslate }
        generation = UUID()
        worker?.cancel()
        worker = nil
        if let id = activeID, !queue.contains(id) { queue.insert(id, at: 0) }
        activeID = nil
        isPaused = !queue.isEmpty
        autoTranslate = false
        for id in queue {
            paragraphs[id].loading = false
            paragraphs[id].activity = "已暂停 · 等待继续"
        }
        updatePendingCount()
        status = reason
    }
    func resume() {
        guard isPaused, documentReady, !clearingCache, !importing else { return }
        isPaused = false
        autoTranslate = automaticBeforePause
        automaticBeforePause = false
        transientFailures.removeAll()
        for id in queue {
            paragraphs[id].loading = true
            paragraphs[id].error = nil
            paragraphs[id].activity = "等待翻译…"
        }
        if worker == nil { startWorker() }
    }
    func stop() {
        generation = UUID()
        worker?.cancel()
        worker = nil
        activeID = nil
        queue.removeAll()
        automaticBeforePause = false
        transientFailures.removeAll()
        isPaused = false
        pendingCount = 0
        var updated = paragraphs
        for index in updated.indices { updated[index].loading = false; updated[index].activity = nil }
        paragraphs = updated
        autoTranslate = false
        status = "翻译已停止，已完成的译文保留"
    }
    func changeEngine() {
        stop()
        var updated = paragraphs
        for index in updated.indices {
            updated[index].translation = nil
            updated[index].error = nil
            updated[index].expanded = false
        }
        paragraphs = updated
        status = "已切换到 \(engine.rawValue)，点击段落重新翻译"
    }
    func collapseAll() {
        var updated = paragraphs
        for index in updated.indices { updated[index].expanded = false }
        paragraphs = updated
    }
    func refreshCacheInfo() async {
        let info = await translator.cacheInfo()
        cacheCount = info.count
        cacheBytes = info.bytes
    }
    func clearTranslationCache() {
        guard !clearingCache else { return }
        stop()
        clearingCache = true
        Task {
            do {
                try await translator.clearCache()
                var updated = paragraphs
                for index in updated.indices {
                    updated[index].translation = nil
                    updated[index].error = nil
                    updated[index].expanded = false
                }
                paragraphs = updated
                status = "翻译缓存已清理 · 点击段落可重新翻译"
            } catch { alert = "清理缓存失败：" + error.localizedDescription }
            await refreshCacheInfo()
            clearingCache = false
        }
    }
    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (documentURL?.deletingPathExtension().lastPathComponent ?? "文档") + "-中英对照.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body = paragraphs.map {
            "<section><p lang=\"en\">\(Self.escape($0.text))</p>" + ($0.translation.map { "<p lang=\"zh-CN\" class=\"translation\">\(Self.escape($0))</p>" } ?? "") + "</section>"
        }.joined(separator: "\n")
        let html = """
        <!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>中英对照</title>
        <style>body{max-width:850px;margin:50px auto;padding:0 24px;font:20px/1.8 Georgia,serif}section{margin-bottom:32px}p{white-space:pre-wrap}.translation{font-family:system-ui;color:#17675d;border-left:3px solid #acd6cb;padding-left:20px}</style>
        <h1>\(Self.escape(documentURL?.lastPathComponent ?? "中英对照"))</h1>\(body)</html>
        """
        do { try html.write(to: url, atomically: true, encoding: .utf8); status = "已导出 \(translatedCount) 段译文及全文原文" }
        catch { alert = error.localizedDescription }
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

