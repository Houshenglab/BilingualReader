"""Regression: text inside a Form XObject must reach the reader, with page coordinates."""
import importlib.util
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('reader_layout', root / 'Resources/PDFEngine/layout.py')
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)
pages = layout.extract(sys.argv[1])
assert len(pages) == 27
lines = [line for box in pages[0]['boxes'] for line in box['lines']]
assert any('Tropopause structure and biases' in line['text'] for line in lines), 'Nested title is missing'
abstract = next((line for line in lines if line['text'].startswith('Abstract. The thermal tropopause')), None)
assert abstract is not None, 'Nested abstract is missing'
assert abs(abstract['bounds'][0] - 46.489) < 1 and abs(abstract['bounds'][1] - 462.469) < 1, 'Form transform was lost'
assert any('and the tropopause in climate models.' in line['text'] for line in lines), 'Abstract end is missing'
assert all(page['boxes'] for page in pages), 'A page lost all text'
print('PASS: nested EGU title, abstract, transformed source coordinates and 27 pages')
