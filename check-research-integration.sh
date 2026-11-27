#!/bin/zsh
set -euo pipefail
cd -P "${0:A:h}"
mkdir -p build
swiftc -parse-as-library -module-cache-path "$PWD/build/research-integration-cache" Sources/Localization.swift Sources/{Core,PDFLayout,PDFMinerEngine,LibraryStore,ResearchNotebook,ResearchAI,ReaderModel,ReaderLibrary,ResearchIntegrationChecks}.swift -o build/research-integration-check -framework SwiftUI -framework AppKit -framework PDFKit -framework CryptoKit
build/research-integration-check
