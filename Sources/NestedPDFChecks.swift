import Foundation
import PDFKit

@main struct NestedPDFChecks {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let values = try DocumentLoader.load(url)
        func require(_ condition: Bool, _ message: String) {
            if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        let abstract = values.filter { $0.text.hasPrefix("Abstract. The thermal tropopause") }
        require(abstract.count == 1, "EGU abstract missing or duplicated")
        require(abstract[0].text.hasSuffix("and the tropopause in climate models."), "EGU abstract split by manuscript line numbers")
        require(abstract[0].sourceRegions.count == 15, "EGU abstract must retain all 15 lines")
        require(!abstract[0].text.contains(" 5 ") && !abstract[0].text.contains(" 10 "), "Margin line numbers entered translation")
        let introduction = values.first { $0.text.hasPrefix("The tropopause represents the transition") }
        require(introduction?.text.contains("gradually change from tropospheric to stratospheric.") == true, "Introduction lines are out of reading order")
        require(introduction?.text.hasSuffix("(e.g. Gettelman et al., 2011).") == true, "Introduction lost its next-page continuation")
        require(introduction?.sourceRegions.contains { $0.page == 2 } == true, "Cross-page source locations missing")
        require(!values.contains { $0.kind == "body" && ($0.text.contains("https://doi.org/10.5194/egusphere-2026-6385") || $0.text.contains("CC BY 4.0 License")) }, "Repeated publisher header is being translated as body")
        print("PASS: EGU complete abstract, line-number exclusion, reading order, cross-page continuation and publisher headers")
        print("Parsed \(values.count) blocks across \(Set(values.flatMap { $0.sourceRegions.map(\.page) }).count) pages")
    }
}
