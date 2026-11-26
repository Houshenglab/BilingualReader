import Foundation
@main struct ShelfGeometryChecks {
    static func main() {
        for width in [500.0, 850, 1200] {
            for height in [170.0, 300, 500] {
                for count in [1,3,5,12] {
                    for selected in [0,count/2,count-1] {
                        let layout = ShelfGeometry(count:count, selected:selected, width:width,height:height)
                        precondition(layout.indices.contains(selected))
                        precondition(layout.coverHeight < height)
                        precondition(layout.coverWidth > 0)
                        let positions=layout.indices.map { layout.x(for:$0) }
                        precondition(abs((positions.first!+positions.last!)/2)<0.01, "Visible group must be centered even at either end")
                        precondition((positions.last!-positions.first!)+layout.coverWidth*1.08 <= width, "Book group cannot clip horizontally")
                    }
                }
            }
        }
        print("PASS: wide, compact and edge-selected shelf layouts")
    }
}
