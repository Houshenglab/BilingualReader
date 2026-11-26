import SwiftUI
import AppKit

struct ResearchAIView: View {
    @ObservedObject var ai: ResearchAI
    let title: String
    let paragraphs: [String]
    let selectedText: String?
    let saveNote: (String) -> Void
    @State private var settings = false
    @State private var confirmClear = false
    @State private var modelPicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var context: ResearchAIContext { ResearchAIContext(paragraphs: paragraphs, selectedText: selectedText, scope: ai.scope) }
    private var canSend: Bool {
        ai.configured && !ai.busy && ai.historyAvailable && !ai.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ai.question.count <= ResearchAIRequest.questionLimit && (ai.scope == .none || !context.text.isEmpty)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI 文献助手").font(.headline)
                    Text(ai.configured ? "文献问答" : "尚未设置模型").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Button { settings = true } label: { if ai.configured { Image(systemName: "slider.horizontal.3").frame(width: 24, height: 24) } else { Label("配置 API", systemImage: "slider.horizontal.3").font(.caption.weight(.medium)) } }
                    .buttonStyle(.borderless).help("配置 AI API").accessibilityLabel("配置 AI API").disabled(ai.busy)
                Menu {
                    Button("清除本篇对话记录…", role: .destructive) { confirmClear = true }
                        .disabled(ai.busy || ai.messages.isEmpty || !ai.historyAvailable)
                } label: { Image(systemName: "ellipsis.circle").frame(width: 22, height: 22) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("对话操作")
            }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, ai.configured ? 8 : 12)
            if ai.configured { modelControls }
            Divider()
            conversation
            Divider()
            composer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $settings) { ResearchAISettings(ai: ai) }
        .alert("清除本篇文献的 AI 对话？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { ai.clear() }
        } message: { Text("仅删除本地对话记录，已保存的笔记和原始文献保留。") }
    }
    private var modelControls: some View {
        HStack(spacing: 8) {
            Button { modelPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cpu").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.accentColor)
                    Text(ai.model).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.09)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换模型")
            .accessibilityValue(ai.model)
            .accessibilityIdentifier("ai-model-picker")
            .help("选择当前 API 帐户可用的模型：\(ai.model)")
            .popover(isPresented: $modelPicker, arrowEdge: .bottom) {
                ResearchAIModelChooser(ai: ai, base: ai.baseURL, current: ai.model, onSelect: { id in
                    ai.selectModel(id)
                    modelPicker = false
                }, onManual: {
                    modelPicker = false
                    settings = true
                })
            }
            ResearchEffortPicker(
                efforts: ai.efforts(for: ai.model, base: ai.baseURL),
                selected: ai.effort,
                onSelect: { ai.selectEffort($0) }
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .disabled(ai.busy)
        .padding(.horizontal, 14).padding(.bottom, 12)
    }
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if ai.messages.isEmpty { introduction }
                    ForEach(ai.messages) { message in messageView(message) }
                    if ai.busy {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("AI 正在思考…").font(.callout).foregroundStyle(.secondary) }
                    }
                    if let error = ai.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                            if !ai.busy, let last = ai.messages.last, last.role == .user {
                                Button("再次编辑提问") { ai.question = last.text; ai.error = nil }.font(.caption).buttonStyle(.link)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 20, weight: .medium)).foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                Text("读懂这篇文献").font(.system(size: 18, weight: .semibold))
            }
            Text("梳理研究目标、方法与核心结果，或围绕原文继续提问。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 7) {
                suggestion("概括文献要点", icon: "list.bullet.rectangle", prompt: "请概括这篇文献的研究背景、目标、核心发现和意义。指出资料范围是否完整。")
                suggestion("梳理研究方法", icon: "point.3.connected.trianglepath.dotted", prompt: "请按研究问题、数据来源、实验或分析方法、关键假设梳理这篇文献。")
                suggestion("分析结论与局限", icon: "text.magnifyingglass", prompt: "请解释主要结论、证据、创新点和局限性，区分作者的结论与推断。")
                suggestion("解释选中文字", icon: "text.cursor", prompt: "请用通俗语言解释选中文字的含义、专业术语及其科研背景。", selection: true)
            }
        }.padding(.top, 6)
    }
    private func suggestion(_ title: String, icon: String, prompt: String, selection: Bool = false) -> some View {
        Button {
            ai.scope = selection ? .selection : .document
            ai.question = prompt
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 20)
                Text(title).font(.callout).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        }.buttonStyle(.plain).disabled(selection && (selectedText?.isEmpty ?? true))
    }
    private func messageView(_ message: ResearchAIMessage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: message.role == .assistant ? "sparkles" : "person.crop.circle")
                    .font(.callout).foregroundStyle(message.role == .assistant ? Color.accentColor : Color.secondary)
                Text(message.role == .assistant ? "AI 助手" : "你").font(.caption.weight(.semibold))
                Spacer()
            }
            if let label = message.contextLabel { Text(label).font(.caption2).foregroundStyle(.secondary) }
            if message.role == .assistant, let attributed = try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(message.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if message.role == .assistant {
                HStack(spacing: 12) {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) } label: { Label("复制", systemImage: "doc.on.doc") }
                    Button { saveNote(message.text) } label: { Label("存为笔记", systemImage: "note.text") }
                }.font(.caption).buttonStyle(.borderless)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(message.role == .user ? Color.accentColor.opacity(0.075) : Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker("资料范围", selection: $ai.scope) {
                ForEach(ResearchAIScope.allCases) { scope in Text(scope.rawValue).tag(scope) }
            }.pickerStyle(.segmented).labelsHidden()
            Label(context.label, systemImage: context.isComplete ? "doc.text" : "doc.text.magnifyingglass")
                .font(.caption).foregroundStyle(context.isComplete ? Color.secondary : Color.orange).fixedSize(horizontal: false, vertical: true)
            if ai.scope == .selection, let text = selectedText, !text.isEmpty {
                Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(3).padding(.leading, 9)
                    .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor.opacity(0.55)).frame(width: 2) }
            }
            ZStack(alignment: .topLeading) {
                if ai.question.isEmpty {
                    Text("关于这篇文章，你想了解什么？").font(.callout).foregroundStyle(.secondary).padding(.top, 10).padding(.leading, 9).allowsHitTesting(false)
                }
                TextEditor(text: $ai.question).font(.system(size: 14)).scrollContentBackground(.hidden).padding(5).frame(height: 76)
                    .accessibilityLabel("输入问题")
            }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.12)))
            HStack {
                if ai.configured, let host = (try? ResearchAIConfiguration.endpoint(ai.baseURL))?.host {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("发送至 \(host)").font(.caption2).lineLimit(1)
                        Text("附带本轮问题、近期对话和此前选区摘录；可能产生 API 费用。")
                            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } else { Text("配置 API 后即可发送").font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                if ai.busy {
                    Button { ai.cancel() } label: { Label("停止", systemImage: "stop.fill") }.buttonStyle(.bordered)
                } else {
                    Button { ai.send(title: title, context: context) } label: { Label("发送", systemImage: "arrow.up.circle.fill") }
                        .buttonStyle(.borderedProminent).disabled(!canSend)
                }
            }
            Text("只有发送提问时才提交文献内容。模型列表查询不包含文献。AI 回答请结合原文核对。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(12)
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
                    Text("选择模型").font(.headline)
                    Text(models.isEmpty ? "API 帐户模型目录" : "API 帐户模型目录 · \(models.count) 个模型")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium)) }
                    .buttonStyle(.borderless).help("刷新模型目录").accessibilityLabel("刷新模型目录")
                    .accessibilityIdentifier("ai-model-refresh")
                    .disabled(ai.loadingModels)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索模型名称或 ID", text: $query).textFieldStyle(.plain)
                    .accessibilityLabel("搜索模型")
                    .accessibilityIdentifier("ai-model-search")
                    .onSubmit { if filtered.count == 1 && !ai.loadingModels { onSelect(filtered[0].id) } }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.borderless).accessibilityLabel("清除搜索")
                }
            }
            .padding(9)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.10)))
            if ai.loadingModels {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("正在获取模型目录…").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("停止") { refreshTask?.cancel(); ai.cancelModelLoading() }.buttonStyle(.borderless)
                }.padding(.vertical, 8)
            } else if let error = ai.modelsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                if !models.isEmpty {
                    Text("下方为此前查询的模型目录。").font(.caption2).foregroundStyle(.secondary)
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
                    Text(!query.isEmpty && !models.isEmpty ? "没有匹配的模型" : (requested && ai.modelsError == nil ? "服务未返回模型" : "尚无模型目录"))
                        .font(.callout.weight(.medium))
                    Text(models.isEmpty ? "可刷新目录，也可直接输入已知模型 ID。" : "试试其他模型名称。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            Divider()
            if let onManual {
                Button(action: onManual) { Label("手动输入模型 ID…", systemImage: "pencil") }
                    .buttonStyle(.borderless).font(.callout)
            }
            Text("目录可能包含不支持对话的模型，请选择兼容 Chat Completions 的模型。查询目录不发送文献内容。")
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
                Text(efforts.count <= 1 ? "服务默认" : value.label).font(.caption.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.16)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("推理强度")
        .accessibilityValue(efforts.count <= 1 ? "服务默认" : value.label)
        .accessibilityIdentifier("ai-effort-picker")
        .help("选择推理强度：\(value.label)")
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
                    Text("推理强度").font(.headline)
                    Text("当前 · \(efforts.count <= 1 ? "服务默认" : selected.label)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if efforts.count <= 1 {
                Text("此服务或模型没有已确认的可调推理档位，将使用服务默认设置。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("较高强度可能需要更多时间和 API 额度。")
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
                    Text("设置 AI 助手").font(.title2.bold())
                    Text("接入兼容 Chat Completions 的 AI 服务").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API 地址").font(.callout.weight(.semibold))
                        TextField("https://api.openai.com/v1", text: $base).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("API 地址")
                        Text("填写服务商提供的接口地址（含版本路径，例如 /v1）。本机模型可使用 localhost 的 HTTP 地址。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API 密钥").font(.callout.weight(.semibold))
                        SecureField(hasKey ? "已保存密钥，留空保留" : "密钥（按服务要求填写）", text: $key)
                            .textFieldStyle(.roundedBorder).disabled(removeKey).accessibilityLabel("API 密钥")
                        Toggle("移除此地址保存的密钥", isOn: $removeKey).font(.caption).disabled(!hasKey)
                        Text("密钥存入 macOS 钥匙串，与接口地址绑定。更换接口地址后需要重新填写密钥。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("模型名称").font(.callout.weight(.semibold))
                            Spacer()
                            Button { modelPicker = true } label: {
                                Label(ai.models(for: base).isEmpty ? "获取模型" : "选择模型（\(ai.models(for: base).count)）", systemImage: "list.bullet")
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
                        TextField("从列表选择，或输入模型 ID", text: $model).textFieldStyle(.roundedBorder)
                            .focused($focusedModel)
                            .accessibilityLabel("模型 ID")
                            .accessibilityIdentifier("ai-settings-model-id")
                        Text("获取模型后可搜索并选择。如果服务未提供模型目录，仍可手动输入 ID。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if validBase && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("推理强度").font(.callout.weight(.semibold))
                                    Text(modelOptions.count <= 1 ? "使用服务默认设置" : "按任务选择思考深度")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                ResearchEffortPicker(efforts: modelOptions, selected: effort, onSelect: { effort = $0 })
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Label("获取模型目录时只会验证接口和密钥。文献内容仅在发送提问时交给所选服务商，API 费用由你的账户承担。", systemImage: "lock.shield")
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
                    Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("保存设置") {
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
