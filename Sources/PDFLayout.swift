import Foundation
import PDFKit

struct PDFSourceRegion: Codable {
    let page: Int
    let bounds: CGRect
}

// Geometry remains attached to text, so both reading modes share the same blocks.
enum PDFLayout {
    struct Line {
        var text: String
        var bounds: CGRect
        var fontSize: CGFloat? = nil
        var fontName: String? = nil
    }
    struct Block {
        var text: String
        var regions: [PDFSourceRegion]
        var kind: String
        var height: CGFloat
        var indented: Bool
        var pageBounds: CGRect = .zero
        var columnBounds: CGRect = .zero
    }
    static func join(_ lhs: String, _ rhs: String) -> String {
        if ["-", "‐", "‑", "\u{00ad}"].contains(where: { lhs.hasSuffix($0) }), rhs.first?.isLowercase == true { return String(lhs.dropLast()) + rhs }
        return lhs + (lhs.isEmpty ? "" : " ") + rhs
    }
    static func endsSentence(_ text: String) -> Bool {
        text.range(of: #"[.!?。！？][\"”’')\]\d,–−]*$"#, options: .regularExpression) != nil
    }
    static func document(_ pdf: PDFDocument, sourceURL: URL, cancellation: PDFExtractionCancellation? = nil) throws -> [ReadingParagraph] {
        let pages = try PDFMinerEngine.extract(sourceURL, cancellation: cancellation)
        // Repeated publisher furniture may sit well below the top margin when
        // the manuscript is embedded in a smaller page-sized Form XObject.
        var headerPages: [String: Set<Int>] = [:]
        for data in pages {
            guard let page = pdf.page(at: data.number - 1) else { continue }
            let frame = page.bounds(for: .cropBox)
            for box in data.boxes {
                let text = box.lines.map(\.text).joined(separator: " ")
                let bounds = box.lines.reduce(CGRect.null) { $0.union(PDFMinerEngine.sourceBounds($1.bounds, page: page)) }
                if text.count < 300, bounds.minY > frame.minY + frame.height * 0.75 {
                    headerPages[text, default: []].insert(data.number)
                }
            }
        }
        let repeatedHeaders = Set(headerPages.filter { $0.value.count >= max(3, (pages.count + 1) / 2) }.map(\.key))
        var all: [Block] = []
        for data in pages {
            guard let page = pdf.page(at: data.number - 1) else { continue }
            var blocks: [Block] = []
            let sizes = data.boxes.flatMap(\.lines).filter { $0.text.count > 35 }.compactMap(\.fontSize).sorted()
            let bodyFont = CGFloat(sizes.isEmpty ? 10 : sizes[sizes.count / 2])
            for box in data.boxes {
                let lines = box.lines.compactMap { item -> Line? in
                    let bounds = PDFMinerEngine.sourceBounds(item.bounds, page: page)
                    guard bounds.width > 0, bounds.height > 0, bounds.isFinite else { return nil }
                    return Line(text: item.text, bounds: bounds, fontSize: item.fontSize.map { CGFloat($0) }, fontName: item.fontName)
                }
                guard !lines.isEmpty else { continue }
                let union = lines.reduce(CGRect.null) { $0.union($1.bounds) }
                let frame = page.bounds(for: .cropBox)
                // Page furniture is not a body paragraph. Figures stay on the original PDF.
                if union.maxY < frame.minY + frame.height * 0.04 { continue }
                let footnote = union.minY < frame.minY + frame.height * 0.12 && lines.count <= 4
                    && lines.contains { $0.text.contains("University") || $0.text.contains("Laboratory") || $0.text.contains("e-mail:") }
                let repeatedHeader = union.minY > frame.minY + frame.height * 0.75
                    && repeatedHeaders.contains(box.lines.map(\.text).joined(separator: " "))
                let kind = footnote || repeatedHeader || union.minY > frame.minY + frame.height * 0.95 ? "metadata" : "body"
                blocks += paragraphs(in: lines, page: data.number, kind: kind).map { block in
                    var value = block
                    if box.isArtwork == true { value.kind = "figure" }
                    value.pageBounds = frame
                    let averageWidth = value.regions.map { $0.bounds.width }.reduce(0, +) / CGFloat(max(1, value.regions.count))
                    if value.kind == "body", value.height < bodyFont * 0.85, averageWidth < frame.width * 0.25 { value.kind = "figure" }
                    return value
                }
            }
            // Estimate the actual text-column extent, including body below a figure or abstract.
            let bodyRegions = blocks.filter { $0.kind == "body" && $0.regions.count >= 3 }.flatMap(\.regions)
            for index in blocks.indices {
                guard let edge = blocks[index].regions.first else { continue }
                let left = blocks[index].regions.map { $0.bounds.minX }.min() ?? edge.bounds.minX
                let matching = bodyRegions.filter { abs($0.bounds.minX - left) < blocks[index].height * 3 && $0.bounds.width > edge.bounds.width * 0.55 }
                blocks[index].columnBounds = matching.reduce(CGRect.null) { $0.union($1.bounds) }
            }
            // Text-box order is supplied by pdfminer; join only a clearly continued body block.
            var next: [Block] = []
            for block in blocks {
                if let previous = next.last, canContinue(previous, block) {
                    next[next.count - 1].text = join(previous.text, block.text)
                    next[next.count - 1].regions += block.regions
                    next[next.count - 1].pageBounds = block.pageBounds
                    next[next.count - 1].columnBounds = block.columnBounds
                } else { next.append(block) }
            }
            if let last = all.lastIndex(where: { $0.kind == "body" }),
               let first = next.firstIndex(where: { $0.kind == "body" }),
               all[last].regions.last?.page == data.number - 1,
               all.suffix(from: last + 1).allSatisfy({ ["metadata", "figure", "caption"].contains($0.kind) }),
               next.prefix(first).allSatisfy({ ["metadata", "figure", "caption"].contains($0.kind) }),
               canContinue(all[last], next[first]) {
                all[last].text = join(all[last].text, next[first].text)
                all[last].regions += next[first].regions
                all[last].pageBounds = next[first].pageBounds
                all[last].columnBounds = next[first].columnBounds
                all += next.enumerated().filter { $0.offset != first }.map(\.element)
            } else { all += next }
        }
        return all.enumerated().map { ReadingParagraph(id: $0.offset, text: $0.element.text,
            page: $0.element.regions.first?.page, sourceRegions: $0.element.regions, kind: $0.element.kind) }
    }
    static func merge(_ values: [ReadingParagraph], first: Int, second: Int) -> [ReadingParagraph] {
        guard values.indices.contains(first), values.indices.contains(second), first != second else { return values }
        let low = min(first, second), high = max(first, second)
        let a = values[low], b = values[high]
        var result = values
        result[low] = ReadingParagraph(id: low, text: join(a.text, b.text), page: a.page,
            sourceRegions: a.sourceRegions + b.sourceRegions, kind: a.kind)
        result.remove(at: high)
        return result.enumerated().map { index, p in
            ReadingParagraph(id: index, text: p.text, page: p.page, sourceRegions: p.sourceRegions,
                kind: p.kind, translation: p.translation, expanded: p.expanded, loading: false, error: p.error)
        }
    }
    static func canContinue(_ a: Block, _ b: Block) -> Bool {
        guard a.kind == "body", b.kind == "body", !endsSentence(a.text), !b.indented,
              b.text.first?.isLowercase == true,
              abs(a.height - b.height) < max(a.height, b.height) * 0.35,
              let last = a.regions.last, let first = b.regions.first else { return false }
        let height = max(a.height, b.height)
        if last.page == first.page {
            let leftA = a.regions.filter { $0.page == last.page }.map { $0.bounds.minX }.min() ?? last.bounds.minX
            let leftB = b.regions.filter { $0.page == first.page }.map { $0.bounds.minX }.min() ?? first.bounds.minX
            let sameColumn = abs(leftA - leftB) < height * 2
            let gap = last.bounds.minY - first.bounds.maxY
            if sameColumn { return gap >= -height * 0.5 && gap <= height * 1.2 }
            // A new column must begin above the previous column's end, near page edges.
            guard !a.pageBounds.isEmpty, !b.pageBounds.isEmpty else { return false }
            return leftB > leftA + height * 6 &&
                last.bounds.minY <= (a.columnBounds.isEmpty ? a.pageBounds.minY + a.pageBounds.height * 0.28 : a.columnBounds.minY + height * 2) &&
                first.bounds.maxY >= (b.columnBounds.isEmpty ? b.pageBounds.minY + b.pageBounds.height * 0.65 : b.columnBounds.maxY - height * 2) && first.bounds.minY > last.bounds.maxY + height * 3
        }
        guard first.page == last.page + 1, !a.pageBounds.isEmpty, !b.pageBounds.isEmpty else { return false }
        return last.bounds.minY <= (a.columnBounds.isEmpty ? a.pageBounds.minY + a.pageBounds.height * 0.28 : a.columnBounds.minY + height * 2) &&
            first.bounds.maxY >= (b.columnBounds.isEmpty ? b.pageBounds.minY + b.pageBounds.height * 0.65 : b.columnBounds.maxY - height * 2)
    }
    static func isHeading(_ text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = clean.replacingOccurrences(of: #"^\d+(?:\.\d+)*[.\s]+"#, with: "", options: .regularExpression).lowercased()
        return ["abstract", "introduction", "background", "results", "discussion", "conclusions", "conclusion", "methods", "methodology", "materials and methods", "results and discussion", "references", "online content", "data availability", "code availability", "acknowledgements", "acknowledgments", "author contributions", "supporting information", "supplementary information"].contains(normalized)
    }
    static func paragraphs(in lines: [Line], page: Int, kind: String) -> [Block] {
        guard !lines.isEmpty else { return [] }
        let maxWidth = lines.map { $0.bounds.width }.max()!
        // Estimate the body alignment from recurring long lines, not the leftmost
        // figure label or a single equation in the column.
        let longLines = lines.filter { $0.bounds.width >= maxWidth * 0.55 }
        let alignments = Dictionary(grouping: longLines, by: { Int(($0.bounds.minX / 2).rounded()) })
        let best = alignments.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            return $0.key < $1.key
        }.first?.value ?? lines
        let base = best.map { $0.bounds.minX }.sorted()[best.count / 2]
        let heights = lines.map { $0.fontSize ?? $0.bounds.height }.sorted()
        let typicalHeight = heights[heights.count / 2]
        let indentThreshold = max(6, typicalHeight * 0.65)
        let distances = zip(lines, lines.dropFirst()).map { $0.bounds.minY - $1.bounds.minY }.filter { $0 > typicalHeight * 0.7 && $0 < typicalHeight * 3 }.sorted()
        let leading = distances.count >= 2 ? distances[distances.count / 3] : typicalHeight * 1.35
        func heading(_ line: Line) -> Bool {
            guard line.text.range(of: "[A-Za-z]{3,}", options: .regularExpression) != nil else { return false }
            return isHeading(line.text) || (((line.fontSize ?? line.bounds.height) > typicalHeight * 1.3 || (line.fontSize ?? line.bounds.height) >= 18) && line.text.count < 100 && !endsSentence(line.text))
                || (line.fontName?.lowercased().contains("bold") == true && line.text.count < 75 && !endsSentence(line.text) && maxWidth < 200 && lines.count <= 2 && line.bounds.width > typicalHeight * 3)
        }
        var result: [Block] = []
        var current: Block?
        var previous: Line?
        var inReferences = false
        for line in lines {
            let indent = line.bounds.minX > base + indentThreshold
            let isTitle = heading(line)
            let reference = line.text.range(of: #"^\d{1,3}\.\s+\S"#, options: .regularExpression) != nil
            let keyword = line.text.hasPrefix("KEYWORDS:") || line.text.hasPrefix("Keywords:")
            let caption = line.text.range(of: #"^(Fig\.?|Figure|Table)\s*\d"#, options: .regularExpression) != nil
            var starts = false
            if let prev = previous {
                let previousIndented = prev.bounds.minX > base + indentThreshold
                // Only the transition into a first-line indent is a paragraph start.
                // Uniformly indented wrapped lines and hanging references stay together.
                let firstLineIndent = indent && !previousIndented && !inReferences
                    && line.bounds.minX - prev.bounds.minX < typicalHeight * 3
                let fontChange = (prev.bounds.height > typicalHeight * 1.5 || line.bounds.height > typicalHeight * 1.5) && abs(prev.bounds.height - line.bounds.height) > typicalHeight * 0.45
                let paragraphGap = prev.bounds.minY - line.bounds.minY > max(leading * 1.65, typicalHeight * 2)
                starts = reference || caption || keyword || firstLineIndent || fontChange || paragraphGap || (isTitle != heading(prev)) || isHeading(line.text)
            }
            if starts, let block = current { result.append(block); current = nil }
            if current == nil {
                current = Block(text: "", regions: [], kind: isTitle ? "heading" : keyword ? "metadata" : reference ? "reference" : caption ? "caption" : kind,
                                height: typicalHeight, indented: indent)
                inReferences = reference
            }
            current!.text = join(current!.text, line.text)
            current!.regions.append(PDFSourceRegion(page: page, bounds: line.bounds))
            previous = line
        }
        if let current { result.append(current) }
        return result.map { block in
            var value = block
            let averageWidth = block.regions.map { $0.bounds.width }.reduce(0, +) / CGFloat(max(1, block.regions.count))
            if isHeading(value.text) {
                value.kind = "heading"
            } else if value.kind == "body" {
                let hasWords = value.text.range(of: "[A-Za-z]{3,}", options: .regularExpression) != nil
                let affiliation = value.text.localizedCaseInsensitiveContains("e-mail:") || value.text.localizedCaseInsensitiveContains("email:")
                if affiliation { value.kind = "metadata" }
                else if !hasWords { value.kind = "figure" }
                else if averageWidth < 120 && !endsSentence(value.text) && block.regions.count <= 2 && value.text.split(separator: " ").count < 8 { value.kind = "metadata" }
            }
            return value
        }
    }

}
private extension CGRect {
    var isFinite: Bool { origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite }
}
