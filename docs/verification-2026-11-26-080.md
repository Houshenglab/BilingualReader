# BilingualReader 0.8.0 verification — 2026-11-26

Platform: Apple Silicon macOS; Swift 6.4.2 targeting arm64-apple-macosx13.0. Built in an isolated task directory outside OneDrive. Original 0.7.2 ZIP was checked against its established SHA-256 and app signature; its bundled PDF Python runtime was reused. No private literature or credentials were used.

Passed checks:
- `check-research-notes.sh`: highlight colors, anchored/independent notes, recoding, editing/deletion, corruption protection, draft anchor and unsaved comment handling, UTF-16 resolution.
- `check-research-ai.sh`: endpoint validation, no unrelated text in selection scope, complete/sampled document, selected excerpt follow-up, request/response, isolated history, mock request, cancellation, corrupt-history protection. No actual provider request was made.
- `check-research-integration.sh`: stable per-book note/chat identity, switching and reopening library books, return-to-library state.
- `check-word.sh fixtures/rich-example.docx`: original styling/table/image/math preservation, inline translations, exact UTF-16 selection across styled runs, overlapping marks, comment/scroll and removal, second Word document.
- `preview-research.sh`: actual native PDF selected text rectangles, PDFKit highlight and note marker, note jump, original file byte preservation; screenshot review of original and paragraph modes and AI panel. Actual page thumbnail verifies color and margin marker. Window capture was unavailable, so native view bitmap fallback was used for the window previews.
- `check.sh`, `check-library.sh`, `check-categories.sh`, `check-shelf-scroll.sh`, `check-layout.sh`, `check-reliability.sh`, `check-library-model.sh fixtures/example.pdf`: all completed successfully with bundled parser and no live translation requests. The parser child process needed normal macOS execution outside the restricted tool shell.
- Release compiled optimized, signed ad hoc; extracted ZIP signature verified and Info.plist version 0.8.0 confirmed; bundled Python parser ran against example PDF.

Known limits: Word selections must be within a paragraph; PDF paragraph renumbering is blocked while anchored paragraph annotations exist. AI uses extracted text rather than image/figure understanding and marks excerpts if longer than 24,000 chars. Live API compatibility depends on user-supplied endpoint/model/key.
