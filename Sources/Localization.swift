import Foundation

/// The language is selected once per launch so existing document views and in-flight operations stay coherent.
enum ReaderLanguage: String, CaseIterable, Identifiable {
    case system, english, chinese
    static let preferenceKey = "reader.interfaceLanguage"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return L("跟随系统", "System default")
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
    static let active: ReaderLanguage = {
        // Explicit override also allows the same executable to be visually verified in both languages.
        let override = ProcessInfo.processInfo.environment["BILINGUALREADER_LANGUAGE"].flatMap(Self.init(rawValue:))
        let choice = override ?? UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .system
        if choice != .system { return choice }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english
    }()
    static var locale: Locale { Locale(identifier: active == .chinese ? "zh-Hans" : "en") }
    static var htmlLanguage: String { active == .chinese ? "zh-CN" : "en" }
}

@inline(__always) func L(_ chinese: String, _ english: String) -> String {
    ReaderLanguage.active == .chinese ? chinese : english
}

/// Compatibility for stable on-disk status/engine values from earlier versions.
func LStatus(_ raw: String) -> String {
    guard ReaderLanguage.active == .english else { return raw }
    switch raw {
    case "等待翻译…": return "Waiting for translation…"
    case "已暂停 · 等待继续": return "Paused · waiting to resume"
    case "正在翻译…": return "Translating…"
    case "正在连接必应…": return "Connecting to Bing…"
    case "必应 · 免密钥": return "Bing · No API key"
    case "Google · 免密钥": return "Google · No API key"
    case "微软官方 · F0 免费档": return "Microsoft Translator · Free F0 tier"
    case "原页模式": return "Original pages"
    case "段落对照": return "Paragraph view"
    case "双语阅读": return "BilingualReader"
    case "全部": return "All"
    case "未分类": return "Uncategorized"
    default: return raw
    }
}
