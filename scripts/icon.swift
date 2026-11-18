import AppKit
let folder = URL(fileURLWithPath: "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        let box = NSBezierPath(roundedRect: NSRect(x: 65, y: 65, width: 894, height: 894), xRadius: 200, yRadius: 200)
        NSColor(srgbRed: 0.12, green: 0.33, blue: 0.70, alpha: 1).setFill()
        box.fill()
        NSColor.white.setStroke()
        let lens = NSBezierPath(ovalIn: NSRect(x: 244, y: 376, width: 392, height: 392))
        lens.lineWidth = 56
        lens.stroke()
        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: 582, y: 438))
        handle.line(to: NSPoint(x: 748, y: 272))
        handle.lineWidth = 56
        handle.lineCapStyle = .round
        handle.stroke()
        // The lens contains a file list, with the shorter final line marking its end.
        let rows = NSBezierPath()
        for (y, endX) in [(636.0, 520.0), (572, 520), (508, 472)] {
            rows.move(to: NSPoint(x: 360, y: y))
            rows.line(to: NSPoint(x: endX, y: y))
        }
        rows.lineWidth = 28
        rows.lineCapStyle = .round
        rows.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); process.arguments = ["-c", "icns", folder.path, "-o", "build/AppIcon.icns"]
try process.run(); process.waitUntilExit()
if process.terminationStatus != 0 { exit(process.terminationStatus) }
