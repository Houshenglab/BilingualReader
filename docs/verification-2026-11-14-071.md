# 0.7.1 verification

- Local EGU 27-page import benchmark (optimized Swift executable, same file/storage): before 1.0713 s, after 0.0334 s. This measures library admission, not completed paragraph analysis; PDF analysis is deferred to opening and cached. Remote file transfer remains dependent on network/storage.
- New model regressions: pending session after import, original-first state, page save during preparation, completed layout/translation cache, late completion isolation, interrupted layout resume, blank/scanned PDF readable with retry, prompt parser cancellation.
- Trackpad checks: horizontal accumulation/direction, phase reset, inertia suppression, mixed-axis vertical gesture lock, actual NSEvent dispatch through AppKit monitor, bounds/window/hidden filtering, teardown callback removal.
- Store checks include locked and corrupt PDF rejection, duplicate detection, copied-byte fidelity, failed import staging cleanup and backwards-compatible session reads.
- Final core, layout, library, model, scroll, EGU, four-paper PDF, translation queue and reliability review checks passed. Native SwiftUI/PDFKit/WebKit preview passed original-first PDF display, page 2 restore, explicit page 3 navigation/reopen and Word DOM translation restore.
- Review by independent agent found cancellation subprocess leak and vertical drift axis issue. Both reproduced with failing tests, fixed and verified green. No deferred findings.
- One parallel invocation of the two reliability modes raced on their shared output executable; rerun sequentially passed. SwiftUI compiler and native preview required normal host execution permissions.
- Build 0.7.1 (9), archive extraction and deep strict signature verification passed.
- Archive: BilingualReader-0.7.1-macOS-arm64.zip, 26,171,697 bytes.
- SHA256: 6a3391d51427e95b216435ceb0336f7779fe36c22de760d7700c6e2eec40544a
