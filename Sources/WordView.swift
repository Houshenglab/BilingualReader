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
        init(model: ReaderModel, url: URL) { self.model = model; self.url = url; self.documentID = model.documentID }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                do {
                    let base64 = try await Task.detached { try Data(contentsOf: self.url).base64EncodedString() }.value
                    guard !cancelled && model.documentURL == url && model.documentID == documentID else { return }
                    webView.callAsyncJavaScript("return await renderWord(bytes);", arguments: ["bytes": base64], in: nil, in: .page) { result in
                        if case .failure(let error) = result, !self.cancelled { self.model.alert = "Word 排版加载失败：\(error.localizedDescription)" }
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
                model.status = "Word 原文排版 · \(payload["tables"] ?? 0) 个表格 · 点击英文段落展开中文"
                synchronize()
            } else if ready, let id = payload["id"] as? Int {
                if kind == "toggle" { model.toggle(id) }
                if kind == "retry" { model.enqueue(id) }
                if kind == "resume" { model.resume() }
                if kind == "visible" && model.autoTranslate { model.enqueueAutomatically(id) }
            }
        }
        func synchronize() {
            guard ready, !cancelled else { return }
            var changed: [[String: Any]] = []
            for p in model.paragraphs {
                let signature = "\(p.expanded)|\(p.loading)|\(p.translation ?? "")|\(p.error ?? "")|\(p.activity ?? "")|\(model.isPaused)"
                if previous[p.id] != signature {
                    previous[p.id] = signature
                    changed.append(["id": p.id, "expanded": p.expanded, "loading": p.loading, "translation": p.translation ?? "", "error": p.error ?? "", "activity": p.activity ?? "", "paused": model.isPaused])
                }
            }
            if !changed.isEmpty || lastAutomatic != model.autoTranslate {
                lastAutomatic = model.autoTranslate
                view?.callAsyncJavaScript("updateReader(states, automatic);", arguments: ["states": changed, "automatic": model.autoTranslate], in: nil, in: .page, completionHandler: nil)
            }
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
