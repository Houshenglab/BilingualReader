import SwiftUI
import PDFKit
import AppKit

final class ClickablePDFView: PDFView {
    var paragraphClicked: ((PDFPage, CGPoint) -> Void)?
}

struct LinkedPDF: NSViewRepresentable {
    @ObservedObject var model: ReaderModel
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> ClickablePDFView {
        let view = ClickablePDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = NSColor.windowBackgroundColor
        view.document = PDFDocument(url: url)
        view.paragraphClicked = { [weak coordinator = context.coordinator] page, point in
            guard let coordinator, let doc = page.document, coordinator.model.documentID == coordinator.documentID else { return }
            if let note = coordinator.note(at: point, on: page) {
                coordinator.model.notebook.beginEditing(note)
                return
            }
            let number = doc.index(for: page) + 1
            let candidates = coordinator.model.paragraphs.filter { p in
                p.sourceRegions.contains { $0.page == number && $0.bounds.insetBy(dx: -3, dy: -3).contains(point) }
            }
            if let match = candidates.min(by: { $0.sourceRegions.count < $1.sourceRegions.count }) {
                coordinator.model.selectPDFParagraph(match.id)
            }
        }
        let restoredPage = model.pdfVisiblePage
        let token = model.documentID
        DispatchQueue.main.async {
            guard context.coordinator.model.documentID == token else { return }
            if context.coordinator.model.selectedPDFParagraph == nil, let page = view.document?.page(at: restoredPage - 1) { view.go(to: page) }
            context.coordinator.observe(view)
            if let doc = view.document, let page = view.currentPage {
                context.coordinator.model.pdfVisiblePage = doc.index(for: page) + 1
            }
        }
        return view
    }
    func updateNSView(_ view: ClickablePDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            context.coordinator.lastSelection = nil
            context.coordinator.renderedNotes = nil
            context.coordinator.ownedAnnotations = []
        }
        context.coordinator.synchronizeNotes(view)
        let sourceCount = model.selectedPDFParagraph.flatMap { model.paragraphs.indices.contains($0) ? model.paragraphs[$0].sourceRegions.count : nil } ?? 0
        if context.coordinator.handleJump(view) { return }
        guard context.coordinator.lastSelection != model.selectedPDFParagraph || context.coordinator.lastSourceCount != sourceCount else { return }
        context.coordinator.lastSourceCount = sourceCount
        context.coordinator.lastSelection = model.selectedPDFParagraph
        context.coordinator.programmaticSelection = true
        defer { context.coordinator.programmaticSelection = false }
        guard let id = model.selectedPDFParagraph, model.paragraphs.indices.contains(id), let doc = view.document else {
            view.clearSelection(); return
        }
        let sources = model.paragraphs[id].sourceRegions
        let selection = PDFSelection(document: doc)
        for region in sources {
            if let page = doc.page(at: region.page - 1), let part = page.selection(for: region.bounds.insetBy(dx: 0.5, dy: 0.3)) { selection.add(part) }
        }
        selection.color = NSColor.systemBlue.withAlphaComponent(0.25)
        view.setCurrentSelection(selection, animate: false)
        let currentPage = view.currentPage.map { doc.index(for: $0) + 1 }
        if !sources.contains(where: { $0.page == currentPage }), let region = sources.first, let page = doc.page(at: region.page - 1) {
            view.go(to: CGRect(x: region.bounds.minX, y: region.bounds.minY, width: region.bounds.width, height: max(160, region.bounds.height)), on: page)
        }
    }
    final class Coordinator: NSObject {
        let model: ReaderModel
        let documentID: UUID
        var lastSelection: Int?
        var lastSourceCount = 0
        var token: NSObjectProtocol?
        var mouseMonitor: Any?
        var mouseDownPoint: NSPoint?
        var programmaticSelection = false
        var keyboardSelecting = false
        var renderedNotes: [ResearchNote]?
        var ownedAnnotations: [(page: PDFPage, annotation: PDFAnnotation, noteID: UUID, marker: Bool)] = []
        var lastJump: UUID?
        @MainActor init(_ model: ReaderModel) { self.model = model; self.documentID = model.documentID }
        func observe(_ view: ClickablePDFView) {
            // Capture only deliberate text selections. The blue paragraph selection
            // used by the translation panel must not appear as an unsaved note.
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .keyDown]) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window else { return event }
                if event.type == .keyDown {
                    guard let responder = event.window?.firstResponder as? NSView,
                          responder === view || responder.isDescendant(of: view) else { return event }
                    guard event.modifierFlags.contains(.shift) || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "a") else { return event }
                    self.keyboardSelecting = true
                    DispatchQueue.main.async { [weak self, weak view] in
                        guard let self, let view else { return }
                        self.captureSelection(view)
                        self.keyboardSelecting = false
                    }
                    return event
                }
                let point = view.convert(event.locationInWindow, from: nil)
                if event.type == .leftMouseDown {
                    self.mouseDownPoint = view.bounds.contains(point) ? point : nil
                }
                if event.type == .leftMouseUp, let down = self.mouseDownPoint {
                    self.mouseDownPoint = nil
                    guard view.bounds.contains(point), let page = view.page(for: point, nearest: false) else { return event }
                    let clicked = event.clickCount == 1 && hypot(point.x - down.x, point.y - down.y) < 4
                    let pagePoint = view.convert(point, to: page)
                    DispatchQueue.main.async { [weak self, weak view] in
                        guard let self, let view, self.model.documentID == self.documentID else { return }
                        if clicked {
                            self.model.notebook.selection = nil
                            view.paragraphClicked?(page, pagePoint)
                        } else {
                            self.captureSelection(view)
                        }
                    }
                }
                return event
            }
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                guard let self, let doc = view?.document, let page = view?.currentPage else { return }
                Task { @MainActor in
                    guard self.model.documentID == self.documentID else { return }
                    self.model.pdfVisiblePage = doc.index(for: page) + 1
                }
            }
        }
        @MainActor func captureSelection(_ view: ClickablePDFView) {
            guard model.documentID == documentID, !programmaticSelection,
                  let doc = view.document, let selected = view.currentSelection,
                  let quote = selected.string, !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let regions = Self.regions(for: selected, document: doc)
            guard !regions.isEmpty else { return }
            let first = regions[0]
            let matching = model.paragraphs.first { paragraph in
                paragraph.sourceRegions.contains { $0.page == first.page && $0.bounds.intersects(first.bounds) }
            }
            let range = matching.map { ($0.text as NSString).range(of: quote) }.flatMap { $0.location != NSNotFound ? $0 : nil }
            let anchor = ResearchAnchor(paragraphID: matching?.id, quote: quote, rangeLocation: range?.location, rangeLength: range?.length, pdfRegions: regions)
            if model.notebook.selection != anchor { model.notebook.selection = anchor }
        }

        static func regions(for selection: PDFSelection, document: PDFDocument) -> [ResearchPDFRegion] {
            selection.selectionsByLine().flatMap { line in
                line.pages.compactMap { page in
                    let index = document.index(for: page)
                    let bounds = line.bounds(for: page)
                    guard index != NSNotFound, bounds.width > 0, bounds.height > 0, !bounds.isInfinite else { return nil }
                    return ResearchPDFRegion(page: index + 1, bounds: bounds)
                }
            }
        }

        @MainActor func regions(for anchor: ResearchAnchor, document: PDFDocument) -> [ResearchPDFRegion] {
            if !anchor.pdfRegions.isEmpty { return anchor.pdfRegions }
            guard let id = anchor.paragraphID,
                  let paragraph = model.paragraphs.first(where: { $0.id == id }),
                  !paragraph.sourceRegions.isEmpty,
                  !anchor.quote.isEmpty else { return [] }
            if paragraph.text == anchor.quote {
                return paragraph.sourceRegions.map { ResearchPDFRegion(page: $0.page, bounds: $0.bounds) }
            }
            let matches = document.findString(anchor.quote, withOptions: .caseInsensitive).map { Self.regions(for: $0, document: document) }
                .filter { !$0.isEmpty && $0.allSatisfy { line in
                    paragraph.sourceRegions.contains { $0.page == line.page && $0.bounds.intersects(line.bounds) }
                } }
            // Repeated words must not be highlighted at the wrong occurrence.
            return matches.count == 1 ? matches[0] : []
        }

        @MainActor func synchronizeNotes(_ view: ClickablePDFView) {
            guard model.documentID == documentID, let document = view.document else { return }
            let notes = model.notebook.notes
            // A note made in paragraph mode may gain PDF coordinates only
            // after the background layout analysis completes.
            let needsTextLookup = notes.contains { $0.anchor?.pdfRegions.isEmpty == true }
            let signature = needsTextLookup ? model.paragraphs.map { "\($0.id)|\($0.text)|\($0.sourceRegions.count)" } : []
            guard renderedNotes != notes || paragraphSignature != signature else { return }
            renderedNotes = notes
            paragraphSignature = signature
            var changedPages = Set<PDFPage>()
            for entry in ownedAnnotations { entry.page.removeAnnotation(entry.annotation); changedPages.insert(entry.page) }
            ownedAnnotations = []
            for note in notes {
                guard let anchor = note.anchor else { continue }
                let regions = regions(for: anchor, document: document)
                for region in regions {
                    guard region.page > 0, let page = document.page(at: region.page - 1) else { continue }
                    let bounds = region.bounds.intersection(page.bounds(for: .cropBox))
                    guard !bounds.isEmpty, !bounds.isInfinite else { continue }
                    let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                    annotation.quadrilateralPoints = [NSValue(point: CGPoint(x: 0, y: bounds.height)), NSValue(point: CGPoint(x: bounds.width, y: bounds.height)), NSValue(point: .zero), NSValue(point: CGPoint(x: bounds.width, y: 0))]
                    annotation.color = (note.color?.nsColor ?? .systemTeal).withAlphaComponent(note.color == nil ? 0.20 : 0.45)
                    page.displaysAnnotations = true
                    page.addAnnotation(annotation)
                    changedPages.insert(page)
                    ownedAnnotations.append((page, annotation, note.id, false))
                }
                if !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let region = regions.first, region.page > 0, let page = document.page(at: region.page - 1) {
                    let crop = page.bounds(for: .cropBox)
                    let size: CGFloat = 14
                    // Place the comment bubble at the outer page margin, not over following words.
                    let x = max(crop.minX, crop.maxX - size - 5)
                    var y = min(max(region.bounds.midY - size / 2, crop.minY), crop.maxY - size)
                    var rect = CGRect(x: x, y: y, width: size, height: size)
                    while ownedAnnotations.contains(where: { $0.marker && $0.page === page && $0.annotation.bounds.intersects(rect) }) && y - size - 2 >= crop.minY {
                        y -= size + 2
                        rect.origin.y = y
                    }
                    let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
                    annotation.contents = "✎"
                    annotation.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
                    annotation.fontColor = .white
                    annotation.alignment = .center
                    annotation.color = .systemTeal
                    page.displaysAnnotations = true
                    page.addAnnotation(annotation)
                    changedPages.insert(page)
                    ownedAnnotations.append((page, annotation, note.id, true))
                }
            }
            for page in changedPages { view.annotationsChanged(on: page) }
            view.documentView?.needsDisplay = true
            view.needsDisplay = true
        }

        var paragraphSignature: [String] = []

        @MainActor func note(at point: CGPoint, on page: PDFPage) -> ResearchNote? {
            guard let marker = ownedAnnotations.last(where: { $0.marker && $0.page === page && $0.annotation.bounds.insetBy(dx: -3, dy: -3).contains(point) }) else { return nil }
            return model.notebook.notes.first(where: { $0.id == marker.noteID })
        }

        @MainActor func handleJump(_ view: ClickablePDFView) -> Bool {
            guard let note = model.notebook.requestedJump else { lastJump = nil; return false }
            guard lastJump != note.id, let anchor = note.anchor, let document = view.document,
                  let region = regions(for: anchor, document: document).first,
                  region.page > 0, let page = document.page(at: region.page - 1) else { return false }
            lastJump = note.id
            programmaticSelection = true
            view.clearSelection()
            view.go(to: region.bounds.insetBy(dx: -12, dy: -50), on: page)
            programmaticSelection = false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.model.documentID == self.documentID,
                      self.model.notebook.requestedJump?.id == note.id else { return }
                self.lastJump = nil
                self.model.notebook.requestedJump = nil
            }
            return true
        }
        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        }
    }
}

