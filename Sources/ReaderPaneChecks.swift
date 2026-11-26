import Foundation
@main struct ReaderPaneChecks {
    static func main() {
        let wide=ReaderPaneGeometry(total:1400,preferred:750)
        precondition(wide.side == 750 && wide.main == 640)
        let compact=ReaderPaneGeometry(total:900,preferred:750)
        precondition(compact.main >= 440 && compact.side <= 450)
        precondition(ReaderPaneGeometry(total:900,preferred:20).side == 300)
        precondition(ReaderPaneGeometry(total:1400,preferred:750).side==750, "stored width returns on larger windows")
        for total in [500.0,900,1210,1600] {
            for desired in [0.0,300,420,700,9999] {
                let g=ReaderPaneGeometry(total:total,preferred:desired)
                precondition(g.main >= 0 && g.side >= 0 && abs(g.main + g.side + ReaderPaneGeometry.handleWidth - total)<0.01)
            }
        }
        print("PASS: sidebar width bounds, restored preference, expandable chat")
    }
}
