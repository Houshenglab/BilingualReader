import AppKit
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 208, yRadius: 208)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.20); shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.set()
NSColor.systemBlue.setFill(); tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [NSColor(calibratedRed: 0.07, green: 0.18, blue: 0.50, alpha: 1), NSColor(calibratedRed: 0.20, green: 0.49, blue: 0.96, alpha: 1)])!.draw(in: tile, angle: 75)
let glow = NSBezierPath(ovalIn: NSRect(x: 280, y: 430, width: 780, height: 690))
NSGraphicsContext.saveGraphicsState(); tile.addClip()
NSColor.white.withAlphaComponent(0.07).setFill(); glow.fill(); NSGraphicsContext.restoreGraphicsState()
func page(_ left: Bool) -> NSBezierPath {
    let p = NSBezierPath()
    if left {
        p.move(to: NSPoint(x: 506,y: 300)); p.curve(to: NSPoint(x: 242,y: 332),controlPoint1: NSPoint(x: 405,y: 344),controlPoint2: NSPoint(x: 335,y: 354)); p.line(to: NSPoint(x: 242,y: 710)); p.curve(to: NSPoint(x: 506,y: 676),controlPoint1: NSPoint(x: 335,y: 739),controlPoint2: NSPoint(x: 426,y: 723))
    } else {
        p.move(to: NSPoint(x: 518,y: 300)); p.curve(to: NSPoint(x: 782,y: 332),controlPoint1: NSPoint(x: 619,y: 344),controlPoint2: NSPoint(x: 689,y: 354)); p.line(to: NSPoint(x: 782,y: 710)); p.curve(to: NSPoint(x: 518,y: 676),controlPoint1: NSPoint(x: 689,y: 739),controlPoint2: NSPoint(x: 598,y: 723))
    }; p.close(); return p
}
NSGraphicsContext.saveGraphicsState(); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0,height: -14); shadow.set()
NSColor(calibratedWhite: 0.99,alpha: 1).setFill(); page(true).fill(); page(false).fill(); NSGraphicsContext.restoreGraphicsState()
func text(_ value: String, _ x: CGFloat, _ y: CGFloat) {
    (value as NSString).draw(at: NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:148,weight:.semibold),.foregroundColor:NSColor(calibratedRed:0.16,green:0.34,blue:0.71,alpha:1)])
}
text("A",322,485); text("中",562,485)
for x: CGFloat in [306,574] {
    for (y,w): (CGFloat,CGFloat) in [(440,144),(402,110)] {
        NSColor(calibratedRed:0.27,green:0.48,blue:0.86,alpha:0.35).setFill()
        NSBezierPath(roundedRect:NSRect(x:x,y:y,width:w,height:12),xRadius:6,yRadius:6).fill()
    }
}
image.unlockFocus()
let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
try rep.representation(using:.png,properties:[:])!.write(to: URL(fileURLWithPath:"Resources/AppIcon.png"))
