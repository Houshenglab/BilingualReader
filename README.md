# BilingualReader

English | [简体中文](README.zh-CN.md)

**A macOS reader for research papers, with bilingual translation, annotation and AI-assisted reading.** Read PDF, Word (DOCX) and TXT documents in a single organized library.

[Download for macOS](https://github.com/Houshenglab/BilingualReader/releases/download/v0.9.0/BilingualReader-0.9.0-macOS-arm64.zip) · [Releases](https://github.com/Houshenglab/BilingualReader/releases) · [Official website](https://test.mibhr.cn/bilingualreader/en/) · [Changelog](CHANGELOG.md)

## Features

- **Library:** animated bookshelf and grid, categories, search, batch imports, saved progress.
- **PDF and Word:** preserve the original layout, translate paragraphs or entire documents, pause/resume, cache completed translations, export bilingual HTML.
- **Research notes:** highlight selected text, add comments, search notes, jump to original passages and export Markdown.
- **AI assistant:** connect your own compatible Chat Completions API, choose models and supported reasoning levels, ask questions about the document or selected text, save answers as notes. Resize or detach the AI panel.
- **Interface languages:** English, Simplified Chinese or system default (relaunch after changing). Translation remains English-to-Chinese.

## Installation

1. Download the ZIP from Releases and extract **BilingualReader.app**.
2. Move it to Applications and launch it.
3. Import PDF, DOCX or UTF-8 TXT files. Existing library data is retained when upgrading.

Requires Apple Silicon and macOS 13 or later. The app is ad-hoc signed, not Apple-notarized. Verify the SHA-256 checksum from Releases. If macOS blocks the verified download, use Privacy & Security to allow opening it.

## Translation and privacy

Google's no-key web translation interface is the default; no developer Google account is shared. Online translation sends the selected text to the chosen service. Azure Translator can use your own key. AI requests are sent to your configured provider when you send a message; provider charges may apply. Keys are stored in macOS Keychain. Local files, notes, translations and reading progress are retained on your Mac. Long articles may be sampled rather than sent in full, as indicated in the AI panel.

Scanned PDFs without a text layer are not supported for text selection or OCR. DOCX layout can differ from Microsoft Word. Legacy DOC files should be converted to DOCX first.

## Build

Use an Apple Silicon Mac with macOS 13+ and Xcode Command Line Tools. Prepare the bundled PDF runtime using Tools/BundlePDFEngine.py or extract it from the release app into Resources/PDFEngine/python, then run:

```sh
zsh build.sh
zsh check.sh
zsh check-research-ai.sh
zsh check-research-notes.sh
zsh check-word.sh fixtures/rich-example.docx
```

The output is dist/BilingualReader.app and dist/BilingualReader-Mac.zip. See the [Chinese documentation](README.zh-CN.md) for full build and verification details.

MIT licensed. See [third-party notices](THIRD-PARTY-NOTICES.md).

## Support the author

**Made by Houshenglab · Free and open source.** If this tool saves you time, a GitHub star or an optional cup of coffee is warmly appreciated. Support is entirely voluntary and never unlocks features.

[WeChat appreciation code · Buy Houshenglab a coffee](https://github.com/Houshenglab/Synapse-releases/releases/download/v1.1.138-build146/Houshenglab-WeChat-tip.png)

<a href="https://github.com/Houshenglab/Synapse-releases/releases/download/v1.1.138-build146/Houshenglab-WeChat-tip.png"><img src="https://raw.githubusercontent.com/Houshenglab/Synapse-releases/eb5043daf1ecaadc53d6aec48be4f26d0ded1a02/Houshenglab-WeChat-tip.png" alt="Houshenglab WeChat appreciation code" width="260"></a>
