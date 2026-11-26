import Foundation

/// Fit the whole visible group in the stage, including at the first/last book.
struct ShelfGeometry {
    let indices: Range<Int>
    let coverHeight: CGFloat
    let coverWidth: CGFloat
    let step: CGFloat
    init(count: Int, selected: Int, width: CGFloat, height: CGFloat) {
        let capacity = min(count, width < 650 ? 5 : 7)
        let start = max(0, min(max(0, count - capacity), selected - capacity / 2))
        indices = start..<(start + capacity)
        coverHeight = max(1, min(330, height - 44, width * 0.78))
        coverWidth = coverHeight * 190 / 265
        let available = max(0, width - coverWidth * 1.08 - 36)
        step = capacity <= 1 ? 0 : min(coverWidth * 0.91, available / CGFloat(capacity - 1))
    }
    func x(for index: Int) -> CGFloat {
        (CGFloat(index - indices.lowerBound) - CGFloat(max(0, indices.count - 1)) / 2) * step
    }
}
