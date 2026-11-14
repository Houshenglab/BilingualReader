import AppKit
import SwiftUI

struct ShelfScrollAccumulator {
    private var distance: Double = 0
    private var lastTimestamp: TimeInterval = 0
    private var horizontalGesture: Bool?
    private var initialX: Double = 0
    private var initialY: Double = 0
    private mutating func reset() {
        distance = 0; horizontalGesture = nil; initialX = 0; initialY = 0
    }
    mutating func consume(horizontal x: Double, vertical y: Double, precise: Bool,
                          phase: NSEvent.Phase, momentum: NSEvent.Phase, timestamp: TimeInterval) -> Int {
        if phase.contains(.began) || (phase.isEmpty && timestamp - lastTimestamp > 0.25) { reset() }
        lastTimestamp = timestamp
        guard momentum.isEmpty else { reset(); return 0 }
        if phase.contains(.ended) || phase.contains(.cancelled) { reset(); return 0 }
        var movement = x
        if horizontalGesture == nil {
            initialX += x; initialY += y
            guard max(abs(initialX), abs(initialY)) >= (precise ? 8 : 1) else { return 0 }
            horizontalGesture = abs(initialX) > abs(initialY)
            movement = initialX
        }
        guard horizontalGesture == true else { return 0 }
        // AppKit deltas already follow the system's natural scrolling preference.
        if distance * movement < 0 { distance = 0 }
        distance += movement * (precise ? 1 : 10)
        let steps = max(-3, min(3, Int(distance / 70)))
        distance -= Double(steps) * 70
        return -steps
    }
}

struct ShelfScrollInput: NSViewRepresentable {
    var onMove: (Int) -> Void
    func makeNSView(context: Context) -> ShelfScrollView {
        let view = ShelfScrollView()
        view.onMove = onMove
        return view
    }
    func updateNSView(_ view: ShelfScrollView, context: Context) { view.onMove = onMove }
    static func dismantleNSView(_ view: ShelfScrollView, coordinator: ()) { view.stopMonitoring() }
}

final class ShelfScrollView: NSView {
    var onMove: ((Int) -> Void)?
    private var monitor: Any?
    private var accumulator = ShelfScrollAccumulator()
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.acceptsScroll(at: event.locationInWindow, window: event.window) else { return event }
            let step = self.accumulator.consume(horizontal: event.scrollingDeltaX, vertical: event.scrollingDeltaY,
                                                precise: event.hasPreciseScrollingDeltas, phase: event.phase,
                                                momentum: event.momentumPhase, timestamp: event.timestamp)
            if step != 0 { self.onMove?(step) }
            return abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? nil : event
        }
    }
    func acceptsScroll(at point: NSPoint, window eventWindow: NSWindow?) -> Bool {
        guard let window, eventWindow === window, !isHiddenOrHasHiddenAncestor else { return false }
        return bounds.intersection(visibleRect).contains(convert(point, from: nil))
    }
    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        accumulator = ShelfScrollAccumulator()
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
