#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
Resources/PDFEngine/python/bin/python3 -I -B Tools/CheckNestedPDF.py "$1"
swiftc -parse-as-library Sources/Core.swift Sources/PDFLayout.swift Sources/PDFMinerEngine.swift Sources/NestedPDFChecks.swift -module-cache-path "$PWD/build/module-cache" -framework AppKit -framework PDFKit -o build/nested-pdf-checks
build/nested-pdf-checks "$1"
