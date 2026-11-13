import AppKit
import WebKit

@MainActor final class WordChecks: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var view: WKWebView!
    var fixture: URL
    var phase = 0
    init(fixture: URL) { self.fixture = fixture }
    func start() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(self, name: "reader")
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1100, height: 800), configuration: config)
        view.navigationDelegate = self
        let file = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Word/index.html")
        view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {}
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        do {
            let base64 = try Data(contentsOf: fixture).base64EncodedString()
            view.callAsyncJavaScript("return await renderWord(bytes);", arguments: ["bytes": base64], in: nil, in: .page) { result in
                switch result {
                case .failure(let error): self.fail(error.localizedDescription)
                case .success(let value):
                    print("Rendered: \(String(describing: value))")
                    self.validate()
                }
            }
        } catch { fail(error.localizedDescription) }
    }
    func validate() {
        let js = """
        const tableCount=document.querySelectorAll('table').length;
        const imageCount=document.querySelectorAll('img').length;
        const mathCount=document.querySelectorAll('math').length;
        const tableParagraph=nodes.findIndex(p=>p.closest('td'));
        const id=tableParagraph>=0?tableParagraph:Math.min(1,nodes.length-1);
        if(id<0)throw new Error('No paragraphs');
        const original=nodes[id].innerHTML;
        updateReader([{id,expanded:true,loading:false,translation:'中文排版回归测试',error:''}],false);
        const translation=document.getElementById('translation-'+id);
        if(nodes[id].innerHTML!==original)throw new Error('Original paragraph altered');
        if(nodes[id].nextElementSibling!==translation)throw new Error('Translation must follow original paragraph');
        if(tableParagraph>=0&&translation.closest('td')!==nodes[id].closest('td'))throw new Error('Translation left its table cell');
        updateReader([{id,expanded:true,loading:true,translation:'',error:'',activity:'等待 2 秒后重试 · 1/2'}],false);
        if(!translation.textContent.includes('等待 2 秒后重试'))throw new Error('Precise retry state missing');
        updateReader([{id,expanded:true,loading:false,translation:'',error:'',activity:'已暂停',paused:true}],false);
        if(!translation.querySelector('button')||!translation.textContent.includes('继续翻译'))throw new Error('Resume control missing');
        updateReader([{id,expanded:true,loading:false,translation:'已完成',error:''}],false);
        if(translation.onclick!==null)throw new Error('Completed translation retains retry action');
        updateReader([{id,expanded:false,loading:false,translation:'',error:''}],false);
        if(document.getElementById('translation-'+id))throw new Error('Collapse failed');
        if(document.querySelectorAll('table').length!==tableCount||document.querySelectorAll('img').length!==imageCount||document.querySelectorAll('math').length!==mathCount)throw new Error('Document objects lost');
        return {tables:tableCount,images:imageCount,math:mathCount,paragraphs:nodes.length,translatedInsideTable:tableParagraph>=0};
        """
        view.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .failure(let error): self.fail(error.localizedDescription)
            case .success(let value):
                print("PASS: local Word layout and inline expansion/collapse: \(String(describing: value))")
                if self.phase == 0 {
                    self.phase = 1
                    self.fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("fixtures/example.docx")
                    self.start()
                } else { print("PASS: second document renders in the same process"); exit(0) }
            }
        }
    }
    func fail(_ message: String) { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct WordChecksMain {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count > 1 else { exit(2) }
        let test = WordChecks(fixture: URL(fileURLWithPath: CommandLine.arguments[1]))
        test.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { test.fail("Word rendering timed out") }
        withExtendedLifetime(test) { NSApp.run() }
    }
}
