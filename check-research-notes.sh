#!/bin/zsh
set -euo pipefail
cd -P "${0:A:h}"
mkdir -p build
swiftc -parse-as-library -target arm64-apple-macosx13.0 -module-cache-path build/module-cache Sources/ResearchNotebook.swift Sources/ResearchNotesChecks.swift -o build/check-research-notes -framework SwiftUI -framework AppKit -framework CryptoKit
build/check-research-notes
