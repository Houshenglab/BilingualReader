import Foundation

@MainActor private final class AITransportProbe {
    var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    var request: URLRequest?
    func transport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func reply() {
        let url = request!.url!
        continuation?.resume(returning: (Data(#"{"choices":[{"message":{"content":"mock response"}}]}"#.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        continuation = nil
    }
}

@main struct ResearchAIChecks {
    @MainActor static func main() async throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
        }
        let endpoint = try ResearchAIConfiguration.endpoint("https://example.com/v1/")
        check(endpoint.absoluteString == "https://example.com/v1/chat/completions", "base path handling")
        check(try! ResearchAIConfiguration.endpoint("http://127.0.0.1:11434/v1").host == "127.0.0.1", "loopback")
        for invalid in ["http://example.com/v1", "https://user:pass@example.com/v1", "https://example.com/v1?token=123", "file:///tmp/x", "https://example.com/v1#fragment"] {
            check((try? ResearchAIConfiguration.endpoint(invalid)) == nil, "invalid endpoint accepted: \(invalid)")
        }
        let full = ResearchAIContext(paragraphs: ["alpha", "beta"], selectedText: nil, scope: .document)
        check(full.isComplete && full.text.contains("alpha") && full.text.contains("beta"), "complete document")
        let long = ResearchAIContext(paragraphs: (0..<100).map { "paragraph-\($0) " + String(repeating: "a", count: 1000) }, selectedText: nil, scope: .document)
        check(!long.isComplete && long.text.count <= ResearchAIContext.characterLimit && long.text.contains("paragraph-0") && long.text.contains("paragraph-99"), "bounded document excerpt coverage")
        let selected = ResearchAIContext(paragraphs: ["confidential elsewhere"], selectedText: "chosen excerpt", scope: .selection)
        check(selected.text == "chosen excerpt", "selection must not send rest of document")
        let req = try ResearchAIRequest.make(endpoint: endpoint, model: "test-model", key: "test-key", title: "Test", context: selected, history: [.init(role: .user, text: "prior question"), .init(role: .assistant, text: "prior answer")], question: "new question")
        check(req.httpMethod == "POST" && req.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "authorization")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        check(body["model"] as? String == "test-model" && messages.last?["content"]?.contains("new question") == true && messages.last?["content"]?.contains("chosen excerpt") == true && messages.contains(where: { $0["content"] == "prior answer" }), "request context/history")
        let followup = try ResearchAIRequest.make(endpoint: endpoint, model: "test-model", key: nil, title: "Test", context: ResearchAIContext(paragraphs: [], selectedText: nil, scope: .none), history: [.init(role: .user, text: "previous", selectedExcerpt: "prior selected quote"), .init(role: .assistant, text: "explanation")], question: "follow-up")
        check(String(data: followup.httpBody!, encoding: .utf8)!.contains("prior selected quote"), "follow-up retains bounded prior selection")
        let response = Data(#"{"choices":[{"message":{"content":"answer"}}]}"#.utf8)
        check(try! ResearchAIRequest.parse(response) == "answer", "response parsing")
        check((try? ResearchAIRequest.parse(Data("{}".utf8))) == nil, "invalid response")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ResearchAIHistory(root: root)
        let chat = [ResearchAIMessage(role: .user, text: "test"), ResearchAIMessage(role: .assistant, text: "reply")]
        try store.save(chat, bookID: "book/one")
        check(try! store.load(bookID: "book/one") == chat, "history persisted")
        check(try! store.load(bookID: "book/two").isEmpty, "history isolation")
        try Data("broken".utf8).write(to: store.file(bookID: "book/one"))
        check((try? store.load(bookID: "book/one")) == nil, "history corruption detected")
        let mock = AITransportProbe()
        let defaults = UserDefaults(suiteName: "research-ai-checks-" + UUID().uuidString)!
        defaults.register(defaults: ["researchAI.baseURL": "https://example.com/v1", "researchAI.model": "test-model"])
        let ai = ResearchAI(root: root, defaults: defaults, transport: { try await mock.transport($0) }, readCredential: { _ in "test-key" })
        func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
            for _ in 0..<100 {
                if predicate() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            fatalError("mock transport timed out")
        }
        ai.open(bookID: "first")
        ai.question = "Question A"
        ai.send(title: "Test A", context: full)
        try await waitUntil { mock.continuation != nil }
        check(ai.busy && ai.messages.count == 1 && mock.request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "send start")
        mock.reply()
        try await waitUntil { !ai.busy }
        check(ai.messages.last?.text == "mock response", "successful answer")
        check(try! store.load(bookID: "first").count == 2, "successful answer persisted")
        ai.question = "Question B"
        ai.send(title: "Test A", context: full)
        try await waitUntil { mock.continuation != nil }
        ai.open(bookID: "second")
        mock.reply()
        try await Task.sleep(nanoseconds: 50_000_000)
        check(ai.messages.isEmpty && !ai.busy, "stale reply cannot leak into switched document")
        ai.open(bookID: "first")
        check(ai.messages.count == 3 && ai.messages.last?.text == "Question B", "canceled question remains in source document only")
        ai.open(bookID: "book/one")
        check(!ai.historyAvailable && ai.error != nil, "corrupt history is protected")
        ai.clear()
        check(try! String(contentsOf: store.file(bookID: "book/one"), encoding: .utf8) == "broken", "cannot overwrite corrupt history")
        print("Research AI checks passed: context, endpoints, request/response, history isolation, mock send and cancellation.")
    }
}
