#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
swiftc -parse-as-library -target arm64-apple-macosx13.0 -module-cache-path build/module-cache Sources/WordChecks.swift -o build/word-checks -framework AppKit -framework WebKit
build/word-checks "${1:-$PWD/fixtures/example.docx}"
