#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
swiftc -parse-as-library -module-cache-path "$PWD/build/module-cache" Sources/Core.swift Sources/PDFLayout.swift Sources/PDFMinerEngine.swift Sources/LayoutChecks.swift -o build/layout-checks -framework AppKit -framework PDFKit -framework CryptoKit
build/layout-checks
