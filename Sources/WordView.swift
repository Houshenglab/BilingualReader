import SwiftUI
import WebKit

struct WordView: NSViewRepresentable {
    @ObservedObject var model: ReaderModel
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(model: model, url: url) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "reader")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        context.coordinator.view = view
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("Word/index.html") {
            view.loadFileURL(resource, allowingReadAccessTo: resource.deletingLastPathComponent())
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.synchronize() }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.cancelled = true
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: ReaderModel
        let url: URL
        let documentID: UUID
        weak var view: WKWebView?
        var ready = false
        var cancelled = false
        var previous: [Int: String] = [:]
        var lastAutomatic: Bool?
        var lastZoom: Double?
        var lastNotes: [ResearchNote]?
        var lastJump: UUID?
        init(model: ReaderModel, url: URL) { self.model = model; self.url = url; self.documentID = model.documentID }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                do {
                    let base64 = try await Task.detached { try Data(contentsOf: self.url).base64EncodedString() }.value
                    guard !cancelled && model.documentURL == url && model.documentID == documentID else { return }
                    webView.callAsyncJavaScript("setReaderLanguage(language); return await renderWord(bytes);", arguments: ["bytes": base64, "language": ReaderLanguage.htmlLanguage], in: nil, in: .page) { result in
                        if case .failure(let error) = result, !self.cancelled { self.model.alert = L("Word 排版加载失败：\(error.localizedDescription)", "Unable to open Word layout: \(error.localizedDescription)") }
                    }
                } catch { if !cancelled { model.alert = error.localizedDescription } }
            }
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !cancelled, message.frameInfo.isMainFrame, model.documentURL == url, model.documentID == documentID,
                  let payload = message.body as? [String: Any], let kind = payload["kind"] as? String else { return }
            if kind == "ready", let texts = payload["paragraphs"] as? [String] {
                model.acceptWordParagraphs(texts, url: url)
                ready = true
                model.status = L("Word 原文排版 · \(payload["tables"] ?? 0) 个表格 · 点击英文段落展开中文", "Word original layout · Tables: \(payload["tables"] ?? 0) · Click a paragraph to translate")
                synchronize()
                view?.callAsyncJavaScript("restoreReadingPosition(id);", arguments: ["id": model.readingParagraphID ?? 0], in: nil, in: .page, completionHandler: nil)
            } else if ready, kind == "selection",
                      let id = payload["id"] as? Int, model.paragraphs.indices.contains(id),
                      let quote = payload["quote"] as? String,
                      let location = payload["location"] as? Int, location >= 0,
                      let length = payload["length"] as? Int, length > 0, length == quote.utf16.count {
                model.notebook.selection = ResearchAnchor(paragraphID: id, quote: quote, rangeLocation: location, rangeLength: length)
            } else if ready, kind == "selectionUnsupported" {
                model.notebook.selection = nil
                model.status = L("请选择同一段落内的文字，便于准确保存高亮与批注", "Select text within one paragraph to save highlights and comments accurately")
            } else if ready, kind == "selectionCleared" {
                model.notebook.selection = nil
            } else if ready, kind == "annotationClicked",
                      let value = payload["noteID"] as? String, let noteID = UUID(uuidString: value),
                      let note = model.notebook.notes.first(where: { $0.id == noteID }) {
                model.notebook.beginEditing(note)
            } else if ready, let id = payload["id"] as? Int {
                if kind == "position", model.paragraphs.indices.contains(id) { model.readingParagraphID = id }
                if kind == "toggle" { model.toggle(id) }
                if kind == "retry" { model.enqueue(id) }
                if kind == "resume" { model.resume() }
                if kind == "visible" && model.autoTranslate { model.enqueueAutomatically(id) }
            }
        }
        func synchronize() {
            guard ready, !cancelled, model.documentID == documentID else { return }
            var changed: [[String: Any]] = []
            for p in model.paragraphs {
                let signature = "\(p.expanded)|\(p.loading)|\(p.translation ?? "")|\(p.error ?? "")|\(p.activity ?? "")|\(model.isPaused)"
                if previous[p.id] != signature {
                    previous[p.id] = signature
                    changed.append(["id": p.id, "expanded": p.expanded, "loading": p.loading, "translation": p.translation ?? "", "error": p.error ?? "", "activity": p.activity ?? "", "activityText": LStatus(p.activity ?? ""), "paused": model.isPaused])
                }
            }
            if !changed.isEmpty || lastAutomatic != model.autoTranslate {
                lastAutomatic = model.autoTranslate
                view?.callAsyncJavaScript("updateReader(states, automatic);", arguments: ["states": changed, "automatic": model.autoTranslate], in: nil, in: .page, completionHandler: nil)
            }
            if lastNotes != model.notebook.notes {
                lastNotes = model.notebook.notes
                let notes: [[String: Any]] = model.notebook.notes.compactMap { note in
                    guard let anchor = note.anchor, let id = anchor.paragraphID else { return nil }
                    var result: [String: Any] = [
                        "id": note.id.uuidString, "paragraphID": id, "quote": anchor.quote,
                        "hasComment": !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "color": note.color?.rawValue ?? "comment"
                    ]
                    if let location = anchor.rangeLocation { result["location"] = location }
                    if let length = anchor.rangeLength { result["length"] = length }
                    return result
                }
                view?.callAsyncJavaScript("updateAnnotations(notes);", arguments: ["notes": notes], in: nil, in: .page, completionHandler: nil)
            }
            if let note = model.notebook.requestedJump, let id = note.anchor?.paragraphID {
                if lastJump != note.id {
                    lastJump = note.id
                    view?.callAsyncJavaScript("return jumpToAnnotation(noteID, id);", arguments: ["noteID": note.id.uuidString, "id": id], in: nil, in: .page) { [weak self] result in
                        guard let self, !self.cancelled, self.model.documentID == self.documentID,
                              self.model.notebook.requestedJump?.id == note.id else { return }
                        self.lastJump = nil
                        self.model.notebook.requestedJump = nil
                        if case .failure(let error) = result { self.model.alert = L("无法定位批注：\(error.localizedDescription)", "Unable to locate comment: \(error.localizedDescription)") }
                    }
                }
            } else { lastJump = nil }
            if lastZoom != model.fontSize {
                lastZoom = model.fontSize
                view?.callAsyncJavaScript("setZoom(zoom);", arguments: ["zoom": model.fontSize / 20], in: nil, in: .page, completionHandler: nil)
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}
