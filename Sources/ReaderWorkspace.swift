import SwiftUI
import AppKit

/// An explicit, generous handle keeps resizing usable even next to PDFKit and WKWebView.
struct ReaderResizableSplit<Main: View, Side: View>: View {
    let presented: Bool
    @Binding var preferredWidth: Double
    @ViewBuilder let main: () -> Main
    @ViewBuilder let side: () -> Side
    @State private var dragStart: CGFloat?
    @State private var dragWidth: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let size = ReaderPaneGeometry(total: width, preferred: dragWidth ?? preferredWidth)
            HStack(spacing: 0) {
                main().frame(width: presented ? size.main : width, height: proxy.size.height)
                if presented {
                    ZStack {
                        Color(nsColor: .windowBackgroundColor)
                        Rectangle().fill(Color.primary.opacity(hovering || dragStart != nil ? 0.07 : 0.025))
                        Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                        RoundedRectangle(cornerRadius: 2).fill(hovering || dragStart != nil ? Color.accentColor : Color.secondary.opacity(0.50)).frame(width: 3, height: 32)
                    }
                    .frame(width: ReaderPaneGeometry.handleWidth, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            if dragStart == nil { dragStart = size.side }
                            let proposed = Double((dragStart ?? size.side) - value.translation.width)
                            dragWidth = Double(ReaderPaneGeometry(total: width, preferred: proposed).side)
                        }
                        .onEnded { _ in
                            if let dragWidth { preferredWidth = dragWidth }
                            dragWidth = nil; dragStart = nil
                        })
                    .onHover { active in hovering = active; if active { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
                    .onDisappear { if hovering { NSCursor.arrow.set() }; hovering = false; dragStart = nil; dragWidth = nil }
                    .help("左右拖动调整侧栏宽度")
                    .accessibilityLabel("调整侧栏宽度")
                    .accessibilityValue("\(Int(size.side))")
                    .accessibilityIdentifier("reader-pane-divider")
                    .accessibilityAdjustableAction { direction in
                        let change: Double = direction == .increment ? 40 : -40
                        preferredWidth = Double(ReaderPaneGeometry(total: width, preferred: Double(size.side) + change).side)
                    }
                    side().frame(width: size.side, height: proxy.size.height)
                }
            }.frame(width: width, height: proxy.size.height, alignment: .leading)
        }
    }
}

/// The detached chat uses the very same ReaderModel and ResearchAI instance, so no draft or history is copied.
@MainActor final class FloatingResearchAIController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var active = false
    private var window: NSWindow?
    private var returnToSidebar: (() -> Void)?
    private weak var dockWindow: NSWindow?
    func present(model: ReaderModel, onDock: @escaping () -> Void) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        returnToSidebar = onDock
        dockWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 455, height: 680), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "AI 文献助手"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 320, height: 360)
        window.contentView = NSHostingView(rootView: FloatingResearchAIContent(model: model, dock: { [weak self] in self?.dock() }))
        if !window.setFrameUsingName("BilingualReader.FloatingAI") { window.center() }
        window.setFrameAutosaveName("BilingualReader.FloatingAI")
        self.window = window; active = true
        window.makeKeyAndOrderFront(nil)
    }
    func bringForward() { window?.makeKeyAndOrderFront(nil) }
    func close() { window?.close() }
    func dock() {
        let action = returnToSidebar
        let main = dockWindow
        close()
        action?()
        if let main { if main.isMiniaturized { main.deminiaturize(nil) }; main.makeKeyAndOrderFront(nil) }
    }
    func windowWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSWindow, closing === window {
            closing.delegate = nil
            window = nil; active = false; returnToSidebar = nil; dockWindow = nil
        }
    }
}

private struct FloatingResearchAIContent: View {
    @ObservedObject var model: ReaderModel
    let dock: () -> Void
    var body: some View {
        if model.importing || model.documentURL == nil || model.showingLibrary && model.library != nil {
            VStack(spacing: 12) { ProgressView().controlSize(.small); Text("正在准备文献…").foregroundStyle(.secondary) }.frame(minWidth: 300, maxWidth: .infinity, minHeight: 330, maxHeight: .infinity)
        } else {
        ResearchAIView(ai: model.researchAI, title: model.documentTitle, paragraphs: model.paragraphs.map(\.text), selectedText: model.notebook.selection?.quote, saveNote: { answer in
            if model.notebook.addNote(text: answer) { model.status = "AI 回答已保存为文献笔记" }
            else { model.alert = model.notebook.error ?? "笔记保存失败" }
        }, onDock: dock)
        .frame(minWidth: 300, minHeight: 330)
        .tint(ReaderBrand.accent).accentColor(ReaderBrand.accent)
        }
    }
}
