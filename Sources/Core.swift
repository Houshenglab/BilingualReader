import Foundation
import PDFKit
import AppKit
import CryptoKit
import Security

struct ReadingParagraph: Identifiable, Codable {
    let id: Int
    let text: String
    let page: Int?
    var sourceRegions: [PDFSourceRegion] = []
    var kind: String = "body"
    var translation: String? = nil
    var expanded = false
    var loading = false
    var error: String? = nil
    var activity: String? = nil
}

enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

// Paragraph extraction is local. The source file is never rewritten.
enum DocumentLoader {
    static func load(_ url: URL) throws -> [ReadingParagraph] {
        let ext = url.pathExtension.lowercased()
        var blocks: [(String, Int?)] = []
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { throw ReaderError.message("无法打开这份 PDF。") }
            guard !pdf.isLocked else { throw ReaderError.message("这份 PDF 有密码保护，请先解锁。") }
            let paragraphs = try PDFLayout.document(pdf, sourceURL: url)
            guard !paragraphs.isEmpty else { throw ReaderError.message("没有找到可读取的文字。扫描版 PDF 暂不支持，请先进行 OCR。") }
            return paragraphs
        } else if ext == "docx" {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            task.arguments = ["-p", url.path, "word/document.xml"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { throw ReaderError.message("无法读取 Word 文档，请确认它是有效的 .docx 文件。") }
            let delegate = WordParagraphParser()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            guard parser.parse() else { throw ReaderError.message("Word 文档结构损坏，无法读取。") }
            blocks = delegate.paragraphs.map { ($0, nil) }
        } else if ext == "doc" {
            throw ReaderError.message("请先在 Word 中将旧版 .doc 另存为 .docx，然后打开。")
        } else {
            let text = try String(contentsOf: url, encoding: .utf8)
            blocks = text.components(separatedBy: "\n\n").map { ($0, nil) }
        }
        let nonempty = blocks.filter { !$0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonempty.isEmpty else { throw ReaderError.message("没有找到可读取的文字。扫描版 PDF 暂不支持，请先进行 OCR。") }
        return nonempty.enumerated().map {
            ReadingParagraph(id: $0.offset, text: $0.element.0.trimmingCharacters(in: .whitespacesAndNewlines), page: $0.element.1)
        }
    }


}

final class WordParagraphParser: NSObject, XMLParserDelegate {
    var paragraphs: [String] = []
    private var current = ""
    private var inText = false
    private var depth = 0
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if name == "w:p" { if depth == 0 { current = "" }; depth += 1 }
        if name == "w:t" { inText = true }
        if name == "w:tab" { current += "\t" }
        if name == "w:br" || name == "w:cr" { current += "\n" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { current += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        if name == "w:t" { inText = false }
        if name == "w:p" {
            depth -= 1
            if depth == 0 && !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { paragraphs.append(current) }
        }
    }
}

enum TranslationEngine: String, CaseIterable, Identifiable {
    case bing = "必应 · 免密钥"
    case google = "Google · 免密钥"
    case azure = "微软官方 · F0 免费档"
    var id: String { rawValue }
}

enum CredentialStore {
    static let service = "local.bilingualreader.mac.translation"
    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: "azure-f0", kSecReturnData as String: true,
                                  kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "azure-f0"]
        let value: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(value) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ReaderError.message("无法保存到系统钥匙串（\(status)）。") }
    }
    static func remove() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "azure-f0"]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ReaderError.message("无法移除钥匙串密钥（\(status)）。") }
    }
}

enum TranslationFailure: LocalizedError {
    case http(Int, TimeInterval?)
    case network(URLError.Code)
    case configuration(String)
    case response(String, Bool)

    var isTransient: Bool {
        switch self {
        case .http(let status, _): return status == 408 || (500...599).contains(status)
        case .network(let code): return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(code)
        default: return false
        }
    }
    var shouldPause: Bool {
        switch self {
        case .http(let status, _): return [401, 403, 429].contains(status)
        case .configuration: return true
        case .response(_, let pause): return pause
        default: return false
        }
    }
    var errorDescription: String? {
        switch self {
        case .http(429, _): return "服务暂时限流或额度已用完，任务已保留。请稍后继续或切换服务。"
        case .http(401, _), .http(403, _): return "服务拒绝了请求，请检查密钥、区域或服务访问情况后继续。"
        case .http(let status, _): return "翻译服务返回 HTTP \(status)，可稍后重试。"
        case .network(.timedOut): return "翻译请求超时，已尝试重连。可稍后重试这一段。"
        case .network: return "无法连接翻译服务，请检查网络后继续。"
        case .configuration(let message), .response(let message, _): return message
        }
    }
}

typealias TranslationProgress = @Sendable (String) async -> Void

