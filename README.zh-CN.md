# BilingualReader · 双语阅读

[English](README.md) | 简体中文

0.9.0 支持在设置中选择 English、简体中文或跟随系统，重新打开软件后生效。

**面向科研文献阅读的 macOS 双语阅读器，支持 PDF、Word（DOCX）和 TXT。**

把英文论文、研究报告和笔记整理到分类书架中，在阅读原文时展开中文译文。支持整段与全文翻译，自动保存阅读位置及已完成译文。0.8.0 新增高亮批注、文献笔记和可配置 AI 助手。

[下载最新版](https://github.com/Houshenglab/BilingualReader/releases/latest) · [版本记录](CHANGELOG.md) · [第三方许可](THIRD-PARTY-NOTICES.md)

## 主要功能

| 文献阅读场景 | 功能 |
| --- | --- |
| 阅读 PDF 论文 | 保留原页中的图表、公式与排版，点击英文段落，在侧栏查看中文；可切换段落对照。 |
| 阅读 Word 资料 | 支持 DOCX 段内翻译，中文显示在原段落下方，保留表格、图片和公式。 |
| 整理多份文献 | 分类书架、封面网格、书名搜索、批量导入与批量归类。 |
| 连续阅读 | 自动恢复页码、段落位置、阅读模式、字号和已完成译文。 |
| 文献笔记 | 划选原文、多色高亮、段落评论、笔记搜索、跳转原文和 Markdown 导出。 |
| AI 文献助手 | 自定义兼容 API、全文文字或选区对话、研究方法和结论梳理、将回答保存为笔记。 |
| 按需翻译 | 支持单段及全文翻译、暂停与继续、本机译文缓存和中英对照 HTML 导出。 |

## 下载与安装

1. [下载 macOS 安装包](https://github.com/Houshenglab/BilingualReader/releases/download/v0.9.0/BilingualReader-0.9.0-macOS-arm64.zip)，或前往 [Releases](https://github.com/Houshenglab/BilingualReader/releases/latest) 查看版本。
2. 解压，将 `BilingualReader.app` 拖到「应用程序」，然后打开。
3. 点击「导入文档」，或拖入 PDF、DOCX、UTF-8 TXT 文件，开始整理和阅读。

支持 **Apple Silicon（M 系列芯片）和 macOS 13 及以上**。目前未提供 Intel 版。
应用使用本地临时签名，尚未经过 Apple 公证。确认来自本仓库后，可通过 macOS「系统设置 → 隐私与安全性」允许打开。下载页提供 SHA-256 校验文件。

## 本机书架（0.7.2）

- 启动进入「我的书架」，可在立体封面与网格之间切换，并按文档名搜索。
- 批量导入 PDF、DOCX、TXT，或将多份文件拖入窗口。相同内容自动去重。
- PDF 使用首页封面，Word/TXT 使用标题封面；点击两侧封面或左右滑动切换，点击中间封面开始阅读。
- 自动保存 PDF 页码、段落位置、字号、阅读模式及已完成译文。返回书架后可换一本继续读。
- 文档副本和记录保存在 `~/Library/Application Support/BilingualReader/Library`，原文件移动后仍可打开副本。
- 右键封面选择「从书架移除」仅删除应用管理的副本与该文档记录，不删除原文件。
- 清理翻译缓存也会清除书库保存的译文；已导入的文档和阅读位置保留。
- 顶部分类栏支持「全部」「未分类」和自定义分类；点击文件夹加号新建分类，右键分类可重命名或删除。
- 右键封面选择「移动到分类」，或用「批量归类」选择多份文档。每份文档归入一个分类。
- 在某个分类中导入会自动归入该分类；在「全部」「未分类」重复导入时保留已有分类。
- 删除分类会把文档移回「未分类」，不会删除文档、译文或阅读记录。分类与书名搜索可同时筛选。
- 触控板双指左右滑动可翻书架。PDF 导入后先显示原页，后台准备段落并缓存结果。
- 动画遵循系统「减少动态效果」设置。

## 阅读与翻译

- **PDF 原页阅读**：点击文字段落，高亮原文并在右侧阅读译文。
- **PDF 段落对照**：按英文段落与中文阅读，支持返回原页、合并相邻段落和撤销。
- **Word 段内翻译**：点击英文段落展开或收起中文；表格内译文留在原单元格中。
- **全文翻译**：翻译任务排队执行，可暂停、继续；优先处理点击的等待段落。
- **超时恢复**：临时故障有限重试；限流或服务认证失败时暂停并保留待翻译任务。
- **缓存与导出**：已完成译文在本机缓存；「阅读」菜单可导出包含原文和已完成译文的 HTML。

## 高亮、批注与 AI（0.8.0）

- 划选原文，使用阅读区上方的工具栏选择黄色、绿色、蓝色或粉色高亮，或添加批注；点击批注标记可回看内容。
- 打开「笔记」查看、编辑和搜索本篇文献的记录，点击「回到原文」定位；可添加独立笔记并导出 Markdown。原文件不被写入。
- 打开「AI 助手」并设置自己的兼容 Chat Completions API：地址（如服务商提供的 `/v1`）、模型名称、API 密钥。密钥按服务地址保存在 macOS 钥匙串；本地服务可使用 loopback HTTP。
- 0.8.3：左右拖动阅读区与 AI 之间的分隔线调整宽度；上下拖动输入框上方调整高度；点击独立窗口图标可移动或停靠 AI。详细发送说明收在信息菜单，长文节选范围始终明确标记。
- 0.8.2：配置 API 地址及密钥后可获取模型列表、搜索或手动填写模型；在对话面板直接切换模型和支持的推理强度。高强度通常耗时更长、可能产生更多费用。未知模型默认采用服务商的推理设置。
- 支持文献内容、仅选中文字和仅对话；本轮资料范围、长文节选以及近期对话发送提示显示在发送按钮旁。文献文字超过 24,000 字符时使用分布在全文中的节选，并标注非全文。只有主动点击发送才会联网；API 费用取决于你的服务商。
- 笔记及已保存聊天记录分别位于应用支持目录的 `ResearchNotes` 和 `ResearchChats`。从书架移除后仍保留独立笔记与对话，重新导入相同内容可恢复。
- Word 划选限同一个段落，已建段落批注的 PDF 暂时限制重新合并或撤销段落，保留定位准确性。扫描版 PDF 无文字层时不能划词；AI 本版本分析提取的文字，不解析原页图片或图标。

## 翻译服务与隐私

默认使用 Google 免登录、免密钥网页接口，**无需 Google 账号，也不共用开发者的账号或 API Key**。每位使用者的电脑直接向所选翻译服务发送请求。

原始文件在本地解析，翻译时会把待翻译的文字发送给所选服务。请根据文档内容决定是否使用在线翻译。应用不上传原文件或修改原文件；使用 AI 时会按用户选择发送文献文字及近期对话。

Google 和必应网页接口不是有稳定性保证的官方付费 API，可能限流、超时或变更。2026-11-13 的验证中 Google 可用，必应遇到 HTTP 401；应用不会绕过验证，也不会自动切换服务。

也可在设置中配置自己的 Azure Translator 密钥。密钥保存在 macOS 钥匙串；资源计费与额度取决于你在 Azure 中选择的方案，应用无法查询或更改订阅定价层。

译文缓存位于 `~/Library/Application Support/BilingualReader/translations.json`。可在「设置 → 本机缓存」中清理。

## PDF 与 Word 兼容性

0.6.1 修复 EGU 等把正文嵌入 PDF 页面对象的文档：支持嵌套文字、较大行距、重复页眉过滤及跨页续段。

扫描版 PDF 暂无 OCR。复杂多栏、图表、参考文献仍建议核对原页。DOCX 的分页和复杂浮动对象可能与 Microsoft Word 有差异；旧版 DOC 请先另存为 DOCX。

## 从源码构建

需要 Apple Silicon Mac、macOS 13+ 和 Xcode Command Line Tools。源码包含 Swift 阅读器与本地 Word 渲染库；Python 运行时放在 Release 安装包中，避免把平台二进制文件放进 Git 历史。

先从 Release 下载同版本安装包到项目根目录，再提取其中的 PDF 运行时：

```sh
mkdir -p build/release-runtime
ditto -x -k BilingualReader-0.9.0-macOS-arm64.zip build/release-runtime
cp -R 'build/release-runtime/BilingualReader.app/Contents/Resources/PDFEngine/python' Resources/PDFEngine/python
zsh build.sh
```

构建产物为 `dist/BilingualReader.app` 与 `dist/BilingualReader-Mac.zip`。用户运行安装包无需自行安装 Python。

也可使用 `Tools/BundlePDFEngine.py` 从独立 Python 环境准备运行时；所需版本见 `Resources/PDFEngine/VERSIONS.txt`。该工具要求 Python 可复制运行，并且相关包安装在该解释器环境中。

## 验证

准备好 PDF 运行时后：

```sh
zsh check.sh
zsh check-library.sh
zsh check-categories.sh
zsh check-shelf-scroll.sh
zsh check-shelf-layout.sh
zsh check-window-layout.sh
zsh check-reader-pane.sh
zsh preview-reader-pane.sh
zsh check-library-model.sh
zsh check-layout.sh
zsh check-reliability.sh
zsh check-reliability.sh --review
zsh check-word.sh fixtures/rich-example.docx
zsh check-research-notes.sh
zsh check-research-ai.sh
zsh check-research-integration.sh
zsh preview-research.sh
```

可选真实文档检查（文献文件不随仓库分发）：

```sh
zsh check-nested-pdf.sh /path/to/egusphere-2026-6385.pdf
zsh check-pdf.sh '/path/to/African rice cultivation linked to rising methane.pdf'
```

`zsh check.sh --network` 会发送固定示例句，检查 Google 翻译与缓存；追加 `--bing` 检查必应。

## 许可

本项目新增代码采用 [MIT License](LICENSE)。必应请求适配参考 Jingyuan-Zheng/translate-document-quick-action；pdfminer.six、Python、docx-preview、JSZip 等组件保留各自许可，详见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
