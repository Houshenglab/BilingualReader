import SwiftUI
import AppKit
import PDFKit

@main struct ReaderPreview {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = ReaderModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "双语阅读 · 界面检查"
        let host = NSHostingView(rootView: ReaderView(model: model))
        window.contentView = host
        window.center(); window.makeKeyAndOrderFront(nil)
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/previews")
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(_ name: String) async throws {
            try await Task.sleep(nanoseconds: 800_000_000)
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            let destination = output.appendingPathComponent(name + ".png")
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-l", String(window.windowNumber), destination.path]
            let code: Int32 = try await withCheckedThrowingContinuation { continuation in
                shot.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
                do { try shot.run() } catch { continuation.resume(throwing: error) }
            }
            if code == 0 {
                print("PREVIEW: \(name) (window capture)")
                return
            }
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw ReaderError.message("Cannot create preview") }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { throw ReaderError.message("Cannot encode preview") }
            try png.write(to: output.appendingPathComponent(name + ".png"))
            print("PREVIEW: \(name)")
        }
        Task { @MainActor in
            do {
                try await capture("welcome")
                let paper = URL(fileURLWithPath: CommandLine.arguments[1])
                model.open(paper)
                for _ in 0..<400 where model.importing { try await Task.sleep(nanoseconds: 50_000_000) }
                guard model.documentURL == paper else { throw ReaderError.message("PDF import failed") }
                let selected = model.paragraphs.firstIndex { $0.text.hasPrefix("Africa has been identified") } ?? 0
                model.selectedPDFParagraph = selected
                model.paragraphs[selected].expanded = true
                model.paragraphs[selected].translation = "非洲被认为是当前大气甲烷浓度上升的重要推动因素，过去主要归因于湿地和牲畜排放。本研究表明，快速扩张的水稻种植也是一个重要来源，估计约占当前全球甲烷排放增量的 7%。为满足人口快速增长而持续扩大的水稻种植，应纳入气候变化减缓目标的考虑。"
                model.status = "点击原文段落，在右侧阅读对应中文"
                @MainActor func findPDF(_ view: NSView) -> PDFView? {
                    if let pdf = view as? PDFView { return pdf }
                    for child in view.subviews { if let pdf = findPDF(child) { return pdf } }
                    return nil
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard let pdfView = findPDF(host), pdfView.document?.pageCount == 5, pdfView.scaleFactor > 0, !pdfView.visiblePages.isEmpty else { throw ReaderError.message("PDF view has no visible pages") }
                print("PDF VIEW: pages=\(pdfView.document!.pageCount), visible=\(pdfView.visiblePages.count), scale=\(pdfView.scaleFactor), frame=\(pdfView.frame)")
                try await capture("pdf-original")
                window.appearance = NSAppearance(named: .darkAqua)
                try await capture("pdf-dark")
                window.appearance = NSAppearance(named: .aqua)
                let sampleTranslation = model.paragraphs[selected].translation
                model.paragraphs[selected].translation = nil
                model.paragraphs[selected].activity = "已暂停 · 等待继续"
                model.paragraphs[selected].error = "请求暂时限流，待翻译内容已保留。"
                model.isPaused = true
                try await capture("pdf-paused")
                model.isPaused = false
                model.paragraphs[selected].activity = nil
                model.paragraphs[selected].error = nil
                model.paragraphs[selected].translation = sampleTranslation
                model.pdfMode = .paragraphs
                try await capture("pdf-paragraphs")
                window.setContentSize(NSSize(width: 900, height: 650))
                try await capture("pdf-compact")
                window.setContentSize(NSSize(width: 1120, height: 800))
                let word = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("fixtures/rich-example.docx")
                model.open(word)
                for _ in 0..<400 where model.importing || !model.documentReady { try await Task.sleep(nanoseconds: 50_000_000) }
                guard model.documentReady else { throw ReaderError.message("Word render not ready") }
                for i in model.paragraphs.indices {
                    model.paragraphs[i].expanded = true
                    model.paragraphs[i].translation = ["双语阅读示例", "阅读帮助我们理解世界。", "保留原文格式，并在下方阅读对应的中文译文。", "表格单元格中的译文会留在原单元格内。"][min(i, 3)]
                }
                try await capture("word-inline")
                print("PASS: native PDF A/B and Word previews")
                window.orderOut(nil); exit(0)
            } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }
}
