import Foundation
import PDFKit
@main struct LayoutChecks {
    static func main() {
        var failures = 0
        func check(_ pass: Bool, _ name: String) { print("\(pass ? "PASS" : "FAIL"): \(name)"); if !pass { failures += 1 } }
        func line(_ text: String, _ x: CGFloat = 50, _ y: CGFloat, _ width: CGFloat = 220) -> PDFLayout.Line {
            PDFLayout.Line(text: text, bounds: CGRect(x: x, y: y, width: width, height: 12))
        }
        let separate = PDFLayout.paragraphs(in: [line("This is the first paragraph.", 50, 700), line("This is a separate paragraph.", 50, 650)], page: 1, kind: "body")
        check(separate.count == 2, "paragraph whitespace splits equal indentation")
        let spaced = PDFLayout.paragraphs(in: [line("A paragraph with ordinary double", 50, 700), line("spacing must remain continuous", 50, 676), line("when all line distances agree.", 50, 652)], page: 1, kind: "body")
        check(spaced.count == 1, "consistent wide line spacing stays together")
        let a = PDFLayout.Block(text: "An unfinished body fragment", regions: [PDFSourceRegion(page: 1, bounds: CGRect(x: 50, y: 700, width: 220, height: 12))], kind: "body", height: 12, indented: false)
        let b = PDFLayout.Block(text: "unrelated text in another column", regions: [PDFSourceRegion(page: 1, bounds: CGRect(x: 350, y: 700, width: 220, height: 12))], kind: "body", height: 12, indented: false)
        check(!PDFLayout.canContinue(a, b), "same-height columns are not continuations")
        let heading = PDFLayout.paragraphs(in: [line("Introduction", 50, 700), line("This section introduces the study.", 50, 680)], page: 1, kind: "body")
        check(heading.count == 2 && heading.first?.kind == "heading", "section heading stays separate from body")
        let narrow = PDFLayout.paragraphs(in: [line("This narrow column contains", 50, 700, 115), line("ordinary running body text", 50, 685, 115), line("continued on another page", 50, 670, 115), line("without final punctuation", 50, 655, 115)], page: 1, kind: "body")
        check(narrow.count == 1 && narrow.first?.kind == "body", "narrow running text remains readable")
        let shortFragment = (0..<3).map { index in
            PDFLayout.Line(text: ["This narrow paragraph continues", "with several ordinary body words", "across the following page boundary"][index], bounds: CGRect(x: 50, y: 90 - index * 13, width: 115, height: 10))
        }
        let short = PDFLayout.paragraphs(in: shortFragment, page: 1, kind: "body")
        check(short.count == 1 && short[0].kind == "body", "short 10pt narrow prose is not hidden as a figure")
        var bottom = a; bottom.regions = [PDFSourceRegion(page: 1, bounds: CGRect(x: 50, y: 60, width: 220, height: 12))]
        bottom.pageBounds = CGRect(x: 0, y: 0, width: 600, height: 800)
        bottom.columnBounds = CGRect(x: 50, y: 60, width: 220, height: 360)
        var top = b; top.regions = [PDFSourceRegion(page: 1, bounds: CGRect(x: 350, y: 408, width: 220, height: 12))]
        top.pageBounds = bottom.pageBounds; top.columnBounds = CGRect(x: 350, y: 60, width: 220, height: 360)
        check(PDFLayout.canContinue(bottom, top), "column starts below an abstract still continue")
        top.regions = [PDFSourceRegion(page: 2, bounds: CGRect(x: 50, y: 248, width: 220, height: 12))]
        top.columnBounds = CGRect(x: 50, y: 50, width: 220, height: 210)
        check(PDFLayout.canContinue(bottom, top), "next-page body below a figure still continues")
        top.kind = "heading"
        check(!PDFLayout.canContinue(bottom, top), "heading blocks continuation")
        exit(failures == 0 ? 0 : 1)
    }
}
