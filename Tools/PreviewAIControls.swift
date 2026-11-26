import SwiftUI
import AppKit

@main struct PreviewAIControls {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let work = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = work.appendingPathComponent("build/ai-controls-previews")
        try! FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let root=output.appendingPathComponent("test-data",isDirectory:true)
        let defaults=UserDefaults(suiteName:"local.bilingualreader.aipreview."+UUID().uuidString)!
        defaults.register(defaults:["researchAI.baseURL":"https://preview.example/v1","researchAI.model":"gpt-6.2-sol"])
        let catalog=Data("""
        {"data":[{"id":"gpt-6.2-sol","effort":{"supported_levels":["low","medium","high","xhigh","max"]}},{"id":"gpt-6.2-astra","effort":{"supported_levels":["low","medium","high","xhigh","max"]}},{"id":"gpt-5.4-mini","effort":{"supported_levels":["none","low","medium","high","xhigh"]}},{"id":"local-literature-model"},{"id":"embedding-example"}]}
        """.utf8)
        let ai=ResearchAI(root:root,defaults:defaults,transport:{ request in
            guard request.httpMethod=="GET", request.httpBody==nil, request.url?.host=="preview.example" else { throw ResearchAIError("Mock catalog must be GET to preview.example") }
            return (catalog,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        },readCredential:{_ in "mock-key"})
        let accent=Color(red:0.06,green:0.46,blue:0.43)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:760),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="AI 控件预览 · 模拟目录"
        let panel=NSHostingView(rootView:ResearchAIView(ai:ai,title:"Example paper",paragraphs:["A scientific paper for mock UI testing."],selectedText:"A scientific paper",saveNote:{_ in}).tint(accent).accentColor(accent))
        window.contentView=panel;window.center();window.makeKeyAndOrderFront(nil)
        func capture(_ view:NSView,_ name:String) async throws {
            try await Task.sleep(nanoseconds:450_000_000)
            view.layoutSubtreeIfNeeded()
            guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw ResearchAIError("Preview image is missing") }
            view.cacheDisplay(in:view.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
        }
        Task { @MainActor in
            do {
                await ai.loadModels(base:ai.baseURL)
                guard ai.models(for:ai.baseURL).count == 5 else { throw ResearchAIError("Model catalog did not load") }
                ai.selectEffort(.high)
                try await capture(panel,"ai-panel")
                ai.selectEffort(.xhigh)
                try await capture(panel,"ai-panel-xhigh")
                // Direct settings view shows the same fields as its in-app sheet.
                let settings=NSHostingView(rootView:ResearchAISettings(ai:ai).background(Color(nsColor:.windowBackgroundColor)).tint(accent).accentColor(accent))
                let settingsWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:530,height:630),styleMask:[.titled,.closable],backing:.buffered,defer:false)
                settingsWindow.contentView=settings;settingsWindow.center();settingsWindow.makeKeyAndOrderFront(nil)
                try await capture(settings,"ai-settings")
                let chooser=NSHostingView(rootView:ResearchAIModelChooser(ai:ai,base:ai.baseURL,current:ai.model,onSelect:{ai.selectModel($0)},onManual:{}).background(Color(nsColor:.windowBackgroundColor)).tint(accent).accentColor(accent))
                let chooserWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:340,height:500),styleMask:[.titled,.closable],backing:.buffered,defer:false)
                chooserWindow.contentView=chooser;chooserWindow.center();chooserWindow.makeKeyAndOrderFront(nil)
                try await capture(chooser,"model-directory")
                chooserWindow.orderOut(nil)
                let options=NSHostingView(rootView:ResearchEffortOptions(efforts:ai.efforts(for:ai.model,base:ai.baseURL),selected:ai.effort,onSelect:{ai.selectEffort($0)}).background(Color(nsColor:.windowBackgroundColor)).tint(accent).accentColor(accent))
                let optionsWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:310,height:510),styleMask:[.titled,.closable],backing:.buffered,defer:false)
                optionsWindow.contentView=options;optionsWindow.center();optionsWindow.makeKeyAndOrderFront(nil)
                try await capture(options,"effort-options")
                optionsWindow.orderOut(nil)
                print("PASS: native model and strength controls render from synthetic catalog; no live API calls")
                settingsWindow.orderOut(nil);window.orderOut(nil);exit(0)
            } catch { fputs("FAIL: \(error)\n",stderr);exit(1) }
        }
        NSApp.run()
    }
}
