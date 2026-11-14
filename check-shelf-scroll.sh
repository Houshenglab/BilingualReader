#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swiftc -parse-as-library Sources/ShelfScroll.swift Sources/ShelfScrollChecks.swift -module-cache-path build/module-cache -framework AppKit -framework SwiftUI -o build/shelf-scroll-checks
build/shelf-scroll-checks
