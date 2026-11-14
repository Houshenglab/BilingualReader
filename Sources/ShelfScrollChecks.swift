import AppKit
final class ScrollSample: NSEvent {
 let target: NSWindow
 init(_ target:NSWindow) { self.target = target; super.init() }
 required init?(coder:NSCoder) { fatalError() }
 override var type: NSEvent.EventType { .scrollWheel }
 override var window: NSWindow? { target }
 override var locationInWindow: NSPoint { NSPoint(x:100,y:100) }
 override var scrollingDeltaX: CGFloat { -90 }
 override var scrollingDeltaY: CGFloat { 0 }
 override var hasPreciseScrollingDeltas: Bool { true }
 override var phase: NSEvent.Phase { .began }
 override var momentumPhase: NSEvent.Phase { [] }
}

@main struct ShelfScrollChecks {
 @MainActor static func main() {
  var scroll = ShelfScrollAccumulator()
  func sample(_ x: Double, _ y: Double = 0, phase: NSEvent.Phase = .changed, momentum: NSEvent.Phase = [], time: Double = 1) -> Int {
   scroll.consume(horizontal: x, vertical: y, precise: true, phase: phase, momentum: momentum, timestamp: time)
  }
  precondition(sample(-30, phase:.began) == 0)
  precondition(sample(-45) == 1, "Small horizontal events must accumulate into next book")
  precondition(sample(80, phase:.began) == -1, "Reverse gesture must select previous book")
  precondition(sample(-120, 160, phase:.began) == 0, "Vertical scrolling must not navigate shelf")
  precondition(sample(-200, momentum:.changed) == 0, "Momentum must not run away through books")
  precondition(sample(-50, phase:.began) == 0)
  precondition(sample(0, phase:.ended) == 0)
  precondition(sample(-30, phase:.began) == 0, "New gesture must not inherit old distance")
  precondition(sample(-30, phase:[], time:3) == 0, "Idle gaps reset phased-less events")
  precondition(sample(-45, phase:[], time:3.01) == 1)
  precondition(sample(-10, -160, phase:.began, time:4) == 0)
  for index in 0..<8 {
   precondition(sample(-10, -5, time:4 + Double(index + 1) * 0.01) == 0, "Vertical gesture drift must never turn books")
  }
  _ = NSApplication.shared
  let window = NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:500), styleMask:[.titled], backing:.buffered, defer:false)
  let view = ShelfScrollView(frame:NSRect(x:50,y:50,width:300,height:300))
  window.contentView!.addSubview(view)
  precondition(view.acceptsScroll(at:NSPoint(x:100,y:100),window:window))
  precondition(!view.acceptsScroll(at:NSPoint(x:400,y:400),window:window), "Shelf must not swallow scroll outside its bounds")
  precondition(!view.acceptsScroll(at:NSPoint(x:100,y:100),window:nil), "Shelf must not swallow another window's scroll")
  var movement = 0
  view.onMove = { movement += $0 }
  NSApp.sendEvent(ScrollSample(window))
  precondition(movement == 1, "A native scroll-wheel event must reach the shelf callback")
  view.isHidden = true
  precondition(!view.acceptsScroll(at:NSPoint(x:100,y:100),window:window))
  view.isHidden = false
  view.stopMonitoring()
  NSApp.sendEvent(ScrollSample(window))
  precondition(movement == 1, "Dismantled shelf must remove its event monitor")
  print("PASS: horizontal two-finger accumulation/direction, vertical isolation, momentum suppression and gesture reset")
 }
}
