# Bookshelf gestures and responsive PDF import

User requests two-finger trackpad shelf navigation and faster initial PDF import. Continue the already-authorized native bookshelf design; no new service/dependency or shared-drive build.

Approach: receive native horizontal scroll events only within the shelf, accumulate movement into animated book steps, respect macOS direction and reduced motion, ignore vertical scrolling and momentum. Retain buttons/click/drag. A full custom continuous carousel is unnecessary for this update.

PDF import currently hashes then copies the entire source, then waits for complete pdfminer layout before publishing a book. Copy and hash in one pass. Validate PDF, generate first-page cover, persist an explicitly pending layout session, then publish. On first open show the original PDF immediately, analyze paragraphs off the main thread and persist them. Existing sessions remain compatible; pending reading location survives exit, errors offer retry, stale analysis must not change another document. Do not replace the accurate layout engine with a faster but lower-quality extractor. DOCX/TXT retain existing behavior.

Version 0.7.1. Build/test/package locally and deliver a verified ZIP in Downloads. No GitHub publication or repeated shared-volume copies.
