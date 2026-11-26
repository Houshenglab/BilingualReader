#!/bin/zsh
set -euo pipefail
cd -P "${0:A:h}"
mkdir -p build
swiftc -parse-as-library -target arm64-apple-macosx13.0 -module-cache-path "$PWD/build/ai-module-cache" Sources/ResearchAI.swift Sources/ResearchAIView.swift Sources/ResearchAIChecks.swift -o build/research-ai-check -framework SwiftUI -framework AppKit -framework Security -framework CryptoKit
build/research-ai-check
