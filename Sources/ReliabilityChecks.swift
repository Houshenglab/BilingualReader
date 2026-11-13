import Foundation
import AppKit

final class StubProtocol: URLProtocol {
    static let lock = NSLock()
    static var handler: (URLRequest) throws -> (Int, [String: String], Data) = { _ in (200, [:], Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.lock.lock(); let handle = Self.handler; Self.lock.unlock()
            let (status, headers, data) = try handle(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw ReaderError.message("FAIL: " + message) }
}
func translator() -> WebTranslator {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return WebTranslator(cacheDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString), testingSession: URLSession(configuration: config))
}
let googleOK = Data(#"[[["测试中文","test",null,null]]]"#.utf8)
let bingOK = Data(#"[{"translations":[{"text":"测试中文","to":"zh-Hans"}]}]"#.utf8)
let bingHTML = Data(#"IG:"abc" data-iid="translator.1" var params_AbusePreventionHelper = [123,"token",3600000];"#.utf8)
@main struct ReliabilityChecks {
    @MainActor static func reviewChecks() async throws {
        var failures: [String] = []
        func check(_ ok: Bool, _ message: String) { print("\(ok ? "PASS" : "FAIL"): \(message)"); if !ok { failures.append(message) } }
        StubProtocol.handler = { _ in (200, [:], googleOK) }
        let automatic = ReaderModel(translator: translator()); automatic.engine = .google
        automatic.paragraphs = [ReadingParagraph(id: 0, text: "automatic", page: nil)]
        automatic.autoTranslate = true
        automatic.enqueueAutomatically(0)
        automatic.pause(); automatic.resume()
        check(automatic.autoTranslate, "pause/resume restores automatic reading preference")
        automatic.stop()
        check(!automatic.autoTranslate, "stop clears automatic mode")
        var requests: [String] = []
        StubProtocol.handler = { request in
            let text = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "q" }!.value!
            requests.append(text)
            return requests.count == 1 ? (503, [:], Data()) : (200, [:], googleOK)
        }
        let priority = ReaderModel(translator: translator()); priority.engine = .google
        priority.paragraphs = (0..<3).map { ReadingParagraph(id: $0, text: "priority \($0)", page: nil) }
        priority.translateAll()
        try await Task.sleep(nanoseconds: 100_000_000)
        priority.toggle(2)
        check(priority.paragraphs[2].expanded, "clicking a queued paragraph keeps its translation visible")
        for _ in 0..<200 where priority.busy { try await Task.sleep(nanoseconds: 20_000_000) }
        check(requests == ["priority 0", "priority 0", "priority 2", "priority 1"], "foreground click prioritizes waiting paragraph without interrupting active request")
        if !failures.isEmpty { exit(1) }
    }
    @MainActor static func main() async throws {
        if CommandLine.arguments.contains("--review") { try await reviewChecks(); return }
        var calls = 0
        StubProtocol.handler = { _ in
            calls += 1
            if calls == 1 { throw URLError(.timedOut) }
            return (200, [:], googleOK)
        }
        do {
            let result = try await translator().translate("test", engine: .google)
            try expect(result == "测试中文" && calls == 2, "timeout retries and returns translation")
        } catch { throw ReaderError.message("FAIL: transient timeout must recover: \(error.localizedDescription)") }
        print("PASS: transient timeout recovery")
        calls = 0
        StubProtocol.handler = { _ in calls += 1; throw URLError(.timedOut) }
        do { _ = try await translator().translate("test", engine: .google); throw ReaderError.message("unexpected success") }
        catch { try expect(calls == 3, "retry count is bounded at three attempts") }
        print("PASS: retry bound")

        calls = 0
        StubProtocol.handler = { _ in
            calls += 1
            return calls == 1 ? (429, ["Retry-After": "0"], Data()) : (200, [:], googleOK)
        }
        _ = try await translator().translate("test", engine: .google)
        try expect(calls == 2, "short Retry-After recovers")
        calls = 0
        StubProtocol.handler = { _ in calls += 1; return (429, ["Retry-After": "600"], Data()) }
        do { _ = try await translator().translate("test", engine: .google); throw ReaderError.message("unexpected success") }
        catch let error as TranslationFailure { try expect(error.shouldPause && calls == 1, "long Retry-After pauses without hammering") }
        print("PASS: rate-limit recovery and pause")

        var pages = 0; var posts = 0
        StubProtocol.handler = { request in
            if request.url!.path == "/translator" { pages += 1; return (200, [:], bingHTML) }
            posts += 1; return (200, [:], bingOK)
        }
        let bing = translator()
        _ = try await bing.translate("first", engine: .bing)
        _ = try await bing.translate("second", engine: .bing)
        try expect(pages == 1 && posts == 2, "reuse Bing credentials for successive requests")
        pages = 0; posts = 0
        StubProtocol.handler = { request in
            if request.url!.path == "/translator" { pages += 1; return (200, [:], bingHTML) }
            posts += 1; return posts == 1 ? (403, [:], Data()) : (200, [:], bingOK)
        }
        _ = try await translator().translate("refresh", engine: .bing)
        try expect(pages == 2 && posts == 2, "expired credentials refreshed once")
        print("PASS: Bing credential reuse and refresh")

        let long = String(repeating: "a", count: 2500) + " " + String(repeating: "b", count: 100)
        var firstCalls = 0; var secondCalls = 0
        StubProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "q" }!.value!
            if query.first == "a" { firstCalls += 1; return (200, [:], googleOK) }
            secondCalls += 1
            return secondCalls == 1 ? (400, [:], Data()) : (200, [:], googleOK)
        }
        let partial = translator()
        do { _ = try await partial.translate(long, engine: .google) } catch {}
        let full = try await partial.translate(long, engine: .google)
        try expect(firstCalls == 1 && secondCalls == 2 && full == "测试中文 测试中文", "retry reuses completed chunks without truncation")
        print("PASS: partial progress reused")

        calls = 0
        StubProtocol.handler = { _ in calls += 1; throw URLError(.timedOut) }
        let cancelled = translator()
        let task = Task { try await cancelled.translate("cancel", engine: .google) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; throw ReaderError.message("unexpected success") } catch is CancellationError {}
        try expect(calls == 1, "cancel interrupts retry wait")
        let info = await cancelled.cacheInfo()
        try expect(info.count == 0, "cancelled work does not populate cache")
        print("PASS: cancellation stops retries and cache writes")

        let cleared = translator()
        calls = 0
        StubProtocol.handler = { _ in calls += 1; return calls == 1 ? (503, [:], Data()) : (200, [:], googleOK) }
        let stale = Task { try await cleared.translate("stale", engine: .google) }
        try await Task.sleep(nanoseconds: 100_000_000)
        try await cleared.clearCache()
        do { _ = try await stale.value; throw ReaderError.message("unexpected success") } catch is CancellationError {}
        let empty = await cleared.cacheInfo()
        try expect(empty.count == 0, "clearing cache rejects late response")
        print("PASS: late response after clear rejected")
        calls = 0
        StubProtocol.handler = { _ in calls += 1; return calls == 1 ? (400, [:], Data()) : (200, [:], googleOK) }
        let model = ReaderModel(translator: translator())
        model.engine = .google
        model.paragraphs = (0..<3).map { ReadingParagraph(id: $0, text: "paragraph \($0)", page: nil) }
        model.enqueue(0, priority: false); model.enqueue(1, priority: false); model.enqueue(2, priority: false)
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 50_000_000) }
        try expect(model.paragraphs[0].error != nil && model.paragraphs[1].translation != nil && model.paragraphs[2].translation != nil, "a bad paragraph must not discard later requests")
        print("PASS: queue continues after isolated content failure")
        StubProtocol.handler = { _ in (429, ["Retry-After": "600"], Data()) }
        let paused = ReaderModel(translator: translator())
        paused.engine = .google
        paused.paragraphs = (0..<3).map { ReadingParagraph(id: $0, text: "paused \($0)", page: nil) }
        paused.translateAll()
        for _ in 0..<100 where !paused.isPaused { try await Task.sleep(nanoseconds: 20_000_000) }
        try expect(paused.isPaused && paused.pendingCount == 3 && !paused.busy, "429 retains active and pending paragraphs")
        StubProtocol.handler = { _ in (200, [:], googleOK) }
        paused.resume()
        for _ in 0..<100 where paused.busy { try await Task.sleep(nanoseconds: 20_000_000) }
        try expect(paused.translatedCount == 3 && paused.pendingCount == 0, "resume completes retained queue")
        paused.pdfMode = .paragraphs
        paused.pdfMode = .original
        try expect(paused.translatedCount == 3, "reading modes share translations")
        print("PASS: queue pause/resume and shared reading modes")

