#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
swiftc -parse-as-library -module-cache-path "$PWD/build/module-cache" Sources/Localization.swift Sources/Core.swift Sources/PDFLayout.swift Sources/PDFMinerEngine.swift Sources/LibraryStore.swift Sources/ResearchNotebook.swift Sources/ResearchAI.swift Sources/ReaderModel.swift Sources/ReaderLibrary.swift Sources/ReliabilityChecks.swift -o build/reliability-checks -framework AppKit -framework PDFKit -framework CryptoKit -framework SwiftUI
build/reliability-checks "$@"
