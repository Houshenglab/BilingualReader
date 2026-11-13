# Third-party code

The BingWebTranslator request flow in Sources/Core.swift is adapted to Swift from
scripts/translate_document_worker.py in Jingyuan-Zheng/translate-document-quick-action.

Source: https://github.com/Jingyuan-Zheng/translate-document-quick-action
Copyright (c) 2026 Jingyuan Zheng. MIT License (full text in vendor/LICENSE).
The original Python worker is preserved in vendor/translate_document_worker.py for reference;
it is not executed and its Python dependencies are not needed by this application.

Google's mobile endpoint was checked but rate-limited; this app instead uses the
Google Translate web JSON endpoint with full paragraph chunking. Both Google and Bing
are unofficial web interfaces, not paid supported APIs. Availability is not guaranteed.

No code from the closed-source Immersive Translate extension, LumenReader, or Gloss
is included. Native reading, file parsing, translation scheduling, cache, and UI are new code.

## Word layout renderer (bundled locally)

docx-preview 0.3.6, Copyright Volodymyr Baydalka and contributors, Apache-2.0.
Source: https://github.com/VolodymyrBaydalka/docxjs
License: Resources/Word/DOCX-LICENSE

JSZip 3.10.1, Copyright Stuart Knightley, David Duponchel, Franz Buchinger, Antal Szabo.
Used under the MIT option of its dual MIT/GPLv3 licensing.
Source: https://github.com/Stuk/jszip
License: Resources/Word/JSZIP-LICENSE

Both scripts are bundled unchanged. Resources/Word/index.html adds paragraph translation
controls and styling, with no modification to upstream library code. No scripts are fetched at runtime.

## PDF parser (bundled, local)

pdfminer.six 20251230, MIT, Copyright (c) 2004-2016 Yusuke Shinyama and contributors.
Source: https://github.com/pdfminer/pdfminer.six
The complete installed parser is bundled in Resources/PDFEngine/python/lib/python3.12/site-packages/pdfminer.
Its original license and distribution metadata accompany it. The adapter in Resources/PDFEngine/layout.py
uses upstream LTTextBoxHorizontal/LTTextLineHorizontal extraction; it makes no network requests.
The Swift reader maps its boxes back to PDFKit coordinates, handles explicit paragraph boundaries,
joins clear continuations and supports reversible in-memory merges.

Python 3.12.14 (PSF license and included third-party notices), cryptography 50.0.1 (Apache-2.0/BSD),
charset-normalizer 3.5.1 (MIT), cffi 2.1.1 (MIT), and pycparser 3.0 (BSD) are included only to run this parser.
All package licenses and metadata are preserved in the bundled site-packages distribution directories.
Python license: Resources/PDFEngine/PYTHON-LICENSE. Versions: Resources/PDFEngine/VERSIONS.txt.
No user-installed Python, Codex runtime path, models, or Python package download is required at runtime.

vendor/pdfminer-layout/layout.py preserves the upstream layout reference fetched from GitHub;
it is reference source, not an additional runtime copy of the parser.
