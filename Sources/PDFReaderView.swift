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
            guard let coordinator, let doc = page.document else { return }
            let number = doc.index(for: page) + 1
            let candidates = coordinator.model.paragraphs.filter { p in
                p.sourceRegions.contains { $0.page == number && $0.bounds.insetBy(dx: -3, dy: -3).contains(point) }
            }
            if let match = candidates.min(by: { $0.sourceRegions.count < $1.sourceRegions.count }) {
                coordinator.model.selectPDFParagraph(match.id)
            }
        }
        context.coordinator.observe(view)
        return view
    }
    func updateNSView(_ view: ClickablePDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            context.coordinator.lastSelection = nil
        }
        let sourceCount = model.selectedPDFParagraph.flatMap { model.paragraphs.indices.contains($0) ? model.paragraphs[$0].sourceRegions.count : nil } ?? 0
        guard context.coordinator.lastSelection != model.selectedPDFParagraph || context.coordinator.lastSourceCount != sourceCount else { return }
        context.coordinator.lastSourceCount = sourceCount
        context.coordinator.lastSelection = model.selectedPDFParagraph
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
        var lastSelection: Int?
        var lastSourceCount = 0
        var token: NSObjectProtocol?
        var mouseMonitor: Any?
        var mouseDownPoint: NSPoint?
        init(_ model: ReaderModel) { self.model = model }
        func observe(_ view: ClickablePDFView) {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window else { return event }
                let point = view.convert(event.locationInWindow, from: nil)
                if event.type == .leftMouseDown { self.mouseDownPoint = view.bounds.contains(point) ? point : nil }
                if event.type == .leftMouseUp, event.clickCount == 1, let down = self.mouseDownPoint,
                   hypot(point.x - down.x, point.y - down.y) < 4,
                   view.bounds.contains(point), let page = view.page(for: point, nearest: false) {
                    self.mouseDownPoint = nil
                    let pagePoint = view.convert(point, to: page)
                    DispatchQueue.main.async { [weak view] in view?.paragraphClicked?(page, pagePoint) }
                }
                return event
            }
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                guard let self, let doc = view?.document, let page = view?.currentPage else { return }
                Task { @MainActor in self.model.pdfVisiblePage = doc.index(for: page) + 1 }
            }
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
            if let paragraph = selected {
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
