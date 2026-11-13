"""Local pdfminer.six adapter. Document content never leaves this process."""
import json
import logging
import sys
from statistics import median
from pdfminer.high_level import extract_pages
from pdfminer.layout import LAParams, LTTextBoxHorizontal, LTTextLineHorizontal, LTChar, LTFigure

logging.getLogger('pdfminer').setLevel(logging.ERROR)


def text_boxes(container, page, artwork=False):
    # Publishers can embed the complete manuscript in a Form XObject. pdfminer
    # has already applied its transform, so retain these page-space coordinates.
    for item in container:
        if isinstance(item, LTTextBoxHorizontal):
            yield item, artwork
        elif isinstance(item, LTFigure):
            small_form = item.height < page.height * 0.25 or item.width < page.width * 0.35
            yield from text_boxes(item, page, artwork or small_form)


def extract(path):
    pages = []
    for page in extract_pages(path, laparams=LAParams(line_margin=0.5, boxes_flow=-0.5, all_texts=False)):
        # Analyze embedded content separately: manuscript forms often have wider
        # leading. Keep the established grouping for ordinary journal pages.
        for item in page:
            if isinstance(item, LTFigure):
                item.analyze(LAParams(line_margin=0.8, boxes_flow=-0.5, all_texts=True))
        boxes = []
        for box, artwork in text_boxes(page, page):
            lines = []
            for line in box:
                if not isinstance(line, LTTextLineHorizontal):
                    continue
                text = line.get_text().strip()
                if text:
                    chars = [c for c in line if isinstance(c, LTChar) and c.get_text().strip()]
                    lines.append({'text': text, 'bounds': list(line.bbox),
                                  'fontSize': median([c.size for c in chars]) if chars else None,
                                  'fontName': max(set(c.fontname for c in chars), key=lambda name: sum(c.fontname == name for c in chars)) if chars else None})
            if lines:
                boxes.append({'lines': lines, 'isArtwork': artwork})
        pages.append({'number': page.pageid, 'boxes': boxes})
    return pages


if __name__ == '__main__':
    try:
        json.dump(extract(sys.argv[1]), sys.stdout, ensure_ascii=False, separators=(',', ':'))
    except Exception as error:
        print(type(error).__name__ + ': ' + str(error)[:400], file=sys.stderr)
        sys.exit(1)
