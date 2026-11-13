#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build dist/双语阅读.app/Contents/MacOS dist/双语阅读.app/Contents/Resources
swiftc -parse-as-library -O -target arm64-apple-macosx13.0 -module-cache-path "$PWD/build/module-cache" Sources/Core.swift Sources/PDFLayout.swift Sources/PDFMinerEngine.swift Sources/ReaderModel.swift Sources/App.swift Sources/WordView.swift Sources/PDFReaderView.swift -o dist/双语阅读.app/Contents/MacOS/BilingualReader -framework SwiftUI -framework AppKit -framework PDFKit -framework CryptoKit -framework WebKit
swiftc Tools/MakeIcon.swift -module-cache-path "$PWD/build/module-cache" -o build/make-icon -framework AppKit
build/make-icon
mkdir -p build/AppIcon.iconset
for pixels in 16 32 128 256 512; do
    sips -z "$pixels" "$pixels" Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${pixels}x${pixels}.png" >/dev/null
    twice=$((pixels * 2))
    sips -z "$twice" "$twice" Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${pixels}x${pixels}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o dist/双语阅读.app/Contents/Resources/AppIcon.icns
cp Info.plist dist/双语阅读.app/Contents/Info.plist
cp THIRD-PARTY-NOTICES.md LICENSE dist/双语阅读.app/Contents/Resources/
cp vendor/LICENSE dist/双语阅读.app/Contents/Resources/UPSTREAM-LICENSE
cp -R Resources/Word dist/双语阅读.app/Contents/Resources/
cp Resources/AppIcon.png dist/双语阅读.app/Contents/Resources/
if [[ ! -x Resources/PDFEngine/python/bin/python3 ]]; then
    : ${BILINGUAL_READER_PYTHON:?Set BILINGUAL_READER_PYTHON to a Python with pdfminer.six and run Tools/BundlePDFEngine.py first}
    "$BILINGUAL_READER_PYTHON" Tools/BundlePDFEngine.py
fi
cp -R Resources/PDFEngine dist/双语阅读.app/Contents/Resources/
cp vendor/pdfminer-layout/LICENSE dist/双语阅读.app/Contents/Resources/PDFEngine/PDFMINER-LICENSE
find dist/双语阅读.app/Contents/Resources/PDFEngine/python -type f -name '*.so' -exec codesign --force --sign - {} \;
codesign --force --sign - dist/双语阅读.app/Contents/Resources/PDFEngine/python/bin/python3
codesign --force --deep --sign - dist/双语阅读.app
swiftc Tools/RegisterApp.swift -module-cache-path "$PWD/build/module-cache" -o build/register-app -framework CoreServices
touch dist/双语阅读.app
build/register-app "$PWD/dist/双语阅读.app"
ditto -c -k --sequesterRsrc --keepParent dist/双语阅读.app dist/双语阅读-Mac.zip
