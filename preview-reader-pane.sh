#!/bin/zsh
set -euo pipefail
cd -P "${0:A:h}"
mkdir -p build/PanePreview.app/Contents/MacOS
cat > build/PanePreview.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Preview</string><key>CFBundleIdentifier</key><string>local.bilingualreader.panepreview</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc -D READER_PREVIEW -parse-as-library -target arm64-apple-macosx13.0 -module-cache-path "$PWD/build/pane-preview-cache" Sources/{Core,PDFLayout,PDFMinerEngine,LibraryStore,ResearchNotebook,ResearchAI,ReaderModel,ReaderLibrary,ShelfScroll,LibraryCategoryView,ShelfGeometry,LibraryView,ResearchToolbar,ResearchNotesView,ResearchAIView,ReaderPaneGeometry,ReaderWorkspace,App,WordView,PDFReaderView}.swift Tools/PreviewReaderPane.swift -o build/PanePreview.app/Contents/MacOS/Preview -framework SwiftUI -framework AppKit -framework PDFKit -framework CryptoKit -framework WebKit
build/PanePreview.app/Contents/MacOS/Preview
