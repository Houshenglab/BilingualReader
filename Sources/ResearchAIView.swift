import SwiftUI
import AppKit

struct ResearchAIView: View {
    @ObservedObject var ai: ResearchAI
    let title: String
    let paragraphs: [String]
    let selectedText: String?
    let saveNote: (String) -> Void
    var onDetach: (() -> Void)? = nil
    var onDock: (() -> Void)? = nil
    @State private var settings = false
    @State private var confirmClear = false
    @State private var modelPicker = false
    @State private var contextInformation = false
    @AppStorage("researchAI.composerHeight") private var composerHeight = 64.0
    @State private var resizeStart: CGFloat?
    @State private var resizePreview: CGFloat?
    @State private var resizeHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var context: ResearchAIContext { ResearchAIContext(paragraphs: paragraphs, selectedText: selectedText, scope: ai.scope) }
    private var canSend: Bool {
        ai.configured && !ai.busy && ai.historyAvailable && !ai.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ai.question.count <= ResearchAIRequest.questionLimit && (ai.scope == .none || !context.text.isEmpty)
    }
    var body: some View {
        GeometryReader { proxy in
            let height = Self.clampedComposerHeight(resizePreview ?? composerHeight, availableHeight: proxy.size.height)
            VStack(spacing: 0) {
                toolbar
                Divider()
                conversation
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                composerResizeHandle(height: height, availableHeight: proxy.size.height)
                composer(height: height)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $settings) { ResearchAISettings(ai: ai) }
        .alert(L("清除本篇文献的 AI 对话？", "Clear this document’s AI chat?"), isPresented: $confirmClear) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("清除", "Clear"), role: .destructive) { ai.clear() }
        } message: { Text(L("仅删除本地对话记录，已保存的笔记和原始文献保留。", "Only local chat history is deleted. Saved notes and the original document are retained.")) }
    }
    static func clampedComposerHeight(_ height: Double, availableHeight: CGFloat) -> CGFloat {
        // Keep room for a substantial conversation even on the shortest panel.
        let maximum = max(48.0, min(300.0, availableHeight - 200.0))
        return min(max(48.0, height.isFinite ? CGFloat(height) : 64.0), maximum)
    }
    private var toolbar: some View {
        HStack(spacing: 6) {
            if ai.configured {
                modelButton
                    .disabled(ai.busy)
                ResearchEffortPicker(
                    efforts: ai.efforts(for: ai.model, base: ai.baseURL),
                    selected: ai.effort,
                    onSelect: { ai.selectEffort($0) }
                )
                .fixedSize(horizontal: true, vertical: false)
                .disabled(ai.busy)
            } else {
                Label(L("AI 助手", "AI assistant"), systemImage: "sparkles")
                    .font(.callout.weight(.semibold)).foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(L("配置 API", "Configure API")) { settings = true }
                    .font(.callout.weight(.medium)).buttonStyle(.borderless)
                    .accessibilityLabel(L("配置 AI API", "Configure AI API")).disabled(ai.busy)
            }
            if let onDock {
                Button(action: onDock) { Image(systemName: "rectangle.portrait.and.arrow.right").frame(width: 23, height: 26) }
                    .buttonStyle(.borderless).help(L("停靠回阅读侧栏", "Dock to reader")).accessibilityLabel(L("停靠回阅读侧栏", "Dock to reader"))
                    .accessibilityIdentifier("ai-dock-button")
            } else if let onDetach {
                Button(action: onDetach) { Image(systemName: "arrow.up.right.square").frame(width: 23, height: 26) }
                    .buttonStyle(.borderless).help(L("移到独立窗口", "Open in separate window")).accessibilityLabel(L("移到独立窗口", "Open in separate window"))
                    .accessibilityIdentifier("ai-detach-button")
            }
            Menu {
                Button { settings = true } label: { Label(L("配置 API", "Configure API"), systemImage: "slider.horizontal.3") }.disabled(ai.busy)
                Button { contextInformation = true } label: { Label(L("发送范围与隐私", "Content scope and privacy"), systemImage: "info.circle") }
                Divider()
                Button(L("清除本篇对话记录…", "Clear this chat…"), role: .destructive) { confirmClear = true }
                    .disabled(ai.busy || ai.messages.isEmpty || !ai.historyAvailable)
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 26) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(L("对话操作", "Chat actions")).accessibilityIdentifier("ai-more-actions")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
    private var modelButton: some View {
        Button { modelPicker = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "cpu").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.accentColor)
                Text(ai.model).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7).padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.09)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("切换模型", "Change model"))
        .accessibilityValue(ai.model)
        .accessibilityIdentifier("ai-model-picker")
        .help(L("选择当前 API 帐户可用的模型：\(ai.model)", "Choose a model available to your API account: \(ai.model)"))
        .popover(isPresented: $modelPicker, arrowEdge: .bottom) {
            ResearchAIModelChooser(ai: ai, base: ai.baseURL, current: ai.model, onSelect: { id in
                ai.selectModel(id)
                modelPicker = false
            }, onManual: {
                modelPicker = false
                settings = true
            })
        }
    }
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if ai.messages.isEmpty { introduction }
                    ForEach(ai.messages) { message in messageView(message) }
                    if ai.busy {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("AI 正在思考…", "AI is thinking…")).font(.callout).foregroundStyle(.secondary) }
                    }
                    if let error = ai.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                            if !ai.busy, let last = ai.messages.last, last.role == .user {
                                Button(L("再次编辑提问", "Edit question again")) { ai.question = last.text; ai.error = nil }.font(.caption).buttonStyle(.link)
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("researchAI-bottom")
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: ai.messages.count) { _ in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo("researchAI-bottom", anchor: .bottom) } }
            .onChange(of: ai.busy) { _ in proxy.scrollTo("researchAI-bottom", anchor: .bottom) }
            .onAppear { if !ai.messages.isEmpty { proxy.scrollTo("researchAI-bottom", anchor: .bottom) } }
        }
    }
    private var introduction: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 19, weight: .medium)).foregroundStyle(Color.accentColor)
            Text(L("问这篇文献", "Ask about this paper")).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(.vertical, 3)
    }
    private var promptMenu: some View {
        Menu {
            suggestion(L("概括文献要点", "Summarize the paper"), icon: "list.bullet.rectangle", prompt: L("请概括这篇文献的研究背景、目标、核心发现和意义。指出资料范围是否完整。", "Summarize the research background, goals, main findings and significance of this paper. State whether the provided material is complete."))
            suggestion(L("梳理研究方法", "Review methods"), icon: "point.3.connected.trianglepath.dotted", prompt: L("请按研究问题、数据来源、实验或分析方法、关键假设梳理这篇文献。", "Outline this paper by research question, data sources, experimental or analytical methods, and key assumptions."))
            suggestion(L("分析结论与局限", "Analyze conclusions"), icon: "text.magnifyingglass", prompt: L("请解释主要结论、证据、创新点和局限性，区分作者的结论与推断。", "Explain the main conclusions, evidence, innovations and limitations, distinguishing the authors’ conclusions from inferences."))
            suggestion(L("解释选中文字", "Explain selected text"), icon: "text.cursor", prompt: L("请用通俗语言解释选中文字的含义、专业术语及其科研背景。", "Explain the selected text, technical terms and scientific context in plain language."), selection: true)
        } label: { Image(systemName: "sparkles").frame(width: 23, height: 25) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(L("常用提问", "Suggested questions")).help(L("常用提问", "Suggested questions"))
        .accessibilityIdentifier("ai-prompt-menu")
    }
    private func suggestion(_ title: String, icon: String, prompt: String, selection: Bool = false) -> some View {
        Button {
            ai.scope = selection ? .selection : .document
            ai.question = prompt
        } label: { Label(title, systemImage: icon) }
            .disabled(selection && (selectedText?.isEmpty ?? true))
    }
    private func messageView(_ message: ResearchAIMessage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: message.role == .assistant ? "sparkles" : "person.crop.circle")
                    .font(.callout).foregroundStyle(message.role == .assistant ? Color.accentColor : Color.secondary)
                Text(message.role == .assistant ? L("AI 助手", "AI assistant") : L("你", "You")).font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                if let label = message.contextLabel {
                    Label(contextTag(label), systemImage: "doc.text")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).help(label)
                        .accessibilityLabel(label)
                }
            }
            if message.role == .assistant, let attributed = try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(message.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if message.role == .assistant {
                HStack(spacing: 12) {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) } label: { Label(L("复制", "Copy"), systemImage: "doc.on.doc") }
                    Button { saveNote(message.text) } label: { Label(L("存为笔记", "Save as note"), systemImage: "note.text") }
                }.font(.caption).buttonStyle(.borderless)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(message.role == .user ? Color.accentColor.opacity(0.075) : Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
    }
    private func composerResizeHandle(height: CGFloat, availableHeight: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color.clear)
            Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1)
            Capsule().fill(resizeHovered || resizeStart != nil ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.55))
                .frame(width: 30, height: 3)
                .padding(.horizontal, 5)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(height: 12)
        .contentShape(Rectangle())
        .onHover { hovering in
            resizeHovered = hovering
            if hovering { NSCursor.resizeUpDown.set() } else if resizeStart == nil { NSCursor.arrow.set() }
        }
        .onDisappear { if resizeHovered || resizeStart != nil { NSCursor.arrow.set() } }
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if resizeStart == nil { resizeStart = height }
                resizePreview = Self.clampedComposerHeight(Double((resizeStart ?? height) - value.translation.height), availableHeight: availableHeight)
            }
            .onEnded { value in
                composerHeight = Double(Self.clampedComposerHeight(Double((resizeStart ?? height) - value.translation.height), availableHeight: availableHeight))
                resizePreview = nil
                resizeStart = nil
                if !resizeHovered { NSCursor.arrow.set() }
            })
        .help(L("上下拖动调整输入框高度", "Drag up or down to resize the input"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("输入框高度", "Input height"))
        .accessibilityIdentifier("ai-composer-resize")
        .accessibilityValue(L("\(Int(height)) 点", "\(Int(height)) pt"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: composerHeight = Double(Self.clampedComposerHeight(Double(height + 16), availableHeight: availableHeight))
            case .decrement: composerHeight = Double(Self.clampedComposerHeight(Double(height - 16), availableHeight: availableHeight))
            @unknown default: break
            }
        }
    }
    private var scopeMenu: some View {
        Menu {
            Picker(L("资料范围", "Content scope"), selection: $ai.scope) {
                ForEach(ResearchAIScope.allCases) { scope in Text(scope.label).tag(scope) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: ai.scope == .none ? "bubble.left" : (ai.scope == .selection ? "text.cursor" : "doc.text"))
                Text(ai.scope == .none ? L("对话", "Chat") : (ai.scope == .selection ? L("选区", "Selection") : L("文献", "Document")))
                    .font(.caption.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }.padding(.horizontal, 5).frame(height: 25)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(L("本轮资料范围：\(context.label)", "Content scope: \(context.label)"))
        .accessibilityLabel(L("资料范围", "Content scope"))
        .accessibilityValue(ai.scope.label)
        .accessibilityIdentifier("ai-context-scope")
    }
    private var contextBadge: some View {
        Button { contextInformation.toggle() } label: {
            HStack(spacing: 4) {
                if !context.isComplete {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(ai.scope == .document ? L("节选·非全文", "Partial text") : L("选区节选", "Selection excerpt")).lineLimit(1)
                } else if ai.scope != .none && context.text.isEmpty {
                    Image(systemName: "exclamationmark.circle")
                    Text(ai.scope == .selection ? L("未选中", "No selection") : L("无正文", "No text")).lineLimit(1)
                } else {
                    Image(systemName: "info.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(!context.isComplete || (ai.scope != .none && context.text.isEmpty) ? Color.orange : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(context.label + L(" · 点击查看发送范围与隐私", " · View content scope and privacy"))
        .accessibilityLabel(L("发送范围与隐私", "Content scope and privacy"))
        .accessibilityValue(context.label)
        .accessibilityIdentifier("ai-context-information")
        .popover(isPresented: $contextInformation, arrowEdge: .top) { contextDetails }
    }
    private var contextDetails: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L("本轮发送范围", "Content to send")).font(.headline)
            Label(context.label, systemImage: "doc.text").font(.callout)
                .foregroundStyle(context.isComplete ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            if ai.scope == .selection, let text = selectedText, !text.isEmpty {
                Text(text).font(.caption).lineLimit(4).textSelection(.enabled)
            }
            if ai.configured, let host = (try? ResearchAIConfiguration.endpoint(ai.baseURL))?.host {
                Label(L("发送至 \(host)", "Send to \(host)"), systemImage: "network").font(.callout)
            }
            Divider()
            Text(L("提问会附带近期对话和此前选区摘录，可能产生 API 费用。仅发送提问时才提交文献内容；模型列表查询不包含文献。", "Questions include recent chat and prior selected excerpts and may incur API charges. Document content is sent only when submitting a question; model listing does not send documents."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L("AI 回答请结合原文核对。", "Check AI responses against the source.")).font(.caption).foregroundStyle(.secondary)
        }.padding(14).frame(width: 270, alignment: .leading)
    }
    private func composer(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if ai.question.isEmpty {
                    Text(L("问这篇文献…", "Ask about this paper…")).font(.callout).foregroundStyle(.secondary)
                        .padding(.top, 8).padding(.leading, 9).allowsHitTesting(false)
                }
                TextEditor(text: $ai.question).font(.system(size: 14)).scrollContentBackground(.hidden)
                    .padding(4).frame(height: height)
                    .accessibilityLabel(L("输入问题", "Enter a question")).accessibilityIdentifier("ai-question-input")
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
            HStack(spacing: 6) {
                scopeMenu
                contextBadge
                Spacer(minLength: 0)
                promptMenu
                if ai.busy {
                    Button { ai.cancel() } label: { Label(L("停止", "Stop"), systemImage: "stop.fill") }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Button { ai.send(title: title, context: context) } label: { Label(L("发送", "Send"), systemImage: "arrow.up") }
                        .buttonStyle(.borderedProminent).controlSize(.small).disabled(!canSend)
                        .help(L("发送提问", "Send question")).accessibilityIdentifier("ai-send-question")
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 9).padding(.top, 1).padding(.bottom, 8)
    }
}

// Reusable model directory: no request is made until the user opens this popover.
struct ResearchAIModelChooser: View {
    @ObservedObject var ai: ResearchAI
    let base: String
    var key = ""
    var useSavedKey = true
    var refreshOnOpen = false
    let current: String
    let onSelect: (String) -> Void
    var onManual: (() -> Void)? = nil
    @State private var query = ""
    @State private var requested = false
    @State private var refreshTask: Task<Void, Never>?
    private var models: [ResearchAIModel] { ai.models(for: base) }
    private var filtered: [ResearchAIModel] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty ? models : models.filter {
            $0.id.localizedCaseInsensitiveContains(needle) || ($0.name?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }
    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            requested = true
            await ai.loadModels(base: base, key: key, useSavedKey: useSavedKey)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("选择模型", "Select model")).font(.headline)
                    Text(models.isEmpty ? L("API 帐户模型目录", "API model catalog") : L("API 帐户模型目录 · \(models.count) 个模型", "API model catalog · \(models.count) models"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium)) }
                    .buttonStyle(.borderless).help(L("刷新模型目录", "Refresh model catalog")).accessibilityLabel(L("刷新模型目录", "Refresh model catalog"))
                    .accessibilityIdentifier("ai-model-refresh")
                    .disabled(ai.loadingModels)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("搜索模型名称或 ID", "Search model names or IDs"), text: $query).textFieldStyle(.plain)
                    .accessibilityLabel(L("搜索模型", "Search models"))
                    .accessibilityIdentifier("ai-model-search")
                    .onSubmit { if filtered.count == 1 && !ai.loadingModels { onSelect(filtered[0].id) } }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.borderless).accessibilityLabel(L("清除搜索", "Clear search"))
                }
            }
            .padding(9)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.10)))
            if ai.loadingModels {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(L("正在获取模型目录…", "Loading model catalog…")).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("停止", "Stop")) { refreshTask?.cancel(); ai.cancelModelLoading() }.buttonStyle(.borderless)
                }.padding(.vertical, 8)
            } else if let error = ai.modelsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                if !models.isEmpty {
                    Text(L("下方为此前查询的模型目录。", "Showing the previously loaded model catalog.")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !filtered.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(filtered) { item in
                            Button { onSelect(item.id) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "cpu").font(.system(size: 12)).foregroundStyle(Color.accentColor)
                                    Text(item.id).font(.system(size: 12, weight: item.id == current ? .semibold : .regular))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 3)
                                    if item.id == current { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor) }
                                }
                                .padding(.horizontal, 9).padding(.vertical, 9)
                                .background(item.id == current ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(item.id)
                            .accessibilityLabel(item.id)
                            .accessibilityIdentifier("ai-model-option-\(item.id)")
                            .accessibilityAddTraits(item.id == current ? .isSelected : [])
                        }
                    }
                }
                .frame(height: min(244, CGFloat(filtered.count) * 36 + 3))
                .disabled(ai.loadingModels)
            } else if !ai.loadingModels {
                VStack(spacing: 7) {
                    Image(systemName: models.isEmpty ? "square.stack" : "magnifyingglass")
                        .font(.system(size: 19)).foregroundStyle(.secondary)
                    Text(!query.isEmpty && !models.isEmpty ? L("没有匹配的模型", "No matching models") : (requested && ai.modelsError == nil ? L("服务未返回模型", "No models returned") : L("尚无模型目录", "No model catalog yet")))
                        .font(.callout.weight(.medium))
                    Text(models.isEmpty ? L("可刷新目录，也可直接输入已知模型 ID。", "Refresh the catalog or enter a known model ID.") : L("试试其他模型名称。", "Try another model name."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            Divider()
            if let onManual {
                Button(action: onManual) { Label(L("手动输入模型 ID…", "Enter model ID manually…"), systemImage: "pencil") }
                    .buttonStyle(.borderless).font(.callout)
            }
            Text(L("目录可能包含不支持对话的模型，请选择兼容 Chat Completions 的模型。查询目录不发送文献内容。", "The catalog may include non-chat models. Choose a Chat Completions-compatible model. Listing models does not send documents."))
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(15).frame(width: 322)
        .accessibilityIdentifier("ai-model-directory")
        .task {
            if refreshOnOpen || models.isEmpty {
                requested = true
                await ai.loadModels(base: base, key: key, useSavedKey: useSavedKey)
            }
        }
        .onDisappear { refreshTask?.cancel(); ai.cancelModelLoading() }
    }
}

// The meter describes the selected reasoning setting, not progress of an API call.
private struct ResearchEffortMeter: View {
    let effort: ResearchReasoningEffort
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var level: Int { max(0, min(5, effort.level)) }
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<5) { index in
                Capsule()
                    .fill(index < level ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(width: 3, height: CGFloat(5 + index * 3))
                    .scaleEffect(x: 1, y: index < level ? 1 : 0.72, anchor: .bottom)
            }
        }
        .frame(height: 17, alignment: .bottom)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.79), value: effort)
        .accessibilityHidden(true)
    }
}

