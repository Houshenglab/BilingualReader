# 0.8.1 window and bookshelf layout verification

Original screenshot: native window title and traffic lights were drawn over the reader header, and three books clustered right of the selected book, wasting space. A genuine SwiftUI `WindowGroup` reproduced the cause: `fullSizeContentView=true`, content height 632, native content-layout height 600. This differed from previous preview-only NSWindow checks.

Fix: regular native titlebar, guarded AppKit window configuration, responsive information card + centered cover group in a flexible stage; opaque book faces and a dedicated full-width continue button. Retains animated horizontal trackpad browsing and grid switching. macOS 13 arm64 target unchanged.

Checks:
- `check-window-layout.sh`: genuine SwiftUI window with three synthetic literature entries; titlebar full-size mask false and content/layout height equal at 1300x630 and 900x600 points. Window screenshot permission unavailable; tested the native window geometry and reviewed hosting view bitmap captures. Wide and compact screenshots included in shared build cache. Reviewed complete CTA, opaque faces, all three visible covers.
- `check-shelf-layout.sh`: visible group centered and contained for selected first, middle and last book, tested widths 500/850/1200, heights 170/300/500, counts 1/3/5/12.
- `check-shelf-scroll.sh`: passed horizontal accumulation/direction, vertical isolation, momentum suppression, gesture reset.
- `check-categories.sh`: passed migration, validation, persistence, atomic assignments, rename/delete and corruption protection.
- `preview-research.sh`: passed native PDF markup, annotation panel, note jump and original bytes preserved; research panel previews captured.
- Release: optimized arm64 binary compiled and signed ad hoc; ZIP extracted and full bundle signature verified. Existing verified 0.8.0 PDF runtime and resources reused.

No personal documents used in the tests. Existing reader data remains untouched.