        StubProtocol.handler = { _ in throw URLError(.timedOut) }
        let stopped = ReaderModel(translator: translator())
        stopped.engine = .google
        stopped.paragraphs = [ReadingParagraph(id: 0, text: "stopped", page: nil)]
        stopped.translateAll()
        try await Task.sleep(nanoseconds: 100_000_000)
        stopped.stop()
        try await Task.sleep(nanoseconds: 100_000_000)
        try expect(!stopped.busy && stopped.pendingCount == 0 && stopped.translatedCount == 0 && stopped.paragraphs[0].activity == nil, "stop invalidates active generation")
        print("PASS: stopping queue invalidates old work")
        calls = 0
        StubProtocol.handler = { _ in calls += 1; return (401, [:], Data()) }
        let auth = ReaderModel(translator: translator()); auth.engine = .google
        auth.paragraphs = [ReadingParagraph(id: 0, text: "auth", page: nil), ReadingParagraph(id: 1, text: "later", page: nil)]
        auth.translateAll()
        for _ in 0..<100 where !auth.isPaused { try await Task.sleep(nanoseconds: 20_000_000) }
        try expect(auth.isPaused && auth.pendingCount == 2 && calls == 1, "authentication failures pause all work without retry")
        auth.stop()
        print("PASS: authentication pause")

