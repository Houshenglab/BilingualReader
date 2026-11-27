#!/bin/zsh
set -euo pipefail
cd -P "${0:A:h}"
mkdir -p build/AIControlsPreview.app/Contents/MacOS
cat > build/AIControlsPreview.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Preview</string><key>CFBundleIdentifier</key><string>local.bilingualreader.aicontrolspreview</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc -parse-as-library -target arm64-apple-macosx13.0 -module-cache-path "$PWD/build/ai-preview-cache" Sources/Localization.swift Sources/ResearchAI.swift Sources/ResearchAIView.swift Tools/PreviewAIControls.swift -o build/AIControlsPreview.app/Contents/MacOS/Preview -framework SwiftUI -framework AppKit -framework Security -framework CryptoKit
build/AIControlsPreview.app/Contents/MacOS/Preview
