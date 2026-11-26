#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
preview_bundle="$PWD/build/Preview.app/Contents"
mkdir -p "$preview_bundle/MacOS" "$preview_bundle/Resources"
cp -R Resources/Word "$preview_bundle/Resources/"
cp Resources/AppIcon.png "$preview_bundle/Resources/"
cat > "$preview_bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Preview</string><key>CFBundleIdentifier</key><string>local.bilingualreader.preview</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc -D READER_PREVIEW -parse-as-library -target arm64-apple-macosx13.0 -module-cache-path build/module-cache Sources/Core.swift Sources/PDFLayout.swift Sources/PDFMinerEngine.swift Sources/LibraryStore.swift Sources/ResearchNotebook.swift Sources/ResearchAI.swift Sources/ReaderModel.swift Sources/ReaderLibrary.swift Sources/ShelfScroll.swift Sources/LibraryCategoryView.swift Sources/ShelfGeometry.swift Sources/LibraryView.swift Sources/ResearchToolbar.swift Sources/ResearchNotesView.swift Sources/ResearchAIView.swift Sources/ReaderPaneGeometry.swift Sources/ReaderWorkspace.swift Sources/App.swift Sources/WordView.swift Sources/PDFReaderView.swift Tools/PreviewLibrary.swift -o "$preview_bundle/MacOS/Preview" -framework SwiftUI -framework AppKit -framework PDFKit -framework CryptoKit -framework WebKit
"$preview_bundle/MacOS/Preview" "$@"
