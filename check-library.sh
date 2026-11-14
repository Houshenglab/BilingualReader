#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
swiftc -parse-as-library Sources/Core.swift Sources/PDFLayout.swift Sources/PDFMinerEngine.swift Sources/LibraryStore.swift Sources/LibraryChecks.swift -module-cache-path build/module-cache -framework AppKit -framework PDFKit -o build/library-checks
build/library-checks
