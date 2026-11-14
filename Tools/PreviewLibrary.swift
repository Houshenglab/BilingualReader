import SwiftUI
import AppKit
import PDFKit
import WebKit

@main struct PreviewLibrary {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/library-preview-" + UUID().uuidString)
        let store=LibraryStore(root:root)
        let model=ReaderModel(translator:WebTranslator(cacheDirectory:root.appendingPathComponent("cache")), library:store)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1120,height:800),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="双语阅读 · 书架检查"
        let host=NSHostingView(rootView:ReaderView(model:model));window.contentView=host
        window.center();window.makeKeyAndOrderFront(nil)
        let output=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/bookshelf-previews")
        try! FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func capture(_ name: String, delay: UInt64 = 800_000_000) async throws {
            try await Task.sleep(nanoseconds: delay)
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
        @MainActor func click(_ point: NSPoint, in target: NSWindow) {
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with:type, location:point, modifierFlags:[], timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:target.windowNumber, context:nil, eventNumber:0, clickCount:1, pressure:type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event,atStart:false)
            }
        }
        @MainActor func textField(in view:NSView) -> NSTextField? {
            if let field=view as? NSTextField,field.isEditable { return field }
            for child in view.subviews { if let field=textField(in:child) { return field } }
            return nil
        }
        Task { @MainActor in
            do {
                UserDefaults.standard.set("shelf",forKey:"libraryDisplay")
                try await capture("empty")
                NSApp.activate(ignoringOtherApps:true)
                click(NSPoint(x:998,y:682),in:window)
                try await Task.sleep(nanoseconds:500_000_000)
                guard let sheet=window.attachedSheet,let content=sheet.contentView,let field=textField(in:content) else { throw ReaderError.message("Category editor did not appear") }
                field.stringValue="气候文献"
                NotificationCenter.default.post(name:NSControl.textDidChangeNotification,object:field)
                sheet.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
                field.currentEditor()?.insertText("气候文献")
                try await Task.sleep(nanoseconds:200_000_000)
                let savePoint=NSPoint(x:content.bounds.width-55,y:40)
                click(savePoint,in:sheet)
                for _ in 0..<100 where model.libraryOrganization.categories.isEmpty { try await Task.sleep(nanoseconds:20_000_000) }
                guard let category=model.libraryOrganization.categories.first,category.name=="气候文献" else { throw ReaderError.message("Category editor did not save the name") }
                print("PASS: native category editor creates a named category")
                var imported:[LibraryBook]=[]
                for path in CommandLine.arguments.dropFirst() { imported.append(try await store.importDocument(URL(fileURLWithPath:path))) }
                let words=try await store.importDocument(URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("fixtures/rich-example.docx"))
                for (index,title) in ["Climate notes", "Reading journal", "Research ideas"].enumerated() {
                    let file=root.appendingPathComponent(title+".txt")
                    try "Personal reading note \(index).\n\nA new paragraph to read later.".write(to:file,atomically:true,encoding:.utf8)
                    _=try await store.importDocument(file)
                }
                await model.refreshLibrary()
                try await model.assignLibraryCategory(Set(imported.map(\.id)+[words.id]),to:category.id)
                model.libraryFilter = .category(category.id)
                try await capture("category-shelf")
                click(NSPoint(x:1060,y:682),in:window)
                try await Task.sleep(nanoseconds:400_000_000)
                guard let batchSheet=window.attachedSheet else { throw ReaderError.message("Batch selection did not open") }
                guard let batchContent=batchSheet.contentView else { throw ReaderError.message("Batch sheet has no content") }
                try await capture("category-batch")
                click(NSPoint(x:80,y:batchContent.bounds.height-150),in:batchSheet)
                try await Task.sleep(nanoseconds:200_000_000)
                try await capture("batch-selected")
                click(NSPoint(x:155,y:80),in:batchSheet)
                try await Task.sleep(nanoseconds:200_000_000)
                let menuPoint=batchSheet.convertPoint(toScreen:NSPoint(x:130,y:55))
                let menu=NSApp.windows.first { $0 !== window && $0 !== batchSheet && $0.isVisible && $0.frame.contains(menuPoint) }
                guard let menu else { throw ReaderError.message("Native menu window unavailable") }
                click(menu.convertPoint(fromScreen:menuPoint),in:menu)
                try await Task.sleep(nanoseconds:200_000_000)
                try await capture("batch-target")
                click(NSPoint(x:batchContent.bounds.width-75,y:40),in:batchSheet)
                for _ in 0..<100 where window.attachedSheet != nil { try await Task.sleep(nanoseconds:20_000_000) }
                guard window.attachedSheet == nil,model.matchingBooks(query: "").isEmpty else { throw ReaderError.message("Native batch classification failed") }
                print("PASS: native batch sheet selects visible documents and moves them to Uncategorized")
                try await model.assignLibraryCategory(Set(imported.map(\.id)+[words.id]),to:category.id)
                let emptyCategory=try await model.createLibraryCategory("待读")
                model.libraryFilter = .category(emptyCategory.id)
                try await capture("category-empty")
                try await model.renameLibraryCategory(emptyCategory.id,name:"待读文献")
                try await model.deleteLibraryCategory(emptyCategory.id)
                model.libraryFilter = .all
                try await capture("shelf")
                UserDefaults.standard.set("grid",forKey:"libraryDisplay")
                try await capture("grid")
                UserDefaults.standard.set("shelf",forKey:"libraryDisplay")
                window.appearance=NSAppearance(named:.darkAqua)
                try await capture("dark-shelf")
                window.appearance=NSAppearance(named:.aqua)
                let book=imported.first!
                model.openBook(book)
                for _ in 0..<400 where model.importing { try await Task.sleep(nanoseconds:50_000_000) }
                guard model.currentBookID==book.id else { throw ReaderError.message("Open failed") }
                try await capture("pdf-preparing", delay:350_000_000)
                for _ in 0..<400 where !model.documentReady { try await Task.sleep(nanoseconds:50_000_000) }
                guard model.documentReady else { throw ReaderError.message("Background PDF preparation failed") }
                model.pdfVisiblePage=2;model.paragraphs[0].translation="持久保存测试";model.paragraphs[0].expanded=true
                model.returnToLibrary();await model.flushLibrarySave()
                model.openBook(book)
                for _ in 0..<400 where model.importing { try await Task.sleep(nanoseconds:50_000_000) }
                try await Task.sleep(nanoseconds:1_000_000_000)
                @MainActor func findPDF(_ view:NSView)->PDFView? {
                    if let pdf=view as? PDFView { return pdf };for child in view.subviews { if let pdf=findPDF(child){return pdf} };return nil
                }
                guard let pdf=findPDF(host), let page=pdf.currentPage, pdf.document?.index(for:page)==1,model.paragraphs[0].translation=="持久保存测试" else { throw ReaderError.message("PDF visible page or translation did not restore") }
                print("PASS: native PDF view restores page 2 and completed translation")
                model.pdfMode = .paragraphs
                try await Task.sleep(nanoseconds:500_000_000)
                let pageThree=model.paragraphs.first { !$0.sourceRegions.isEmpty && $0.sourceRegions.allSatisfy{$0.page==3} }!
                model.selectedPDFParagraph=pageThree.id;model.pdfMode = .original
                try await Task.sleep(nanoseconds:1_000_000_000)
                guard let jump=findPDF(host),let target=jump.currentPage,jump.document?.index(for:target)==2, model.pdfVisiblePage==3 else { throw ReaderError.message("Explicit paragraph navigation overwritten by saved PDF page") }
                model.returnToLibrary();await model.flushLibrarySave();model.openBook(book)
                for _ in 0..<400 where model.importing { try await Task.sleep(nanoseconds:50_000_000) }
                try await Task.sleep(nanoseconds:800_000_000)
                guard let reopened=findPDF(host),let page3=reopened.currentPage,reopened.document?.index(for:page3)==2 else { throw ReaderError.message("Explicit page was not persisted for reopen") }
                print("PASS: explicit paragraph navigation overrides saved PDF page and survives reopen")
                model.returnToLibrary();model.openBook(words)
                for _ in 0..<400 where model.importing || !model.documentReady { try await Task.sleep(nanoseconds:50_000_000) }
                guard model.documentReady,model.paragraphs.count==6 else { throw ReaderError.message("Word render failed") }
                model.paragraphs[2].translation="Word 持久保存测试";model.paragraphs[2].expanded=true;model.readingParagraphID=2
                model.returnToLibrary();await model.flushLibrarySave();model.openBook(words)
                for _ in 0..<400 where model.importing || !model.documentReady { try await Task.sleep(nanoseconds:50_000_000) }
                guard model.paragraphs[2].translation=="Word 持久保存测试",model.paragraphs[2].expanded else { throw ReaderError.message("Word DOM readiness erased saved translation") }
                print("PASS: native Word rerender preserves saved translation")
                try await capture("word-restored")
                model.returnToLibrary();try await capture("returned-shelf")
                await model.flushLibrarySave()
                print("PASS: library UI and native document roundtrips")
                try? FileManager.default.removeItem(at:root)
                window.orderOut(nil);exit(0)
            } catch { fputs("FAIL: \(error)\n",stderr);exit(1) }
        }
        NSApp.run()
    }
}
