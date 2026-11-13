"""Build a local DOCX regression fixture with a table, image and equation."""
from pathlib import Path
import zipfile
root = Path(__file__).resolve().parent.parent
with zipfile.ZipFile(root / 'fixtures/example.docx') as source:
    files = {name: source.read(name) for name in source.namelist()}
xml = files['word/document.xml'].decode()
xml = xml.replace('<w:document ', '<w:document xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" ')
extra = '''<w:p><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr><w:r><w:rPr><w:i/></w:rPr><w:t>Scientific equations and illustrations remain part of the original document.</w:t></w:r></w:p>
<w:p><w:r><w:t>Emission estimate: </w:t></w:r><m:oMath><m:sSub><m:e><m:r><m:t>CH</m:t></m:r></m:e><m:sub><m:r><m:t>4</m:t></m:r></m:sub></m:sSub><m:r><m:t> = A × EF</m:t></m:r></m:oMath></w:p>
<w:p><w:r><w:drawing><wp:inline><wp:extent cx="731520" cy="731520"/><wp:docPr id="1" name="Reading illustration"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="1" name="Reader icon"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rIdImage"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="731520" cy="731520"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="1000" w:bottom="1000" w:left="1000"/></w:sectPr>'''
xml = xml.replace('<w:sectPr/>', extra)
files['word/document.xml'] = xml.encode()
files['word/_rels/document.xml.rels'] = b'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdImage" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/icon.png"/></Relationships>'
files['word/media/icon.png'] = (root / 'Resources/AppIcon.png').read_bytes()
files['[Content_Types].xml'] = files['[Content_Types].xml'].replace(b'</Types>', b'<Default Extension="png" ContentType="image/png"/></Types>')
with zipfile.ZipFile(root / 'fixtures/rich-example.docx', 'w', zipfile.ZIP_DEFLATED) as output:
    for name, content in files.items():
        output.writestr(name, content)
