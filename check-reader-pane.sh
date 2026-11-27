#!/bin/zsh
set -euo pipefail
cd -P "${0:A:h}"
mkdir -p build
swiftc -parse-as-library -module-cache-path "$PWD/build/pane-check-cache" Sources/Localization.swift Sources/ReaderPaneGeometry.swift Sources/ReaderPaneChecks.swift -o build/reader-pane-checks
build/reader-pane-checks
