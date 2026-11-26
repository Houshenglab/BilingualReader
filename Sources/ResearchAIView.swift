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
                    Text(ai.configured ? ai.model : "尚未设置模型").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Button { settings = true } label: { if ai.configured { Image(systemName: "slider.horizontal.3").frame(width: 24, height: 24) } else { Label("配置 API", systemImage: "slider.horizontal.3").font(.caption.weight(.medium)) } }
                    .buttonStyle(.borderless).help("配置 AI API").accessibilityLabel("配置 AI API")
                Menu {
                    Button("清除本篇对话记录…", role: .destructive) { confirmClear = true }
                        .disabled(ai.busy || ai.messages.isEmpty || !ai.historyAvailable)
                } label: { Image(systemName: "ellipsis.circle").frame(width: 22, height: 22) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("对话操作")
            }.padding(.horizontal, 14).padding(.vertical, 12)
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
            .onChange(of: ai.messages.count) { _ in withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("researchAI-bottom", anchor: .bottom) } }
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
            Text("点击发送才会联网，阅读和笔记仍在本机。AI 回答请结合原文核对。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(12)
    }
}

struct ResearchAISettings: View {
    @ObservedObject var ai: ResearchAI
    @Environment(\.dismiss) private var dismiss
    @State private var base = ""
    @State private var model = ""
    @State private var key = ""
    @State private var removeKey = false
    @State private var error: String?
    @State private var hasKey = false
    private func refreshSavedKey() {
        hasKey = (try? ResearchAIConfiguration.endpoint(base)).flatMap { ResearchAICredentials.read($0) } != nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置 AI 助手").font(.title2.bold())
                    Text("接入兼容 Chat Completions 的 AI 服务").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("API 地址").font(.callout.weight(.semibold))
                TextField("https://你的服务地址/v1", text: $base).textFieldStyle(.roundedBorder)
                Text("填写服务商提供的地址（含版本路径，例如 /v1）。本机模型可使用 localhost 的 HTTP 地址。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("模型名称").font(.callout.weight(.semibold))
                TextField("服务商提供的模型 ID", text: $model).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("API 密钥").font(.callout.weight(.semibold))
                SecureField(hasKey ? "已保存密钥，留空保留" : "密钥（按服务要求填写）", text: $key).textFieldStyle(.roundedBorder).disabled(removeKey)
                Toggle("移除此地址保存的密钥", isOn: $removeKey).font(.caption).disabled(!hasKey)
                Text("密钥存入 macOS 钥匙串，与接口地址绑定；换服务地址时不会沿用其他服务的密钥。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Label("文献资料和近期对话仅在点击发送时交给你选择的服务商，API 费用由你的账户承担。", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存设置") {
                    do { try ai.configure(base: base, model: model, key: key, removeKey: removeKey); key = ""; dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 470)
            .onAppear { base = ai.baseURL; model = ai.model; refreshSavedKey() }
            .onChange(of: base) { _ in removeKey = false; refreshSavedKey() }
    }
}
