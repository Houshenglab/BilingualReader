# 0.7.2 verification

- Categories stored in atomic organization.json; legacy index/session formats unchanged. No sidecar means Uncategorized. Names are trimmed, 1–40 characters, unique ignoring case, excluding built-ins.
- CategoryChecks: persistent empty/custom categories, rename identity, single/batch moves, rejected batch atomicity, deletion without file/session loss, session/index byte preservation, corrupt sidecar protection, import target snapshot, duplicate imports from All/Uncategorized, combined search/category filter, deleted-active-filter fallback.
- Independent review found failed book removal could clear its category before index write failed. Reproduced RED with index destination made unwritable, restored previous organization on index-write failure, GREEN.
- Review also found Cancel during category saving could allow late completion to override navigation. Editor now disables all controls and interactive dismissal during saving.
- Native preview uses in-process AppKit mouse events: opens category editor, enters/saves name, opens batch sheet, selects two documents, chooses Uncategorized via the native menu window and applies; verifies sheet dismissal and changed category results. Category shelf/empty/batch screenshots inspected.
- Existing PDF original-first rendering, page 2 restoration, explicit page 3 navigation/reopen and Word DOM translation restoration pass in the same native preview.
- Final category, library, model, shelf-scroll, core, layout, queue/reliability and reliability-review checks pass. Expected CoreGraphics warning appears for deliberately malformed PDF.
- SwiftUI accessibility tree was empty in the preview harness; used native events instead. Test-only menu targeting was corrected to send events to its actual NSWindow. No product workaround or dependency added.
- Version 0.7.2/build 10; extracted ZIP deep strict code-signature verification passed. Verified copy delivered to Downloads.
- ZIP size 26,262,079 bytes; SHA256 e8199c22633c147d126ede2c32d746318a282a6f6232b78a3e2117b83a3014c8.
