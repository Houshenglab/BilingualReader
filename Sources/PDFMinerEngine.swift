import Foundation
import PDFKit

enum PDFMinerEngine {
    struct TextLine: Decodable { let text: String; let bounds: [Double]; let fontSize: Double?; let fontName: String? }
    struct TextBox: Decodable { let lines: [TextLine]; let isArtwork: Bool? }
    struct Page: Decodable { let number: Int; let boxes: [TextBox] }
    static func resourceDirectory() -> URL? {
        let fm = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("PDFEngine"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/PDFEngine"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("BilingualReader/Resources/PDFEngine")
        ].compactMap { $0 }
        return candidates.first { fm.isExecutableFile(atPath: $0.appendingPathComponent("python/bin/python3").path) }
    }
    static func extract(_ url: URL) throws -> [Page] {
        guard let resources = resourceDirectory() else {
            throw ReaderError.message("应用的 PDF 解析引擎缺失，请打开完整的新版 App。")
        }
        let process = Process()
        process.executableURL = resources.appendingPathComponent("python/bin/python3")
        process.arguments = ["-I", "-B", resources.appendingPathComponent("layout.py").path, url.path]
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: deadline)
        defer { deadline.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ReaderError.message("PDF 版面分析未完成。" + (detail.isEmpty ? "请稍后重试或换一份文件。" : String(detail.prefix(350))))
        }
        return try JSONDecoder().decode([Page].self, from: data)
    }
    static func sourceBounds(_ values: [Double], page: PDFPage) -> CGRect {
        guard values.count == 4 else { return .null }
        let b = CGRect(x: values[0], y: values[1], width: values[2] - values[0], height: values[3] - values[1])
        let media = page.bounds(for: .mediaBox)
        let rotation = (page.rotation % 360 + 360) % 360
        let unrotated: CGRect
        switch rotation {
        case 90: unrotated = CGRect(x: media.width - b.maxY, y: b.minX, width: b.height, height: b.width)
        case 180: unrotated = CGRect(x: media.width - b.maxX, y: media.height - b.maxY, width: b.width, height: b.height)
        case 270: unrotated = CGRect(x: b.minY, y: media.height - b.maxX, width: b.height, height: b.width)
        default: unrotated = b
        }
        return unrotated.offsetBy(dx: media.minX, dy: media.minY)
    }
}
