#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swiftc -parse-as-library Sources/Core.swift Sources/PDFLayout.swift Sources/PDFMinerEngine.swift Sources/LibraryStore.swift Sources/ReaderModel.swift Sources/ReaderLibrary.swift Sources/CategoryChecks.swift -module-cache-path build/module-cache -framework AppKit -framework PDFKit -framework SwiftUI -o build/category-checks
build/category-checks