struct ResearchEffortPicker: View {
    let efforts: [ResearchReasoningEffort]
    let selected: ResearchReasoningEffort
    let onSelect: (ResearchReasoningEffort) -> Void
    @State private var showOptions = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var value: ResearchReasoningEffort { efforts.contains(selected) ? selected : .automatic }
    var body: some View {
        Button { showOptions = true } label: {
            HStack(spacing: 6) {
                ResearchEffortMeter(effort: value)
                Text(efforts.count <= 1 ? L("服务默认", "Default") : value.label).font(.caption.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.16)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("推理强度", "Reasoning"))
        .accessibilityValue(efforts.count <= 1 ? L("服务默认", "Default") : value.label)
        .accessibilityIdentifier("ai-effort-picker")
        .help(L("选择推理强度：\(value.label)", "Choose reasoning effort: \(value.label)"))
        .popover(isPresented: $showOptions, arrowEdge: .bottom) {
            ResearchEffortOptions(efforts: efforts, selected: value, onSelect: { item in
                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.80)) { onSelect(item) }
                showOptions = false
            })
        }
    }
}

struct ResearchEffortOptions: View {
    let efforts: [ResearchReasoningEffort]
    let selected: ResearchReasoningEffort
    let onSelect: (ResearchReasoningEffort) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ResearchEffortMeter(effort: selected)
                    .padding(9).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("推理强度", "Reasoning")).font(.headline)
                    Text(L("当前 · ", "Current · ") + (efforts.count <= 1 ? L("服务默认", "Default") : selected.label)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if efforts.count <= 1 {
                Text(L("此服务或模型没有已确认的可调推理档位，将使用服务默认设置。", "This service or model has no confirmed reasoning options. Default settings will apply."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("较高强度可能需要更多时间和 API 额度。", "Higher effort may take longer and use more API credits."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(efforts) { item in
                            Button { onSelect(item) } label: {
                                HStack(alignment: .center, spacing: 11) {
                                    ResearchEffortMeter(effort: item)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.label).font(.callout.weight(item == selected ? .semibold : .medium))
                                        Text(item.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 4)
                                    if item == selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 9)
                                .background(item == selected ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.label)
                            .accessibilityHint(item.detail)
                            .accessibilityIdentifier("ai-effort-option-\(item.rawValue)")
                            .accessibilityAddTraits(item == selected ? .isSelected : [])
                        }
                    }
                }
                .frame(height: min(CGFloat(efforts.count) * 55 + 5, 340))
            }
        }
        .padding(15).frame(width: 286)
        .accessibilityIdentifier("ai-effort-options")
    }
}