struct PDFTranslationPanel: View {
    @ObservedObject var model: ReaderModel
    var selected: ReadingParagraph? {
        guard let id = model.selectedPDFParagraph, model.paragraphs.indices.contains(id) else { return nil }
        return model.paragraphs[id]
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("段落译文").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { model.movePDFParagraph(-1) } label: { Image(systemName: "chevron.up") }
                    .help("上一段").accessibilityLabel("上一段")
                    .disabled(selected == nil || selected?.id == model.readingParagraphs.first?.id)
                Button { model.movePDFParagraph(1) } label: { Image(systemName: "chevron.down") }
                    .help("下一段").accessibilityLabel("下一段")
                    .disabled(selected == nil || selected?.id == model.readingParagraphs.last?.id)
            }.buttonStyle(.borderless).padding(24)
            Divider()
            if model.pdfLayoutPending {
                VStack(alignment: .leading, spacing: 16) {
                    if model.preparingPDF {
                        ProgressView().controlSize(.small)
                        Text("正在准备段落翻译").font(.title3)
                        Text("你可以先阅读、翻动左侧原页。完成后即可点击英文段落翻译。").foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass").font(.title)
                        Text("段落分析未完成").font(.title3)
                        Text(model.pdfPreparationError ?? "请重试段落分析，原页仍可阅读。").foregroundStyle(.secondary)
                        Button("重新分析") { model.preparePDFLayout() }.buttonStyle(.borderedProminent)
                    }
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let paragraph = selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            Text("第 \(Array(Set(paragraph.sourceRegions.map(\.page))).sorted().map(String.init).joined(separator: "、")) 页 · 段落 \(paragraph.id + 1)")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                Button("与上一段合并") { model.mergePDFParagraph(-1) }
                                    .disabled(paragraph.id == model.readingParagraphs.first?.id)
                                Button("与下一段合并") { model.mergePDFParagraph(1) }
                                    .disabled(paragraph.id == model.readingParagraphs.last?.id)
                                if model.pdfMergeBackup != nil { Button("撤销上次合并") { model.undoPDFMerge() } }
                            } label: { Image(systemName: "ellipsis.circle") }
                                .menuStyle(.borderlessButton).fixedSize().help("调整段落范围").accessibilityLabel("调整段落")
                        }
                        TranslationResult(model: model, paragraph: paragraph)
                        Divider()
                        DisclosureGroup("英文原文") {
                            Text(paragraph.text).font(.system(size: 16, design: .serif)).lineSpacing(8)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 12)
                        }.font(.callout).foregroundStyle(.secondary)
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }.id(paragraph.id)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "text.cursor").font(.system(size: 32, weight: .light)).foregroundStyle(Color.accentColor)
                    Text("从一段开始").font(.system(size: 24, weight: .medium))
                    Text("点击左侧英文段落，\n在这里阅读对应中文。")
                        .font(.system(size: 16)).lineSpacing(8).foregroundStyle(.secondary)
                    Text("图表与公式保留在原页。")
                        .font(.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(32).padding(.top, 48)
            }
        }.background(Color(nsColor: .textBackgroundColor))
    }
}
