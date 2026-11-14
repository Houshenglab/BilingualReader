# Library categories

Add folder-style, single-category organization to the existing native bookshelf. User requested convenient grouping of literature and other documents, and has previously asked for direct recommended implementation.

UI: horizontal category strip below the header, All and Uncategorized built in, custom categories with counts. Create/rename from a sheet; category context menu for rename/delete with confirmation. Book context menu moves a document. Batch categorization opens a searchable checklist for the current filter with select all and destination picker. Search and both shelf/grid modes use the selected category. Import in a category assigns the new document there; imports from All/Uncategorized preserve an existing duplicate's category. Import target captured when batch starts. Empty-category state offers import. Delete category returns documents to Uncategorized and preserves reading sessions/files.

Data: atomic organization.json holds category IDs/names and book-ID assignments; existing index/session formats untouched. Empty categories persist. Validate names (trim, 1–40 characters, no reserved built-in names, case-insensitive uniqueness). Category changes do not alter lastOpened or reading state. Corrupt organization data must not be silently overwritten. Flat folders chosen over multiple labels/nesting to keep classification simple.

Release 0.7.2/build 10, local build/tests/package, deliver ZIP in Downloads; sync only source changes to original project once.
