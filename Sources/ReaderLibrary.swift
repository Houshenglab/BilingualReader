import Foundation

extension ReaderModel {
    static func visibleParagraph(in frames: [Int: CGRect]) -> Int? {
        frames.filter { $0.value.maxY > 0 }.min { $0.value.minY < $1.value.minY }?.key
    }
    var documentTitle: String {
        libraryBooks.first(where: { $0.id == currentBookID })?.title
            ?? documentURL?.deletingPathExtension().lastPathComponent ?? "双语阅读"
    }
    func refreshLibrary() async {
        guard let library else { return }
        do {
            libraryBooks = try await library.list()
            for book in libraryBooks { libraryCovers[book.id] = await library.coverURL(book) }
        } catch { alert = error.localizedDescription; libraryStatus = "书库读取失败，已有文件保留" }
    }
    func importDocuments(_ urls: [URL], openFirst: Bool = false) {
        guard let library, !libraryBusy, !urls.isEmpty else { return }
        libraryBusy = true
        Task {
            var imported: [LibraryBook] = [], errors: [String] = []
            for (index, url) in urls.enumerated() {
                libraryStatus = "正在导入 \(index + 1)/\(urls.count)：\(url.lastPathComponent)"
                do {
                    imported.append(try await library.importDocument(url))
                    await refreshLibrary()
                }
                catch { errors.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            }
            await refreshLibrary()
            libraryBusy = false
            libraryStatus = "已加入 \(imported.count) 份文档"
            if !errors.isEmpty { alert = errors.joined(separator: "\n") }
            if openFirst, let first = imported.first { openBook(first) }
        }
    }
    func openBook(_ book: LibraryBook) {
        guard let library else { return }
        saveReadingSession()
        stop()
        pdfPreparationTask?.cancel()
        preparingPDF = false
        pdfPreparationError = nil
        importGeneration = UUID()
        let version = importGeneration
        importing = true
        Task {
            do {
                await saveTask?.value
                let url = await library.documentURL(book)
                guard FileManager.default.fileExists(atPath: url.path) else { throw ReaderError.message("这本书的本地副本已丢失，请从书架移除后重新导入。") }
                let state = try await library.session(book.id)
                let values: [ReadingParagraph]
                let pendingPDF = book.format == "pdf" && (state == nil || state?.layoutPending == true)
                if pendingPDF { values = [] }
                else if let state { values = state.paragraphs }
                else { values = try await Task.detached { try DocumentLoader.load(url) }.value }
                guard importGeneration == version else { return }
                restoringSession = true
                currentBookID = book.id
                documentURL = url; documentID = UUID()
                var clean = values
                for i in clean.indices {
                    clean[i].loading = false; clean[i].activity = nil; clean[i].error = nil
                    if state?.engine != engine.rawValue { clean[i].translation = nil; clean[i].expanded = false }
                }
                paragraphs = clean
                pdfVisiblePage = max(1, min(state?.page ?? 1, max(1, book.pageCount)))
                readingParagraphID = state?.paragraphID.flatMap { clean.indices.contains($0) ? $0 : nil }
                selectedPDFParagraph = nil
                pdfMode = pendingPDF ? .original : state.flatMap { PDFReadingMode(rawValue: $0.mode) } ?? .original
                fontSize = min(28, max(16, state?.fontSize ?? 20))
                pdfMergeBackup = nil
                autoTranslate = false; showPDFDetails = false
                pdfLayoutPending = pendingPDF
                documentReady = book.format != "docx" && !pendingPDF
                if book.format == "docx" {
                    pendingWordSession = ReadingSession(paragraphs: clean, paragraphID: readingParagraphID, engine: engine.rawValue)
                } else { pendingWordSession = nil }
                importing = false; showingLibrary = false
                restoringSession = false
                status = "已恢复阅读位置 · \(translatedCount) 段译文"
                saveReadingSession()
                if pendingPDF { preparePDFLayout() }
            } catch {
                guard importGeneration == version else { return }
                importing = false; alert = error.localizedDescription
            }
        }
    }
    func preparePDFLayout() {
        guard pdfLayoutPending, !preparingPDF, let url = documentURL else { return }
        let version = importGeneration
        preparingPDF = true
        pdfPreparationError = nil
        status = "原页已打开 · 正在准备段落翻译…"
        let cancellation = PDFExtractionCancellation()
        pdfPreparationTask = Task {
            defer { if importGeneration == version { preparingPDF = false } }
            do {
                let values = try await withTaskCancellationHandler {
                    try await Task.detached(priority: .userInitiated) { try DocumentLoader.load(url, cancellation: cancellation) }.value
                } onCancel: {
                    cancellation.cancel()
                }
                guard !Task.isCancelled, importGeneration == version else { return }
                paragraphs = values
                pdfLayoutPending = false
                documentReady = true
                status = "段落已就绪 · 点击原页中的英文查看中文"
                saveReadingSession()
            } catch {
                guard !Task.isCancelled, importGeneration == version else { return }
                pdfPreparationError = error.localizedDescription
                status = "原页可继续阅读 · 段落分析未完成"
            }
        }
    }
    func returnToLibrary() {
        saveReadingSession()
        importGeneration = UUID()
        pdfPreparationTask?.cancel()
        preparingPDF = false
        importing = false
        stop()
        showingLibrary = true
        Task { await saveTask?.value; await refreshLibrary() }
    }
    func scheduleLibrarySave() {
        guard library != nil, !restoringSession, (documentReady || pdfLayoutPending), !importing, currentBookID != nil else { return }
        saveDebounce?.cancel()
        saveDebounce = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            self?.saveReadingSession()
        }
    }
    func saveReadingSession() {
        saveDebounce?.cancel(); saveDebounce = nil
        guard let library, let id = currentBookID, (documentReady || pdfLayoutPending), !restoringSession, !importing else { return }
        let snapshot = ReadingSession(paragraphs: paragraphs, layoutPending: pdfLayoutPending ? true : nil, page: pdfVisiblePage, paragraphID: readingParagraphID,
                                      mode: pdfMode.rawValue, fontSize: fontSize, engine: engine.rawValue)
        let previous = saveTask
        saveTask = Task { [weak self] in
            await previous?.value
            do { try await library.save(id, session: snapshot) }
            catch { self?.alert = "阅读记录保存失败：\(error.localizedDescription)" }
        }
    }
    func flushLibrarySave() async { saveReadingSession(); await saveTask?.value }
    func removeBook(_ book: LibraryBook) {
        guard let library else { return }
        if currentBookID == book.id {
            returnToLibrary(); pdfLayoutPending = false; currentBookID = nil; documentURL = nil; paragraphs = []; pendingWordSession = nil
        }
        Task {
            do { await saveTask?.value; try await library.remove(book.id); await refreshLibrary() }
            catch { alert = error.localizedDescription }
        }
    }
}
