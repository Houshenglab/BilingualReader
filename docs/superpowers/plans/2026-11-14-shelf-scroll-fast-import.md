# Bookshelf navigation and import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Support native two-finger shelf scrolling and remove full PDF analysis from import/first-display latency.
**Architecture:** Local AppKit scroll adapter within SwiftUI; one-pass copy/hash and explicit pending layout state; async reader preparation with generation guards.
**Tech Stack:** SwiftUI, AppKit, PDFKit, existing bundled pdfminer.
**Spec:** docs/superpowers/specs/2026-11-14-shelf-scroll-fast-import-design.md

## Global Constraints
macOS 13+, arm64, no added dependencies; retain existing reading/translation data; all development in /tmp.

## Review Focus
- Vertical scrolling and inertia must not unexpectedly change books.
- Invalid/encrypted PDF must fail import without orphan records.
- Leaving an analyzing PDF must not overwrite the new document or lose page location.
- Failed/unfinished analysis must remain retryable across restart.
- Existing saved translations must not be reparsed or discarded.

### Task 1: Responsive PDF import and reading
Files: LibraryStore.swift, ReaderLibrary.swift, ReaderModel.swift, App.swift, PDFReaderView.swift, LibraryModelChecks.swift, LibraryChecks.swift.
Interfaces: ReadingSession.layoutPending optional Bool for backward compatibility; ReaderModel pdfLayoutPending/preparingPDF/pdfPreparationError; preparePDFLayout() retries current pending PDF.
- [x] Add real-PDF import test asserting empty/pending session after import, early original-page display and eventual populated persisted session. Run and observe RED.
- [x] Copy/hash once using temporary staging; validate PDF without full layout; create pending session.
- [x] Display PDF before detached analysis; disable translation pending, show status/retry; persist page while pending, guard stale results by generation.
- [x] Run library/model checks incl. invalid and duplicate imports, stale-open and restored translation cases; benchmark real EGU first import.
- [x] Commit.

### Task 2: Trackpad shelf navigation
Files: ShelfScroll.swift, LibraryView.swift, ShelfScrollChecks.swift, check-shelf-scroll.sh; build/preview scripts.
Interfaces: ShelfScrollAccumulator.consume(horizontal:vertical:precise:phase:momentum:timestamp:) -> Int; ShelfScrollInput(onMove:) NSViewRepresentable.
- [x] Test accumulated horizontal motion, reverse direction, vertical, momentum, gesture reset. Observe RED before implementation.
- [x] Add scoped native event monitor behind shelf without intercepting clicks; remove monitor on dismantle; move existing animated selection.
- [x] Run accumulator plus actual NSWindow event routing checks and existing native preview.
- [x] Commit.

### Task 3: Verify and package
- [x] Run build and relevant existing PDF/layout/reader/Word/reliability checks, review complete diff.
- [x] Set 0.7.1/build 9, update release notes, build signed app, verify ZIP extraction/signature and hash.
- [x] Deliver ZIP in Downloads; save source changes as a small archive rather than repeatedly writing the SMB share.
