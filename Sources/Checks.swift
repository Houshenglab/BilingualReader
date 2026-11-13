import Foundation
import AppKit
import PDFKit

@main
struct Checks {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let word = try DocumentLoader.load(root.appendingPathComponent("fixtures/example.docx"))
        precondition(word.count == 4, "DOCX paragraph and table-cell extraction")
        precondition(word[1].text == "Reading helps us understand the world.")
        precondition(word[2].text.contains("&"), "XML entities must be decoded")
        precondition(word[3].text.contains("Table cell"), "Table cells must not be lost")
        let longText = Array(repeating: "Methane emissions 中文🙂 and water management.", count: 200).joined(separator: " ")
        let parts = WebTranslator.chunks(longText, limit: 900)
        precondition(parts.allSatisfy { $0.count <= 900 })
        precondition(parts.joined(separator: " ") == longText, "No truncation or unicode corruption")
        let noSpaces = String(repeating: "a", count: 5200)
        precondition(WebTranslator.chunks(noSpaces, limit: 900).joined() == noSpaces)
        let request = try WebTranslator.azureRequest(text: "Hello & 中文", key: "TEST-KEY-NOT-REAL", region: "eastasia")
        precondition(request.url?.host == "api.cognitive.microsofttranslator.com")
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Region") == "eastasia")
        precondition(!request.url!.absoluteString.contains("TEST-KEY"), "Credentials must not be embedded in URLs")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [[String: String]]
        precondition(body[0]["Text"] == "Hello & 中文")
        let sample = Data(#"[{"translations":[{"text":"你好","to":"zh-Hans"}]}]"#.utf8)
        let sampleResult = try WebTranslator.azureResult(sample)
        precondition(sampleResult == "你好")
        print("PASS: official Azure request headers, payload and response parsing (synthetic; no real key)")

        let cacheFolder = root.appendingPathComponent("build/cache-regression-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheFolder) }
        let cacheFile = cacheFolder.appendingPathComponent("translations.json")
        try JSONEncoder().encode(["example": "示例"]).write(to: cacheFile)
        let unrelated = cacheFolder.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        let cachedTranslator = WebTranslator(cacheDirectory: cacheFolder)
        let before = await cachedTranslator.cacheInfo()
        precondition(before.count == 1 && before.bytes > 0)
        try await cachedTranslator.clearCache()
        let after = await cachedTranslator.cacheInfo()
        precondition(after.count == 0 && after.bytes == 0)
        precondition(FileManager.default.fileExists(atPath: unrelated.path))
        try await cachedTranslator.clearCache()
        let reloaded = await WebTranslator(cacheDirectory: cacheFolder).cacheInfo()
        precondition(reloaded.count == 0)
        print("PASS: cache size, clearing, repeat clearing, persistence and unrelated file preservation")

        let pdfURL = root.appendingPathComponent("fixtures/example.pdf")
        var rectangle = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = CGContext(pdfURL as CFURL, mediaBox: &rectangle, nil)!
        context.beginPDFPage(nil)
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Times New Roman", size: 18)!, .paragraphStyle: style]
        ("Reading local documents" as NSString).draw(at: CGPoint(x: 60, y: 770), withAttributes: attrs)
        ("Reading helps us understand the world.\nWe can compare English and Chinese as we read." as NSString).draw(in: CGRect(x: 60, y: 640, width: 480, height: 95), withAttributes: attrs)
        ("Water management affects methane emissions.\nScientific terms should be checked against the original." as NSString).draw(in: CGRect(x: 60, y: 510, width: 480, height: 95), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        let pdf = try DocumentLoader.load(pdfURL)
        precondition(pdf.count >= 3, "PDF must split separated paragraphs")
        precondition(pdf.allSatisfy { $0.page == 1 })
        print("PASS: DOCX (paragraphs, entities, tables), PDF paragraph extraction, long and Unicode chunking")

        if CommandLine.arguments.contains("--network") {
            let translator = WebTranslator(cacheDirectory: root.appendingPathComponent("build/test-cache"))
            try await translator.clearCache()
            let engine: TranslationEngine = CommandLine.arguments.contains("--bing") ? .bing : .google
            let result = try await translator.translate("Reading helps us understand the world.", engine: engine)
            precondition(result.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil, "Expected Chinese response")
            print("PASS: \(engine.rawValue): \(result)")
            let cached = try await translator.translate("Reading helps us understand the world.", engine: engine)
            precondition(cached == result)
            print("PASS: translation cache")
        }
    }
}
