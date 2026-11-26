import Foundation

/// A stored preferred sidebar width is clamped to the current window, not overwritten when the window shrinks.
struct ReaderPaneGeometry {
    static let handleWidth: CGFloat = 10
    let main: CGFloat
    let side: CGFloat
    init(total: CGFloat, preferred: Double) {
        let usable = max(0, total - Self.handleWidth)
        let minimumSide = min(300, usable)
        let minimumMain = min(440, max(0, usable - minimumSide))
        let wanted = preferred.isFinite ? CGFloat(preferred) : 420
        side = min(max(minimumSide, wanted), usable - minimumMain)
        main = usable - side
    }
}