struct ResearchAISettings: View {
    @ObservedObject var ai: ResearchAI
    @Environment(\.dismiss) private var dismiss
    @State private var base = ""
    @State private var model = ""
    @State private var key = ""
    @State private var effort: ResearchReasoningEffort = .automatic
    @State private var removeKey = false
    @State private var error: String?
    @State private var hasKey = false
    @State private var previousEndpoint: URL?
    @State private var modelPicker = false
    @State private var saved = false
    @FocusState private var focusedModel: Bool
    private var validBase: Bool { (try? ResearchAIConfiguration.endpoint(base)) != nil }
    private var modelOptions: [ResearchReasoningEffort] { ai.efforts(for: model, base: base) }
    private func refreshSavedKey() { hasKey = ai.hasSavedCredential(base: base) }
    private func invalidateModelLoading() {
        modelPicker = false
        ai.cancelModelLoading()
    }
    private func clampEffort() {
        if !modelOptions.contains(effort) { effort = .automatic }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("设置 AI 助手", "AI assistant settings")).font(.title2.bold())
                    Text(L("接入兼容 Chat Completions 的 AI 服务", "Connect a Chat Completions-compatible AI service")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("API 地址", "API URL")).font(.callout.weight(.semibold))
                        TextField("https://api.openai.com/v1", text: $base).textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L("API 地址", "API URL"))
                        Text(L("填写服务商提供的接口地址（含版本路径，例如 /v1）。本机模型可使用 localhost 的 HTTP 地址。", "Enter the provider’s API URL, including its version path (e.g. /v1). Local models can use HTTP on localhost."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("API 密钥", "API key")).font(.callout.weight(.semibold))
                        SecureField(hasKey ? L("已保存密钥，留空保留", "Key saved; leave blank to keep") : L("密钥（按服务要求填写）", "API key (if required)"), text: $key)
                            .textFieldStyle(.roundedBorder).disabled(removeKey).accessibilityLabel(L("API 密钥", "API key"))
                        Toggle(L("移除此地址保存的密钥", "Remove the key for this URL"), isOn: $removeKey).font(.caption).disabled(!hasKey)
                        Text(L("密钥存入 macOS 钥匙串，与接口地址绑定。更换接口地址后需要重新填写密钥。", "Keys are stored in macOS Keychain and linked to the API URL. Enter the key again when changing the URL."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("模型名称", "Model name")).font(.callout.weight(.semibold))
                            Spacer()
                            Button { modelPicker = true } label: {
                                Label(ai.models(for: base).isEmpty ? L("获取模型", "Load models") : L("选择模型（\(ai.models(for: base).count)）", "Choose model (\(ai.models(for: base).count))"), systemImage: "list.bullet")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!validBase)
                            .accessibilityIdentifier("ai-settings-model-list")
                            .popover(isPresented: $modelPicker, arrowEdge: .bottom) {
                                ResearchAIModelChooser(ai: ai, base: base, key: key, useSavedKey: !removeKey, refreshOnOpen: true, current: model, onSelect: { id in
                                    model = id
                                    clampEffort()
                                    modelPicker = false
                                }, onManual: {
                                    modelPicker = false
                                    focusedModel = true
                                })
                            }
                        }
                        TextField(L("从列表选择，或输入模型 ID", "Choose from list or enter model ID"), text: $model).textFieldStyle(.roundedBorder)
                            .focused($focusedModel)
                            .accessibilityLabel(L("模型 ID", "Model ID"))
                            .accessibilityIdentifier("ai-settings-model-id")
                        Text(L("获取模型后可搜索并选择。如果服务未提供模型目录，仍可手动输入 ID。", "Search and select from loaded models. If the provider has no catalog, enter a model ID manually."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if validBase && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L("推理强度", "Reasoning")).font(.callout.weight(.semibold))
                                    Text(modelOptions.count <= 1 ? L("使用服务默认设置", "Use default settings") : L("按任务选择思考深度", "Choose reasoning depth for the task"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                ResearchEffortPicker(efforts: modelOptions, selected: effort, onSelect: { effort = $0 })
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Label(L("获取模型目录时只会验证接口和密钥。文献内容仅在发送提问时交给所选服务商，API 费用由你的账户承担。", "Model catalog requests only verify the API and key. Document content is sent to the selected service only when you submit a question. API charges apply to your account."), systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(22)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Spacer()
                    Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(L("保存设置", "Save settings")) {
                        do {
                            try ai.configure(base: base, model: model, key: key, removeKey: removeKey, effort: effort)
                            saved = true
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!validBase || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ai.busy)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 506, height: 535)
        .onAppear {
            previousEndpoint = try? ResearchAIConfiguration.endpoint(ai.baseURL)
            base = ai.baseURL; model = ai.model; effort = ai.effort
            refreshSavedKey(); clampEffort()
        }
        .onChange(of: base) { _ in
            let endpoint = try? ResearchAIConfiguration.endpoint(base)
            guard endpoint != previousEndpoint else { return }
            // Discard any catalogue obtained with an unsaved credential before changing its address.
            if let previousEndpoint, !key.isEmpty || removeKey { ai.invalidateModels(for: previousEndpoint.absoluteString) }
            previousEndpoint = endpoint
            invalidateModelLoading()
            key = ""; removeKey = false; effort = .automatic
            refreshSavedKey()
        }
        .onChange(of: key) { _ in
            modelPicker = false
            ai.invalidateModels(for: base)
        }
        .onChange(of: removeKey) { removing in
            if removing { key = "" }
            modelPicker = false
            ai.invalidateModels(for: base)
        }
        .onChange(of: model) { _ in clampEffort() }
        .onDisappear {
            if !saved && (!key.isEmpty || removeKey) { ai.invalidateModels(for: base) }
            else { ai.cancelModelLoading() }
        }
    }
}

/// Existing chats may contain scope descriptions saved in either interface language.
private func contextTag(_ label: String) -> String {
    let value = label.lowercased()
    if value.contains("摘录") || value.contains("excerpt") || value.contains("partial") {
        return L("节选", "Excerpt")
    }
    if value.contains("选中") || value.contains("selected") || value.contains("selection") {
        return L("选区", "Selection")
    }
    if value.contains("全文") || value.contains("full text") {
        return L("全文", "Full text")
    }
    return L("对话", "Chat")
}
