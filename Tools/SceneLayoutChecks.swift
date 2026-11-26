import SwiftUI
import AppKit

@main struct SceneLayoutChecks: App {
    @StateObject private var model = ReaderModel(library: LibraryStore(root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/scene-library")))
    var body: some Scene {
        WindowGroup("双语阅读") {
            ReaderView(model: model).task {
                try? await Task.sleep(nanoseconds:800_000_000)
                let now = Date()
                model.libraryBooks = (0..<3).map { i in LibraryBook(id: String(repeating: String(i+1), count: 64), title: ["Research methods and climate change", "Global water management", "Atmospheric science and ecosystems"][i], fileName: "example.pdf", format: "pdf", addedAt: now, lastOpened: now, pageCount: 27, translatedCount: 54, page: 19) }
                try? await Task.sleep(nanoseconds:800_000_000)
                guard let window=NSApp.windows.first(where: {$0.isVisible}), let content=window.contentView else { fputs("No window\n",stderr);exit(1) }
                window.setContentSize(NSSize(width:1300,height:630)); window.center(); window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(nanoseconds:800_000_000)
                guard model.libraryBooks.count == 3 else { fputs("Fixture books missing\n", stderr); exit(1) }
                print("Window style: \(window.styleMask.rawValue) fullSize=\(window.styleMask.contains(.fullSizeContentView)) transparent=\(window.titlebarAppearsTransparent) content=\(content.frame) layout=\(window.contentLayoutRect)")
                guard !window.styleMask.contains(.fullSizeContentView), abs(content.frame.height-window.contentLayoutRect.height)<2 else { fputs("FAIL: content extends under native titlebar\n",stderr); exit(1) }
                fflush(stdout)
                let destination=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/scene-check.png")
                let shot=Process();shot.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture");shot.arguments=["-x","-l",String(window.windowNumber),destination.path]
                try? shot.run();shot.waitUntilExit()
                if shot.terminationStatus != 0, let rep=content.bitmapImageRepForCachingDisplay(in:content.bounds) { content.cacheDisplay(in:content.bounds,to:rep);try? rep.representation(using:.png,properties:[:])?.write(to:destination) }
                window.setContentSize(NSSize(width:900,height:600)); window.center()
                try? await Task.sleep(nanoseconds:600_000_000)
                guard !window.styleMask.contains(.fullSizeContentView), abs(content.frame.height-window.contentLayoutRect.height)<2 else { fputs("FAIL: compact content extends under titlebar\n",stderr); exit(1) }
                let compact=destination.deletingLastPathComponent().appendingPathComponent("scene-compact.png")
                if let rep=content.bitmapImageRepForCachingDisplay(in:content.bounds) { content.cacheDisplay(in:content.bounds,to:rep);try? rep.representation(using:.png,properties:[:])?.write(to:compact) }
                print("PASS: native scene titlebar separates content at wide and compact sizes")
                exit(0)
            }
        }.windowStyle(.titleBar).defaultSize(width:1210,height:820)
    }
}
