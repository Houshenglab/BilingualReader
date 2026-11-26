# 0.8.3 compact movable AI workspace verification

User screenshot showed conversation compressed by toolbar, prompt cards, permanent explanatory text and fixed input. The new model/effort/menu toolbar is one row, scope and necessary partial-context badge are compact, and detailed privacy/cost/recipient/character count are available in the information popover. Common prompts are in a menu. No permanent bottom copy remains.

- `check-reader-pane.sh` passed width bounds, min reading space and restored preference at narrow/wide windows.
- `preview-reader-pane.sh` passed actual native mouse drag of sidebar from 380 to over 500 points, actual vertical composer drag with saved height increase, composer bounds, detached resizable NSWindow movement, re-docking, and draft retained in shared ResearchAI. Visual captures at 1120×470 include compact, expanded, resized input, chat content and floating window. No actual API or personal data used.
- `check-research-ai.sh` passed model discovery, credential isolation, model-specific reasoning, history, persistence, cancellation.
- `check-research-integration.sh` passed book-scoped notes/chats and reader navigation.
- `preview-research.sh` passed PDF original highlight, note jump and original bytes preserved, with newly sized sidebar and compact AI screenshot.
- `check-window-layout.sh` passed genuine native SwiftUI scene at wide and compact window dimensions; titlebar remains separate.
- Review identified minimized main window on re-dock: now restore/raise main window and close detached window when reading view disappears. Repeated actual drag/docking test passed.
- Optimized macOS 13 arm64 compiled and ad hoc signed, archive extracted and full signature/0.8.3 metadata verified.
