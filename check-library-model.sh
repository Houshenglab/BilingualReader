#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
swiftc -parse-as-library Sources/Core.swift Sources/PDFLayout.swift Sources/PDFMinerEngine.swift Sources/LibraryStore.swift Sources/ReaderModel.swift Sources/ReaderLibrary.swift Sources/LibraryModelChecks.swift -module-cache-path build/module-cache -framework AppKit -framework PDFKit -framework SwiftUI -o build/library-model-checks
build/library-model-checks "$@"
