// Measures text contrast on Nightwatch's live popover glass (v0.4 spec §7).
//
// Usage: swift scripts/contrast.swift [--wait SECONDS]
//
// Open the popover first, ideally over a white window (the worst case). Or pass --wait to poll every two seconds for
// the popover to open. The script captures the popover window alone (screencapture -l, no clicks). It samples the
// bare glass in the 16 pt side padding, where no content is drawn, and prints each text token's worst WCAG 2.1 ratio
// against it. It exits 1 when any token falls under 4.5:1, and 2 when no popover is found.
import AppKit
import CoreGraphics

let tokens: [(name: String, hex: UInt32)] = [("text.primary", 0xE8EAEF), ("text.secondary", 0xA8AEBE), ("status.warning", 0xEDB40D)]

func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
func lum(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }
func lum(_ hex: UInt32) -> Double { lum(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255) }
func ratio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }

/// The popover: an on-screen Nightwatch window about 360 pt wide with no title (the Targets, Settings and About windows have one).
func popover() -> (id: Int, bounds: CGRect)? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where (w[kCGWindowOwnerName as String] as? String) == "Nightwatch" {
        guard let id = w[kCGWindowNumber as String] as? Int, let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let width = b["Width"], let height = b["Height"], abs(width - 360) < 40, height > 300,
              ((w[kCGWindowName as String] as? String) ?? "").isEmpty else { continue }
        return (id, CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: width, height: height))
    }
    return nil
}

var wait = 0.0
if let i = CommandLine.arguments.firstIndex(of: "--wait"), i + 1 < CommandLine.arguments.count { wait = Double(CommandLine.arguments[i + 1]) ?? 0 }
let deadline = Date().addingTimeInterval(wait)
var found = popover()
while found == nil, Date() < deadline { Thread.sleep(forTimeInterval: 2); found = popover() }
guard let (id, bounds) = found else { print("No Nightwatch popover on screen. Open it (click the menu-bar star) and run again."); exit(2) }

let path = NSTemporaryDirectory() + "nightwatch-popover.png"
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-o", "-l", String(id), path]
try p.run(); p.waitUntilExit()
guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Capture failed: grant Screen Recording to the terminal in System Settings › Privacy & Security."); exit(2)
}
let rep = NSBitmapImageRep(cgImage: cg)
let scale = Double(rep.pixelsWide) / bounds.width

// Bare glass: 4–12 pt in from each side, over the middle 80 % of the height. The hairline edge and the content stay out.
var darkest = (l: 2.0, hex: ""), lightest = (l: -1.0, hex: "")
for side in [4.0, bounds.width - 12] {
    for xPt in stride(from: side, to: side + 8, by: 2) {
        for yPt in stride(from: bounds.height * 0.1, to: bounds.height * 0.9, by: 4) {
            guard let c = rep.colorAt(x: Int(xPt * scale), y: Int(yPt * scale))?.usingColorSpace(.sRGB) else { continue }
            let l = lum(c.redComponent, c.greenComponent, c.blueComponent)
            let hex = String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
            if l < darkest.l { darkest = (l, hex) }
            if l > lightest.l { lightest = (l, hex) }
        }
    }
}
print("Glass background sampled: darkest #\(darkest.hex), lightest #\(lightest.hex)")
var failed = false
for t in tokens {
    let worst = min(ratio(lum(t.hex), darkest.l), ratio(lum(t.hex), lightest.l))
    print(String(format: "%-15@ worst %.2f:1  %@", t.name as NSString, worst, worst >= 4.5 ? "pass" : "FAIL (needs 4.5:1)"))
    if worst < 4.5 { failed = true }
}
exit(failed ? 1 : 0)
