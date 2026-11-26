import SwiftUI

// The same controls are available for PDF, Word, and reflowed text.
struct ResearchSelectionBar: View {
    @ObservedObject var notebook: ResearchNotebook
    let showNotes: () -> Void
    let askAI: () -> Void
    var body: some View {
        if let selection = notebook.selection {
            HStack(spacing: 12) {
                Image(systemName: "text.cursor").foregroundStyle(Color.accentColor)
                Text(selection.quote).font(.callout).lineLimit(1).truncationMode(.tail)
                    .help(selection.quote).frame(maxWidth: .infinity, alignment: .leading)
                Divider().frame(height: 20)
                ForEach(ResearchColor.allCases) { color in
                    Button { if !notebook.highlight(color) { showNotes() } } label: {
                        Circle().fill(color.color).frame(width: 19, height: 19)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                            .padding(5).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("\(color.label)高亮").accessibilityLabel("\(color.label)高亮")
                }
                Button { notebook.requestComment(); showNotes() } label: { Label("批注", systemImage: "bubble.left") }
                Button(action: askAI) { Label("问 AI", systemImage: "sparkles") }.buttonStyle(.borderedProminent)
                Button { notebook.selection = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("关闭选中文字工具栏").accessibilityLabel("关闭选中文字工具栏")
            }.font(.callout).padding(.horizontal, 18).frame(height: 47)
                .background(Color.accentColor.opacity(0.07))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "highlighter").foregroundStyle(Color.accentColor)
                Text("选中原文即可高亮、批注或问 AI").foregroundStyle(.secondary)
                Spacer()
            }.font(.callout).padding(.horizontal, 18).frame(height: 47)
                .background(Color.accentColor.opacity(0.035))
        }
    }
}
