import SwiftUI
import AppKit
import PDFKit

@main struct PreviewResearch {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let work = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let root = work.appendingPathComponent("build/research-preview-" + UUID().uuidString)
        let model = ReaderModel(translator: WebTranslator(cacheDirectory: root.appendingPathComponent("cache")), notebook: ResearchNotebook(root: root.appendingPathComponent("notes")), researchAI: ResearchAI(root: root.appendingPathComponent("chat")))
        let window = NSWindow(contentRect: CGRect(x:0,y:0,width:1210,height:820),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        let host = NSHostingView(rootView: ReaderView(model:model))
        window.contentView = host; window.center(); window.makeKeyAndOrderFront(nil)
        let output = work.appendingPathComponent("build/research-previews")
        try! FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func wait() async throws { try await Task.sleep(nanoseconds: 800_000_000) }
        func capture(_ name: String) async throws {
            try await wait(); host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            let file = output.appendingPathComponent(name + ".png")
            let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/sbin/screencapture")
            process.arguments = ["-x","-l",String(window.windowNumber),file.path]
            let result:Int32 = try await withCheckedThrowingContinuation { c in
                process.terminationHandler = { c.resume(returning:$0.terminationStatus) }
                do { try process.run() } catch { c.resume(throwing:error) }
            }
            if result != 0 {
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw ReaderError.message("No preview") }
                host.cacheDisplay(in:host.bounds,to:rep); try rep.representation(using:.png,properties:[:])!.write(to:file)
            }
            print("PREVIEW: \(name)")
        }
        func findPDF(in v:NSView) -> ClickablePDFView? {
            if let pdf = v as? ClickablePDFView { return pdf }
            for child in v.subviews { if let pdf = findPDF(in:child) { return pdf } }
            return nil
        }
        func click(_ p:CGPoint) {
            for t in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
                let event=NSEvent.mouseEvent(with:t,location:p,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:t == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event,atStart:false)
            }
        }
        Task { @MainActor in
            do {
                let file = work.appendingPathComponent("fixtures/example.pdf")
                let original = try Data(contentsOf:file)
                model.open(file)
                for _ in 0..<250 where model.importing { try await Task.sleep(nanoseconds:40_000_000) }
                guard model.documentURL == file, !model.paragraphs.isEmpty else { throw ReaderError.message(model.alert ?? "PDF not opened") }
                try await capture("reader-translation")
                guard let pdf = findPDF(in:host), let doc = pdf.document, let page = doc.page(at:0), let source = page.string,
                      let word = source.split(whereSeparator: \.isWhitespace).first, let selection = doc.findString(String(word),withOptions:[]).first else { throw ReaderError.message("Native PDF selection missing") }
                pdf.setCurrentSelection(selection,animate:false)
                let coordinator = LinkedPDF.Coordinator(model)
                coordinator.captureSelection(pdf)
                guard let anchor = model.notebook.selection, !anchor.pdfRegions.isEmpty else { throw ReaderError.message("PDF selection anchor missing") }
                guard model.notebook.highlight(.yellow), model.notebook.addNote(text:"这里记录一条文献批注。",anchor:anchor) else { throw ReaderError.message("Unable to save annotation") }
                model.notebook.requestComment()
                try await capture("reader-annotation")
                guard doc.page(at:0)!.annotations.contains(where:{$0.type == "Highlight" && $0.quadrilateralPoints?.count == 4}) else { throw ReaderError.message("Native PDF highlight missing") }
                let thumb = page.thumbnail(of: CGSize(width: 700,height: 900),for:.cropBox)
                if let data = thumb.tiffRepresentation, let rep=NSBitmapImageRep(data:data), let png=rep.representation(using:.png,properties:[:]) { try png.write(to:output.appendingPathComponent("pdf-markup.png")) }
                guard try Data(contentsOf:file) == original else { throw ReaderError.message("Source file altered") }
                model.notebook.requestedJump = model.notebook.notes[0]
                try await wait()
                guard model.notebook.requestedJump == nil else { throw ReaderError.message("PDF note jump not consumed") }
                model.pdfMode = .paragraphs
                try await capture("reader-paragraph-notes")
                // AI tab is the rightmost named tab of the research navigation row.
                NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil)
                try await wait()
                click(CGPoint(x:width(window)-66,y:window.contentView!.bounds.height-78))
                try await capture("reader-ai")
                print("PASS: native PDF highlight, annotation panel, note jump, original bytes preserved")
                window.orderOut(nil); exit(0)
            } catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
        }
        NSApp.run()
    }
    static func width(_ window:NSWindow)->CGFloat { window.contentView!.bounds.width }
}