        calls = 0
        StubProtocol.handler = { _ in calls += 1; return (503, [:], Data()) }
        let circuit = ReaderModel(translator: translator()); circuit.engine = .google
        circuit.paragraphs = (0..<4).map { ReadingParagraph(id: $0, text: "circuit \($0)", page: nil) }
        circuit.translateAll()
        for _ in 0..<650 where !circuit.isPaused { try await Task.sleep(nanoseconds: 20_000_000) }
        try expect(circuit.isPaused && circuit.pendingCount == 4 && calls == 9, "three exhausted transient failures pause and retain all unfinished work")
        circuit.stop()
        print("PASS: service failure circuit preserves work")

        let preparing = ReaderModel(translator: translator())
        preparing.documentReady = false
        preparing.paragraphs = [ReadingParagraph(id: 0, text: "not ready", page: nil)]
        preparing.translateAll(); preparing.enqueue(0)
        try expect(!preparing.busy && preparing.pendingCount == 0, "Word cannot queue before rendered paragraph IDs are ready")
        print("PASS: Word readiness guard")

        calls = 0
        StubProtocol.handler = { _ in calls += 1; return (200, [:], Data("<html>service unavailable</html>".utf8)) }
        let malformed = ReaderModel(translator: translator()); malformed.engine = .google
        malformed.paragraphs = (0..<2).map { ReadingParagraph(id: $0, text: "malformed \($0)", page: nil) }
        malformed.translateAll()
        for _ in 0..<100 where malformed.busy { try await Task.sleep(nanoseconds: 20_000_000) }
        try expect(malformed.isPaused && malformed.pendingCount == 2 && calls == 1, "changed webpage response pauses queue")
        print("PASS: changed response format pauses service")
    }
}
