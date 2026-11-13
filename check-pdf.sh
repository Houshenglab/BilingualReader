#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swiftc -parse-as-library Sources/Core.swift Sources/PDFLayout.swift Sources/PDFMinerEngine.swift Sources/PDFChecks.swift -module-cache-path "$PWD/build/module-cache" -framework AppKit -framework PDFKit -o build/pdf-checks
build/pdf-checks "$1"
