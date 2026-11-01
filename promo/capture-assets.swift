// Captures the real panel and icon frames used by the promo video (run via promo/make-assets.sh).
import AppKit
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
let out = CommandLine.arguments[1]
let booster = Booster()
booster.factor = 2.0
let v = PanelView(frame: NSRect(x: 0, y: 0, width: PanelView.width, height: PanelView.height))
v.booster = booster
func shot(_ name: String) {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: Int(PanelView.height) * 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = v.bounds.size
  v.cacheDisplay(in: v.bounds, to: rep)
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/" + name + ".png"))
}
// the icon, lit, as it plays in the menu bar
for i in 0..<48 {
  let img = GhostArt.lit(t: Double(i) / 8, fade: 1)
  let rep = img.representations[0] as! NSBitmapImageRep
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: String(format: "%@/icon%03d.png", out, i)))
}
let off = GhostArt.off
let big = NSImage(size: NSSize(width: 52, height: 52), flipped: false) { r in off.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true }
try! NSBitmapImageRep(data: big.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/icon_off.png"))
booster.enabled = false
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
shot("off")
booster.enabled = true
let start = Date()
for i in 0..<92 {
  RunLoop.main.run(until: start.addingTimeInterval(Double(i) * 0.05))
  shot(String(format: "on%03d", i))
}
booster.enabled = false
