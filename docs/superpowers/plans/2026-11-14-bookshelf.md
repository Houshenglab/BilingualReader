# Bookshelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Persistent animated document library with reliable reading restoration.
**Architecture:** LibraryStore actor owns disk metadata, managed copies and sessions. ReaderModel coordinates import/open/save; a separate LibraryView owns shelf/grid presentation. Existing native readers report/restore anchors.
**Tech Stack:** SwiftUI, Foundation, CryptoKit, PDFKit, WKWebView, macOS 13+.
**Spec:** docs/superpowers/specs/2026-11-14-bookshelf-design.md

## Global Constraints
- macOS 13+, Apple Silicon; no new dependencies or cloud storage.
- Originals untouched; deduplicate content; atomic writes; never silently reset corrupt metadata.
- Restore completed translations only for matching engine; no resumed network work.
- Keep existing PDF/Word behavior and existing 0.6.1 bundle.

## Review Focus
- Moved originals and repeated/same-name imports: storage tests.
- Corrupt/unsupported documents and index corruption: storage tests.
- Switching while opening/translating: model generation and restoration tests.
- Word DOM readiness and repeated paragraph text: model and WebKit tests.
- Clearing cache/removing books then delayed saves: storage/model tests.

### Task 1: Library persistence
Files: Sources/LibraryStore.swift, Sources/LibraryChecks.swift, check-library.sh.
Interfaces: LibraryBook Codable/Identifiable(id,title,fileName,format,addedAt,lastOpened,pageCount,translatedCount); ReadingSession Codable(paragraphs,page,paragraphID,mode,fontSize,engine,modifiedAt); actor LibraryStore(root: URL?) with list(), importDocument(URL), documentURL(book), coverURL(book), session(id), save(id,session), remove(id), clearTranslations().
- [ ] Write executable checks for duplicate imports, same-name different content, copied-original removal, corrupt index, invalid document rollback, session roundtrip, late save after removal and clearing translations.
- [ ] Run failing checks, implement storage and run green checks.
- [ ] Commit persistence.

### Task 2: Reader integration
Files: ReaderModel.swift, ReaderLibrary.swift, PDFReaderView.swift, WordView.swift, Resources/Word/index.html, App.swift, existing compile scripts.
Interfaces: model libraryBooks, showingLibrary, currentBookID, readingParagraphID; importDocuments, openBook, returnToLibrary, saveReadingSession, removeBook, restoreWord state. Save debounced plus navigation/translation completion; generation guards.
- [ ] Write model checks for restore, navigation cancellation, Word readiness, engine isolation and cache clear.
- [ ] Implement and verify new + existing reliability checks and Word tests.
- [ ] Commit integration.

### Task 3: Shelf UI and delivery
Files: LibraryView.swift, App.swift, Tools/PreviewLibrary.swift, build.sh, Info.plist, README.md.
- [ ] Implement shelf/grid, PDF thumbnails, typographic Word covers, search, batch import, removal confirmation, reduced motion and keyboard/accessibility labels.
- [ ] Native preview empty/shelf/grid/search and read/return; verify PDF and Word resume after new model creation.
- [ ] Run whole suite; fresh independent review and fix material findings.
- [ ] Build/sign/package 0.7.0, copy source+versioned deliverable back, verify copied package.
