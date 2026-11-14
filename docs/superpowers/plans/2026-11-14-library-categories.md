# Library Categories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for inline implementation.

**Goal:** Persist user-defined document categories and enable single/batch classification in the bookshelf.
**Architecture:** Atomic organization sidecar owned by LibraryStore; ReaderModel filtering/actions; native SwiftUI category strip and editing/batch sheets.
**Tech Stack:** SwiftUI/AppKit/Foundation; no dependencies.
**Spec:** docs/superpowers/specs/2026-11-14-library-categories-design.md

## Global Constraints
macOS 13+, existing books and translations preserved, no full app copy to shared directory during development.

## Review Focus
- Legacy library has no sidecar: all books visible/uncategorized.
- Deleting category never deletes documents or sessions.
- Duplicate imports and changing the filter mid-batch must not misclassify documents.
- Empty/duplicate/reserved names and stale destination IDs fail without partial mutation.
- Corrupt sidecar cannot be silently reset; batch selection cannot affect hidden/unselected books.

### Task 1: Storage and model
Files: LibraryStore.swift, ReaderModel.swift, ReaderLibrary.swift, CategoryChecks.swift, check-categories.sh.
Interfaces: LibraryCategory, LibraryOrganization, LibraryFilter; store organization/createCategory/renameCategory/deleteCategory/assignCategory; model matchingBooks/query, category actions, import target capture.
- [x] Write and run red tests for persistent categories, migration, rename/delete, batch assignments, preserved session bytes and invalid inputs.
- [x] Implement atomic sidecar, category filtering and async model actions; integrate import and removal.
- [x] Verify persistence across fresh store instances, import routing, duplicate handling and filter/search composition.

### Task 2: UI and release
Files: LibraryView.swift, LibraryCategoryView.swift, Tools/PreviewLibrary.swift, build/preview scripts, Info.plist, CHANGELOG.md.
- [x] Add category strip, category editor, book move menu, batch selection sheet and meaningful empty state.
- [x] Native preview category/create/rename/delete/filter/search and batch sheet, retain PDF/Word roundtrip checks.
- [x] Independent review; fix material findings with regressions.
- [x] Run relevant regression suite, build/extract/signature verify 0.7.2; deliver ZIP to Downloads and sync source once.
