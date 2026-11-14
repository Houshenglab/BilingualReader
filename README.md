# 双语阅读 · BilingualReader

macOS 本地 PDF、Word 和 TXT 双语阅读器。PDF 支持原页与译文对照、整段中英对照；Word 在原段落下方显示中文，并保留表格、图片和公式。

[下载最新版](https://github.com/Houshenglab/BilingualReader/releases/latest) · [版本记录](CHANGELOG.md) · [第三方许可](THIRD-PARTY-NOTICES.md)

## 下载与安装

1. 在 Releases 下载 `BilingualReader-0.6.1-macOS-arm64.zip`。
2. 解压，将 `双语阅读-0.6.1.app` 拖到「应用程序」，然后打开。
3. 点击「打开文档」，或拖入 PDF、DOCX、UTF-8 TXT 文件。

支持 **Apple Silicon（M 系列芯片）和 macOS 13 及以上**。目前未提供 Intel 版。
应用使用本地临时签名，尚未经过 Apple 公证。确认来自本仓库后，可通过 macOS「系统设置 → 隐私与安全性」允许打开。下载页提供 SHA-256 校验文件。

## 本机书架（0.7.0）

- 启动进入「我的书架」，可在立体封面与网格之间切换，并按文档名搜索。
- 批量导入 PDF、DOCX、TXT，或将多份文件拖入窗口。相同内容自动去重。
- PDF 使用首页封面，Word/TXT 使用标题封面；点击两侧封面或左右滑动切换，点击中间封面开始阅读。
- 自动保存 PDF 页码、段落位置、字号、阅读模式及已完成译文。返回书架后可换一本继续读。
- 文档副本和记录保存在 `~/Library/Application Support/BilingualReader/Library`，原文件移动后仍可打开副本。
- 右键封面选择「从书架移除」仅删除应用管理的副本与该文档记录，不删除原文件。
- 清理翻译缓存也会清除书库保存的译文；已导入的文档和阅读位置保留。
- 动画遵循系统「减少动态效果」设置。

## 阅读与翻译

- **PDF 原页阅读**：点击文字段落，高亮原文并在右侧阅读译文。
- **PDF 段落对照**：按英文段落与中文阅读，支持返回原页、合并相邻段落和撤销。
- **Word 段内翻译**：点击英文段落展开或收起中文；表格内译文留在原单元格中。
- **全文翻译**：翻译任务排队执行，可暂停、继续；优先处理点击的等待段落。
- **超时恢复**：临时故障有限重试；限流或服务认证失败时暂停并保留待翻译任务。
- **缓存与导出**：已完成译文在本机缓存；「阅读」菜单可导出包含原文和已完成译文的 HTML。

## 翻译服务与隐私

默认使用 Google 免登录、免密钥网页接口，**无需 Google 账号，也不共用开发者的账号或 API Key**。每位使用者的电脑直接向所选翻译服务发送请求。

原始文件在本地解析，翻译时会把待翻译的文字发送给所选服务。请根据文档内容决定是否使用在线翻译。应用不上传完整原文件、不修改原文件。

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
ditto -x -k BilingualReader-0.6.1-macOS-arm64.zip build/release-runtime
cp -R 'build/release-runtime/双语阅读-0.6.1.app/Contents/Resources/PDFEngine/python' Resources/PDFEngine/python
zsh build.sh
```

构建产物为 `dist/双语阅读.app` 与 `dist/双语阅读-Mac.zip`。用户运行安装包无需自行安装 Python。

也可使用 `Tools/BundlePDFEngine.py` 从独立 Python 环境准备运行时；所需版本见 `Resources/PDFEngine/VERSIONS.txt`。该工具要求 Python 可复制运行，并且相关包安装在该解释器环境中。

## 验证

准备好 PDF 运行时后：

```sh
zsh check.sh
zsh check-library.sh
zsh check-library-model.sh
zsh check-layout.sh
zsh check-reliability.sh
zsh check-reliability.sh --review
zsh check-word.sh fixtures/rich-example.docx
```

可选真实文档检查（文献文件不随仓库分发）：

```sh
zsh check-nested-pdf.sh /path/to/egusphere-2026-6385.pdf
zsh check-pdf.sh '/path/to/African rice cultivation linked to rising methane.pdf'
```

`zsh check.sh --network` 会发送固定示例句，检查 Google 翻译与缓存；追加 `--bing` 检查必应。

## 许可

本项目新增代码采用 [MIT License](LICENSE)。必应请求适配参考 Jingyuan-Zheng/translate-document-quick-action；pdfminer.six、Python、docx-preview、JSZip 等组件保留各自许可，详见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
