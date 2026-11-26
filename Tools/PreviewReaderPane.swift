import SwiftUI
import AppKit

@MainActor final class PanePreviewState: ObservableObject {
    @Published var width: Double = 380
}
struct PanePreviewRoot: View {
    @ObservedObject var state: PanePreviewState
    @ObservedObject var ai: ResearchAI
    var body: some View {
        ReaderResizableSplit(presented: true, preferredWidth:$state.width) {
            VStack(alignment:.leading,spacing:16) {
                Text("Example research paper").font(.title.bold())
                Text("A compact document reading area.\n\nThe chat pane can be dragged to give it more space.").font(.title3).lineSpacing(8)
                Spacer()
            }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color(nsColor:.textBackgroundColor))
        } side: {
            ResearchAIView(ai:ai,title:"Example paper",paragraphs:[String(repeating:"Example literature context. ",count:2400)],selectedText:nil,saveNote:{_ in},onDetach:{})
        }.tint(ReaderBrand.accent).accentColor(ReaderBrand.accent)
    }
}
@main struct PreviewReaderPane {
    @MainActor static func main() {
        _=NSApplication.shared;NSApp.setActivationPolicy(.accessory)
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/pane-preview")
        try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let defaults=UserDefaults(suiteName:"BilingualReader.panecheck."+UUID().uuidString)!
        defaults.register(defaults:["researchAI.baseURL":"https://preview.example/v1","researchAI.model":"gpt-6.2-sol"])
        let ai=ResearchAI(root:root.appendingPathComponent("chat"),defaults:defaults,transport:{_ in throw ResearchAIError("Network disabled in preview")},readCredential:{_ in nil})
        UserDefaults.standard.set(64.0,forKey:"researchAI.composerHeight")
        let state=PanePreviewState(),host=NSHostingView(rootView:PanePreviewRoot(state:state,ai:ai))
        let window=NSWindow(contentRect:CGRect(x:0,y:0,width:1120,height:470),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.contentView=host;window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        func wait() async throws {try await Task.sleep(nanoseconds:450_000_000)}
        func capture(_ name:String,view:NSView) async throws {
            try await wait();view.layoutSubtreeIfNeeded()
            guard let image=view.bitmapImageRepForCachingDisplay(in:view.bounds) else {throw ReaderError.message("Cannot capture panel")}
            view.cacheDisplay(in:view.bounds,to:image);try image.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
        }
        func event(_ type:NSEvent.EventType,_ point:CGPoint) {
            let e=NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:type == .leftMouseUp ? 0 : 1)!
            NSApp.postEvent(e,atStart:false)
        }
        Task { @MainActor in
            do {
                try await capture("compact-initial",view:host)
                let start=CGPoint(x:host.bounds.width-state.width-5,y:host.bounds.height/2)
                event(.leftMouseDown,start);try await wait();event(.leftMouseDragged,CGPoint(x:start.x-170,y:start.y));try await wait();event(.leftMouseUp,CGPoint(x:start.x-170,y:start.y))
                try await wait();guard state.width>500 else {throw ReaderError.message("Native drag not applied: \(state.width)")}
                try await capture("expanded-dragged",view:host)
                // Actual mouse drag on the composer handle in the short window.
                let inputStart=CGPoint(x:host.bounds.width-state.width/2,y:105)
                event(.leftMouseDown,inputStart);try await wait();event(.leftMouseDragged,CGPoint(x:inputStart.x,y:inputStart.y+75));try await wait();event(.leftMouseUp,CGPoint(x:inputStart.x,y:inputStart.y+75));try await wait()
                let composerHeight=UserDefaults.standard.double(forKey:"researchAI.composerHeight")
                guard composerHeight>100 else {throw ReaderError.message("Native composer resize not applied: \(composerHeight)")}
                guard ResearchAIView.clampedComposerHeight(999,availableHeight:380)==180,ResearchAIView.clampedComposerHeight(0,availableHeight:470)==48 else {throw ReaderError.message("Composer size bounds failed")}
                try await capture("input-resized",view:host)
                UserDefaults.standard.set(64.0,forKey:"researchAI.composerHeight")
                try ai.store.save([ResearchAIMessage(role:.user,text:"What is the key finding?",contextLabel:"长文献分段摘录 · 非全文"),ResearchAIMessage(role:.assistant,text:"示例回答：这篇文献讨论了研究目标、数据和主要结论。\n\n阅读原文时，可直接对照方法与证据，并将重要回答保存为笔记。")],bookID:"preview")
                ai.open(bookID:"preview");ai.question="尚未发送的草稿"
                try await capture("chat-content",view:host)
                let model=ReaderModel(translator:WebTranslator(cacheDirectory:root.appendingPathComponent("cache")),notebook:ResearchNotebook(root:root.appendingPathComponent("notes")),researchAI:ai)
                model.documentURL=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("fixtures/example.pdf")
                model.showingLibrary=false
                let floating=FloatingResearchAIController();var docked=false
                floating.present(model:model,onDock:{docked=true})
                guard floating.active,ai.question=="尚未发送的草稿",let detached=NSApp.windows.first(where:{$0.title=="AI 文献助手"}),detached.styleMask.contains(.resizable) else {throw ReaderError.message("Floating window missing")}
                let origin=detached.frame.origin;detached.setFrameOrigin(CGPoint(x:origin.x+30,y:origin.y+20));guard detached.frame.origin != origin else {throw ReaderError.message("Floating window cannot move")}
                if let view=detached.contentView {try await capture("floating-chat",view:view)}
                floating.dock();guard docked && !floating.active && ai.question=="尚未发送的草稿" else {throw ReaderError.message("Dock return failed")}
                print("PASS: actual native sidebar and composer drag, movable resizable detached window, docking return and draft preserved")
                window.orderOut(nil);exit(0)
            }catch{fputs("FAIL: \(error)\n",stderr);exit(1)}
        }
        NSApp.run()
    }
}
