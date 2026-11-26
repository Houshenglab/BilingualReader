# Research workspace implementation plan

Goal: add persistent local research annotations and AI chat without interrupting existing reading.

- Notebook: add stable scoped annotation data, atomic save, editing/deletion/export, tests for persistence and corruption; exact selection and highlighting in selectable paragraphs.
- AI: add scoped history, endpoint/key configuration, request/response and cancellation, bounded context, prompt presets and save answer, tests for payload/config/isolation.
- PDF/Word: capture native selected text anchors, show highlights and note markers, implement jump and validate rendering; preserve translation/position behavior.
- Shell: bind notebook/AI lifecycle to document identity, one switchable side panel and responsive selection toolbar, unify accent/spacing; validate app compilation and regressions using existing scripts and new tests.
- Package 0.8.0 with previously supported resources in temporary build directory. Verify archive, sync source/tests/docs and artifact to existing project location, report storage status. No public release unless explicitly requested for this version.
