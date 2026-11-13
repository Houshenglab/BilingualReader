import Foundation
import PDFKit
@main struct Check {
static func main() throws {
guard CommandLine.arguments.count == 2 else { fatalError("Pass the African rice paper PDF path") }
let url=URL(fileURLWithPath: CommandLine.arguments[1])
let values=try DocumentLoader.load(url)

let summary=values.filter{$0.text.hasPrefix("Africa has been identified")}
precondition(summary.count == 1 && summary[0].text.hasSuffix("mitigation goals."))
precondition(!summary[0].text.contains("Check for updates") && !summary[0].text.contains("Zichong"))
let inverse=values.first{$0.text.hasPrefix("Inverse top-down")}!
precondition(inverse.text.contains("A global inversion") && inverse.text.hasSuffix("trend9."))
let card=values.first{$0.text.hasPrefix("In response to the 2007")}!
precondition(card.text.contains("The target for the second phase") && card.text.hasSuffix("participating countries."))
let edgar=values.first{$0.text.hasPrefix("Current methane emission inventories")}!
precondition(edgar.sourceRegions.contains{$0.page==2}, "Cross-page continuation")
precondition(edgar.text.contains("upland fraction of the rice area"))
precondition(!values.contains{$0.text == "."})
precondition(values.allSatisfy{!$0.sourceRegions.isEmpty})
let root = url.deletingLastPathComponent()
let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
if let grpi = files.first(where: { $0.lastPathComponent.hasPrefix("Earth s Future") && $0.pathExtension == "pdf" }) {
    let blocks = try DocumentLoader.load(grpi)
    let abstract = blocks.filter { $0.text.hasPrefix("Abstract Rice agriculture") }
    precondition(abstract.count == 1 && abstract[0].sourceRegions.count >= 20)
    precondition(abstract[0].text.hasSuffix("organic matter management."))
    precondition(!abstract[0].text.contains("Supporting Information") && !abstract[0].text.contains("Zichong"))
    let summary = blocks.first { $0.text.hasPrefix("Plain Language Summary Rice agriculture") }!
    precondition(summary.text.hasSuffix("between countries.") && summary.sourceRegions.count >= 8)
    print("PASS: GRPI full 21-line abstract and plain-language summary, sidebar separation")
}
if let acs = files.first(where: { $0.lastPathComponent.hasPrefix("EST2024") && $0.pathExtension == "pdf" }) {
    let blocks = try DocumentLoader.load(acs)
    let abstract = blocks.filter { $0.text.hasPrefix("ABSTRACT: Rice cultivation") }
    precondition(abstract.count == 1 && abstract[0].sourceRegions.count >= 18)
    precondition(abstract[0].text.hasSuffix("natural wetlands.") && !abstract[0].text.contains("KEYWORDS:"))
    print("PASS: ACS complete abstract and keyword separation")
}
if let monsoon = files.first(where: { $0.lastPathComponent.hasPrefix("季风亚洲") && $0.pathExtension == "pdf" }) {
    let blocks = try DocumentLoader.load(monsoon)
    let abstract = blocks.filter { $0.text.hasPrefix("Rice is a staple food for more than half of humanity") }
    precondition(abstract.count == 1 && abstract[0].sourceRegions.count >= 15)
    precondition(abstract[0].text.hasSuffix("types and local environment."))
    print("PASS: Monsoon Asia complete 15-line abstract")
}
let example = [
    ReadingParagraph(id: 0, text: "A continued para-", page: 1, sourceRegions: [PDFSourceRegion(page: 1, bounds: CGRect(x: 10, y: 20, width: 100, height: 12))]),
    ReadingParagraph(id: 1, text: "graph on the next page.", page: 2, sourceRegions: [PDFSourceRegion(page: 2, bounds: CGRect(x: 10, y: 80, width: 100, height: 12))]),
    ReadingParagraph(id: 2, text: "Another paragraph.", page: 2, translation: "另一段。")
]
let merged = PDFLayout.merge(example, first: 0, second: 1)
precondition(merged.count == 2 && merged[0].text == "A continued paragraph on the next page.")
precondition(merged[0].sourceRegions.count == 2 && merged[0].translation == nil)
precondition(merged[1].id == 1 && merged[1].translation == "另一段。")
precondition(example[0].text == "A continued para-", "The undo snapshot stays intact")
print("PASS: manual merge, cross-page highlights, stable IDs, unrelated translations and undo snapshot")
print("PASS: complete abstract, citations, cross-column paragraph, cross-page paragraph and source locations")
}
}
