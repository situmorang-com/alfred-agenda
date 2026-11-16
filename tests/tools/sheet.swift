// sheet — lays tile images out the way Alfred's Grid View shows them (rounded cells on the
// window background), so month and week tiles can be checked without opening Alfred.
//
//   sheet <out.png> <columns> <cell width in points> <light|dark> <tile.png>…
//
// Output is drawn at 2x, like a Retina screen.

import AppKit

let args = CommandLine.arguments
guard args.count > 5, let columns = Int(args[2]), let cellWidth = Double(args[3]) else {
    FileHandle.standardError.write(Data("usage: sheet <out.png> <columns> <cell width> <light|dark> <tile.png>…\n".utf8))
    exit(2)
}
let dark = args[4] == "dark"
let tiles = args.dropFirst(5).compactMap { NSImage(contentsOfFile: $0) }
guard let first = tiles.first else { exit(1) }

let scale = 2.0, gap = 8.0, pad = 12.0, inset = 6.0
let cellHeight = (cellWidth * first.size.height / first.size.width).rounded()
let rows = (tiles.count + columns - 1) / columns
let width = pad * 2 + Double(columns) * cellWidth + Double(columns - 1) * gap
let height = pad * 2 + Double(rows) * cellHeight + Double(rows - 1) * gap

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

(dark ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1) : NSColor(srgbRed: 0.84, green: 0.85, blue: 0.86, alpha: 1)).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
let cell = dark ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.06)

for (index, tile) in tiles.enumerated() {
    let row = index / columns, column = index % columns
    let frame = NSRect(x: pad + Double(column) * (cellWidth + gap),
                       y: height - pad - Double(row + 1) * cellHeight - Double(row) * gap,
                       width: cellWidth, height: cellHeight)
    cell.setFill()
    NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10).fill()
    tile.draw(in: frame.insetBy(dx: inset, dy: inset * cellHeight / cellWidth), from: .zero, operation: .sourceOver, fraction: 1)
}
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[1]))
