#!/bin/zsh
set -euo pipefail
cd -P "${0:A:h}"
mkdir -p build
swiftc -parse-as-library Sources/Localization.swift Sources/ShelfGeometry.swift Sources/ShelfGeometryChecks.swift -module-cache-path "$PWD/build/module-cache" -o build/shelf-geometry-checks
build/shelf-geometry-checks
