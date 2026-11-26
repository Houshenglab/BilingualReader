#!/bin/zsh
set -euo pipefail
cd -P "${0:A:h}"
mkdir -p build/SceneCheck.app/Contents/MacOS
cat > build/SceneCheck.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>SceneCheck</string><key>CFBundleIdentifier</key><string>local.bilingualreader.scenecheck</string><key>CFBundleName</key><string>SceneCheck</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc -D READER_PREVIEW -parse-as-library -target arm64-apple-macosx13.0 -module-cache-path "$PWD/build/module-cache" Sources/{Core,PDFLayout,PDFMinerEngine,LibraryStore,ResearchNotebook,ResearchAI,ReaderModel,ReaderLibrary,ShelfScroll,LibraryCategoryView,ShelfGeometry,LibraryView,ResearchToolbar,ResearchNotesView,ResearchAIView,ReaderPaneGeometry,ReaderWorkspace,App,WordView,PDFReaderView}.swift Tools/SceneLayoutChecks.swift -o build/SceneCheck.app/Contents/MacOS/SceneCheck -framework SwiftUI -framework AppKit -framework PDFKit -framework CryptoKit -framework WebKit
build/SceneCheck.app/Contents/MacOS/SceneCheck