actor WebTranslator {
    private var cache: [String: String] = [:]
    private var cacheGeneration = UUID()
    private let cacheURL: URL
    private let session: URLSession
    private var chunkCache: [String: String] = [:]
    private struct BingCredentials {
        let ig: String; let iid: String; let key: String; let token: String; let expires: Date
    }
    private var bingCredentials: BingCredentials?
    init(cacheDirectory: URL? = nil, testingSession: URLSession? = nil) {
        let directory = cacheDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BilingualReader")
        cacheURL = directory.appendingPathComponent("translations.json")
        if let data = try? Data(contentsOf: cacheURL), let values = try? JSONDecoder().decode([String: String].self, from: data) { cache = values }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        session = testingSession ?? URLSession(configuration: config)
    }
    private func cacheKey(_ text: String, engine: TranslationEngine) -> String {
        SHA256.hash(data: Data((engine.rawValue + "|zh-CN|" + text).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func translate(_ text: String, engine: TranslationEngine, progress: @escaping TranslationProgress = { _ in }) async throws -> String {
        try Task.checkCancellation()
        let version = cacheGeneration
        let key = cacheKey(text, engine: engine)
        if let cached = cache[key] { return cached }
        let parts = Self.chunks(text, limit: engine == .bing ? 900 : 2500)
        var pieces: [String] = []
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            guard version == cacheGeneration else { throw CancellationError() }
            let partKey = cacheKey(part, engine: engine)
            if let value = chunkCache[partKey] { pieces.append(value); continue }
            await progress(parts.count > 1 ? "正在翻译 · 片段 \(index + 1)/\(parts.count)" : "正在翻译…")
            let value: String
            switch engine {
            case .google: value = try await google(part, progress: progress)
            case .bing: value = try await bing(part, progress: progress)
            case .azure: value = try await azure(part, progress: progress)
            }
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranslationFailure.response("服务返回了空译文，请重试这一段。", false)
            }
            try Task.checkCancellation()
            guard version == cacheGeneration else { throw CancellationError() }
            chunkCache[partKey] = value
            pieces.append(value)
            if index < parts.count - 1 { try await Task.sleep(nanoseconds: 250_000_000) }
        }
        let result = pieces.joined(separator: " ")
        guard !result.isEmpty else { throw TranslationFailure.response("没有可翻译的文字。", false) }
        try Task.checkCancellation()
        guard version == cacheGeneration else { throw CancellationError() }
        cache[key] = result
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
        return result
    }
    static func chunks(_ text: String, limit: Int) -> [String] {
        var remaining = text[...]
        var result: [String] = []
        while remaining.count > limit {
            let end = remaining.index(remaining.startIndex, offsetBy: limit)
            let window = remaining[..<end]
            let midpoint = window.index(window.startIndex, offsetBy: window.count / 2)
            let sentence = window.indices.last { i in
                i >= midpoint && ".!?。！？".contains(window[i]) && window.index(after: i) < end && window[window.index(after: i)].isWhitespace
            }.map { window.index(after: $0) }
            let split = sentence ?? window.lastIndex(where: { $0.isWhitespace }) ?? end
            let boundary = split == remaining.startIndex ? end : split
            result.append(String(remaining[..<boundary]))
            remaining = remaining[boundary...]
            while remaining.first?.isWhitespace == true { remaining.removeFirst() }
        }
        if !remaining.isEmpty { result.append(String(remaining)) }
        return result
    }
    private func fetch(_ request: URLRequest, progress: @escaping TranslationProgress) async throws -> Data {
        for attempt in 0...2 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw TranslationFailure.response("服务返回了无效响应。", false) }
                guard (200..<300).contains(http.statusCode) else {
                    throw TranslationFailure.http(http.statusCode, Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After")))
                }
                return data
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                let failure: TranslationFailure
                if let value = error as? TranslationFailure { failure = value }
                else if let value = error as? URLError { failure = .network(value.code) }
                else { throw error }
                var delay = Double(1 << attempt)
                var retry = failure.isTransient
                if case .http(429, let after) = failure {
                    delay = max(delay, after ?? 3)
                    retry = delay <= 30
                }
                guard retry && attempt < 2 else { throw failure }
                await progress("等待 \(Int(ceil(delay))) 秒后重试 · \(attempt + 1)/2")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw TranslationFailure.response("翻译未完成。", false)
    }
    static func retryAfter(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSinceNow) }
    }
    private func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        return req
    }
    private func google(_ text: String, progress: @escaping TranslationProgress) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [URLQueryItem(name: "client", value: "gtx"), URLQueryItem(name: "sl", value: "auto"), URLQueryItem(name: "tl", value: "zh-CN"), URLQueryItem(name: "dt", value: "t"), URLQueryItem(name: "q", value: text)]
        let data = try await fetch(request(components.url!), progress: progress)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [Any], let segments = json.first as? [[Any]] else { throw TranslationFailure.response("Google 响应格式发生变化，请稍后继续或切换服务。", true) }
        return segments.compactMap { $0.first as? String }.joined()
    }
    static func azureRequest(text: String, key: String, region: String) throws -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to=zh-Hans&textType=plain")!)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        if !region.isEmpty && region.lowercased() != "global" { req.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region") }
        req.httpBody = try JSONSerialization.data(withJSONObject: [["Text": text]])
        return req
    }
    static func azureResult(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let translations = json.first?["translations"] as? [[String: Any]],
              let text = translations.first?["text"] as? String, !text.isEmpty else {
            throw ReaderError.message("微软官方接口未返回有效译文。请检查 F0 资源配置。")
        }
        return text
    }
    private func azure(_ text: String, progress: @escaping TranslationProgress) async throws -> String {
        guard UserDefaults.standard.bool(forKey: "azureF0Confirmed"), let key = CredentialStore.read(), !key.isEmpty else {
            throw TranslationFailure.configuration("请在设置中配置微软 Translator F0 免费档密钥。")
        }
        let req = try Self.azureRequest(text: text, key: key, region: UserDefaults.standard.string(forKey: "azureRegion") ?? "global")
        return try Self.azureResult(await fetch(req, progress: progress))
    }
    private func credentials(progress: @escaping TranslationProgress) async throws -> BingCredentials {
        if let credentials = bingCredentials, credentials.expires > Date() { return credentials }
        await progress("正在连接必应…")
        let data = try await fetch(request(URL(string: "https://www.bing.com/translator")!), progress: progress)
        let html = String(decoding: data, as: UTF8.self)
        let ig = Self.capture(#"IG:"([^"]+)""#, html) ?? Self.capture(#""ig":"([^"]+)""#, html)
        let iid = Self.capture(#"data-iid="([^"]+)""#, html)
        let key = Self.capture(#"params_AbusePreventionHelper\s*=\s*\[(\d+),"#, html)
        let token = Self.capture(#"params_AbusePreventionHelper\s*=\s*\[\d+,"([^"]+)""#, html)
        guard let ig, let iid, let key, let token else {
            throw TranslationFailure.response("必应网页暂时无法使用，请稍后继续或切换服务。", true)
        }
        let duration = Self.capture(#"params_AbusePreventionHelper\s*=\s*\[\d+,"[^"]+",\s*(\d+)"#, html).flatMap(Double.init).map { $0 / 1000 } ?? 300
        let value = BingCredentials(ig: ig, iid: iid, key: key, token: token, expires: Date().addingTimeInterval(max(1, min(1800, duration - 30))))
        bingCredentials = value
        return value
    }
    private func bing(_ text: String, progress: @escaping TranslationProgress) async throws -> String {
        for refresh in 0...1 {
            let credentials = try await credentials(progress: progress)
            var components = URLComponents(string: "https://www.bing.com/ttranslatev3")!
            components.queryItems = [URLQueryItem(name: "IG", value: credentials.ig), URLQueryItem(name: "IID", value: credentials.iid)]
            var req = request(components.url!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data([("fromLang", "auto-detect"), ("to", "zh-Hans"), ("text", text), ("token", credentials.token), ("key", credentials.key)].map { Self.encode($0.0) + "=" + Self.encode($0.1) }.joined(separator: "&").utf8)
            do {
                let data = try await fetch(req, progress: progress)
                let json = try? JSONSerialization.jsonObject(with: data)
                if let error = json as? [String: Any], let code = error["statusCode"] as? Int { throw TranslationFailure.http(code, nil) }
                guard let response = json as? [[String: Any]], let translations = response.first?["translations"] as? [[String: Any]], let value = translations.first?["text"] as? String else {
                    throw TranslationFailure.response("必应未返回有效译文，请稍后继续或切换服务。", true)
                }
                return value
            } catch let failure as TranslationFailure {
                if case .http(let code, _) = failure, [400, 401, 403].contains(code), refresh == 0 {
                    bingCredentials = nil
                    continue
                }
                if case .http(let code, _) = failure, [400, 401, 403].contains(code) {
                    throw TranslationFailure.configuration("必应网页验证未通过，待翻译内容已保留。可在设置中选择 Google，或稍后继续。")
                }
                throw failure
            }
        }
        throw TranslationFailure.configuration("必应凭证刷新失败，请稍后继续。")
    }
    private static func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~")))! }
    private static func capture(_ pattern: String, _ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    func cacheInfo() -> (count: Int, bytes: Int64) {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        return (cache.count, bytes)
    }
    func clearCache() throws {
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try FileManager.default.removeItem(at: cacheURL)
        }
        cacheGeneration = UUID()
        cache.removeAll()
        chunkCache.removeAll()
        bingCredentials = nil
    }
}
