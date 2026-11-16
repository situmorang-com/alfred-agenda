// demo — draws the frames of docs/images/demo.gif: Agenda's views in an Alfred-style window on
// a desktop, filled with the workflow's own rows and tiles for the made-up calendar (never the
// real one). tests/demo.sh sets that calendar up, runs this from the workflow folder, and turns
// the frames into the GIF.
//
//   demo <frames folder>      writes frame-NNN.png and frames.txt (ffmpeg's concat list)

import AppKit

let canvas = NSSize(width: 1040, height: 800)
let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "frames")
let workflow = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// MARK: - The workflow's own rows and tiles

typealias Item = [String: Any]

/// Runs a view of `bin/agenda`, with British English formats (10:00, Fri 13 Nov).
func agenda(_ view: String, _ query: String = "", _ extra: [String: String] = [:]) -> (items: [Item], preselect: String?) {
    let process = Process()
    process.executableURL = workflow.appendingPathComponent("bin/agenda")
    process.arguments = [view, query, "-AppleLocale", "en_GB"]
    process.environment = ProcessInfo.processInfo.environment.merging(extra) { $1 }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    return (json["items"] as? [Item] ?? [], json["preselect"] as? String)
}

var loaded: [String: NSImage] = [:]
func picture(_ path: String) -> NSImage? {
    if let image = loaded[path] { return image }
    let image = NSImage(contentsOfFile: path)
    loaded[path] = image
    return image
}
func picture(of item: Item) -> NSImage? {
    guard let path = (item["icon"] as? [String: Any])?["path"] as? String else { return nil }
    return picture(path.hasPrefix("/") ? path : workflow.appendingPathComponent(path).path)
}

// MARK: - What a frame shows

enum Content {
    case search                                        // only the search field
    case list([Item], selected: Int)
    case grid([Item], selected: Int, aspect: CGFloat)  // aspect: cell height over width
}

struct Frame {
    var seconds: Double
    var caption: String? = nil
    var clock = "09:56"
    var query: String? = nil         // nil: Alfred is closed
    var content = Content.search
    var key: String? = nil           // a keystroke, shown in a pill under the window
    var appear: CGFloat = 1          // 0 → 1 while the window pops up
    var titleCard = false
}

// MARK: - Drawing helpers (the context is flipped: y grows downwards)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular, rounded: Bool = false) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard rounded, let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func write(_ string: String, _ font: NSFont, _ color: NSColor, in rect: NSRect, align: NSTextAlignment = .left, shadow: NSShadow? = nil) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineBreakMode = .byTruncatingTail
    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
    if let shadow { attributes[.shadow] = shadow }
    NSAttributedString(string: string, attributes: attributes).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
}

func widthOf(_ string: String, _ font: NSFont) -> CGFloat { (string as NSString).size(withAttributes: [.font: font]).width }

func place(_ image: NSImage?, in rect: NSRect, alpha: CGFloat = 1) {
    image?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
}

func fill(_ path: NSBezierPath, _ color: NSColor) {
    color.setFill()
    path.fill()
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius) }

func softShadow(_ alpha: CGFloat, blur: CGFloat, down: CGFloat) -> NSShadow {
    let shadow = NSShadow()
    shadow.shadowColor = rgb(0x000000, alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: -down)  // offsets are unflipped: negative is down
    return shadow
}

func symbol(_ name: String, size: CGFloat) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
}

// MARK: - The desktop

func drawDesktop() {
    let whole = NSRect(origin: .zero, size: canvas)
    NSGradient(colors: [rgb(0x1E3FAE), rgb(0x5B3CC4), rgb(0x9A45B8), rgb(0xE0679A)],
               atLocations: [0, 0.38, 0.7, 1], colorSpace: .sRGB)?.draw(in: whole, angle: 35)
    // A soft light behind the window, so it lifts off the wallpaper.
    let centre = NSPoint(x: canvas.width / 2, y: canvas.height * 0.52)
    NSGradient(starting: rgb(0xFFFFFF, 0.22), ending: rgb(0xFFFFFF, 0))?
        .draw(fromCenter: centre, radius: 0, toCenter: centre, radius: 560, options: [])
}

func drawMenuBar(clock: String) {
    fill(NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvas.width, height: 28)), rgb(0xFFFFFF, 0.14))
    let menuFont = font(13.5), bold = font(13.5, .bold)
    write("\u{F8FF}", font(15), .white, in: NSRect(x: 20, y: 5, width: 20, height: 20))
    write("Finder", bold, .white, in: NSRect(x: 48, y: 6, width: 80, height: 20))
    var x = 48 + widthOf("Finder", bold) + 22
    for menu in ["File", "Edit", "View", "Go", "Window", "Help"] {
        write(menu, menuFont, rgb(0xFFFFFF, 0.92), in: NSRect(x: x, y: 6, width: 80, height: 20))
        x += widthOf(menu, menuFont) + 20
    }
    let time = "Fri 13 Nov  \(clock)"
    let timeFont = font(13.5, .medium)
    var right = canvas.width - 20 - widthOf(time, timeFont)
    if clock != "09:56" {  // the alert scene: the minute that matters
        fill(rounded(NSRect(x: right - 8, y: 3, width: widthOf(time, timeFont) + 16, height: 22), 6), rgb(0xFFFFFF, 0.3))
    }
    write(time, timeFont, .white, in: NSRect(x: right, y: 6, width: 200, height: 20))
    for name in ["switch.2", "magnifyingglass", "wifi", "battery.75percent"] {
        guard let icon = symbol(name, size: 13) else { continue }
        let size = icon.size
        right -= size.width + 16
        place(icon, in: NSRect(x: right, y: 14 - size.height / 2, width: size.width, height: size.height))
    }
}

func drawCaption(_ caption: String) {
    write(caption, font(31, .semibold, rounded: true), .white, in: NSRect(x: 0, y: 58, width: canvas.width, height: 44),
          align: .center, shadow: softShadow(0.28, blur: 14, down: 2))
}

func drawKey(_ key: String, under bottom: CGFloat) {
    let keyFont = font(17, .semibold, rounded: true)
    let width = max(56, widthOf(key, keyFont) + 34), height: CGFloat = 38
    let rect = NSRect(x: (canvas.width - width) / 2, y: min(bottom + 22, canvas.height - height - 16), width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    softShadow(0.25, blur: 10, down: 3).set()
    fill(rounded(rect, height / 2), rgb(0x0E1430, 0.72))
    NSGraphicsContext.restoreGraphicsState()
    write(key, keyFont, .white, in: rect.insetBy(dx: 4, dy: 8), align: .center)
}

func drawTitleCard() {
    let tile = NSRect(x: canvas.width / 2 - 78, y: 168, width: 156, height: 156)
    NSGraphicsContext.saveGraphicsState()
    softShadow(0.3, blur: 30, down: 12).set()
    fill(rounded(tile, 36), .white)
    NSGraphicsContext.restoreGraphicsState()
    place(picture(workflow.appendingPathComponent("icon.png").path), in: tile.insetBy(dx: 14, dy: 14))

    let glow = softShadow(0.25, blur: 16, down: 2)
    write("Agenda for Alfred", font(56, .bold, rounded: true), .white, in: NSRect(x: 0, y: 352, width: canvas.width, height: 72), align: .center, shadow: glow)
    write("Your calendar, one keystroke away", font(25, .medium, rounded: true), rgb(0xFFFFFF, 0.9),
          in: NSRect(x: 0, y: 432, width: canvas.width, height: 36), align: .center, shadow: glow)

    let chips = ["Next meeting", "Day", "Week", "Month", "Add & delete", "Join on time"]
    let chipFont = font(16, .semibold, rounded: true)
    let widths = chips.map { widthOf($0, chipFont) + 32 }
    var x = (canvas.width - widths.reduce(0, +) - CGFloat(chips.count - 1) * 12) / 2
    for (chip, width) in zip(chips, widths) {
        let rect = NSRect(x: x, y: 512, width: width, height: 36)
        fill(rounded(rect, 18), rgb(0xFFFFFF, 0.18))
        write(chip, chipFont, .white, in: rect.insetBy(dx: 0, dy: 8), align: .center)
        x += width + 12
    }
}

// MARK: - Alfred's window

let windowWidth: CGFloat = 860, windowTop: CGFloat = 126
let searchHeight: CGFloat = 74, rowHeight: CGFloat = 54, visibleRows = 9
let gridPad: CGFloat = 12, gridGap: CGFloat = 8, footerHeight: CGFloat = 56
let ink = rgb(0x1D1D1F), secondary = rgb(0x86868B), faint = rgb(0xAEAEB2), accent = rgb(0x2F7BF5)

func cellWidth() -> CGFloat { (windowWidth - 2 * gridPad - 6 * gridGap) / 7 }

func height(of content: Content) -> CGFloat {
    switch content {
    case .search:
        return searchHeight
    case .list(let items, _):
        return searchHeight + 1 + 6 + CGFloat(min(items.count, visibleRows)) * rowHeight + 6
    case .grid(let items, _, let aspect):
        let rows = CGFloat((items.count + 6) / 7)
        return searchHeight + 1 + 2 * gridPad + rows * cellWidth() * aspect + (rows - 1) * gridGap + footerHeight
    }
}

/// Draws the window and returns where its bottom edge landed on the canvas.
func drawWindow(_ frame: Frame, query: String) -> CGFloat {
    let full = height(of: frame.content)
    // Tall views (the month) shrink to fit; a popping window grows from 97 %.
    let scale = min(1, (canvas.height - windowTop - 22) / full) * (0.97 + 0.03 * frame.appear)
    let origin = NSPoint(x: (canvas.width - windowWidth * scale) / 2, y: windowTop + (1 - frame.appear) * 8)

    guard let cg = NSGraphicsContext.current?.cgContext else { return windowTop }
    NSGraphicsContext.saveGraphicsState()
    cg.setAlpha(frame.appear)
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    let transform = NSAffineTransform()
    transform.translateX(by: origin.x, yBy: origin.y)
    transform.scale(by: scale)
    transform.concat()

    let body = rounded(NSRect(x: 0, y: 0, width: windowWidth, height: full), 16)
    NSGraphicsContext.saveGraphicsState()
    softShadow(0.38, blur: 44, down: 18).set()
    fill(body, .white)
    NSGraphicsContext.restoreGraphicsState()
    rgb(0x000000, 0.08).setStroke()
    body.lineWidth = 1
    body.stroke()
    body.addClip()

    // Search field: the typed text, a caret, and the workflow's icon where Alfred shows its own.
    let queryFont = font(28, .light)
    write(query, queryFont, ink, in: NSRect(x: 24, y: 18, width: windowWidth - 120, height: 40))
    if case .search = frame.content {
        fill(NSBezierPath(rect: NSRect(x: 26 + widthOf(query, queryFont), y: 21, width: 2, height: 33)), accent)
    }
    place(picture(workflow.appendingPathComponent("icon.png").path), in: NSRect(x: windowWidth - 62, y: 15, width: 44, height: 44))

    switch frame.content {
    case .search:
        break
    case .list(let items, let selected):
        fill(NSBezierPath(rect: NSRect(x: 0, y: searchHeight, width: windowWidth, height: 1)), rgb(0xE6E6EB))
        for (index, item) in items.prefix(visibleRows).enumerated() {
            let y = searchHeight + 1 + 6 + CGFloat(index) * rowHeight
            if index == selected {
                fill(rounded(NSRect(x: 8, y: y + 1, width: windowWidth - 16, height: rowHeight - 2), 10), rgb(0xE7EEFA))
            }
            place(picture(of: item), in: NSRect(x: 20, y: y + 9, width: 36, height: 36))
            write(item["title"] as? String ?? "", font(18), ink, in: NSRect(x: 70, y: y + 6, width: windowWidth - 150, height: 24))
            write(item["subtitle"] as? String ?? "", font(13), secondary, in: NSRect(x: 70, y: y + 30, width: windowWidth - 150, height: 18))
            let shortcut = index == selected ? "↩" : "⌘\(index + 1)"
            let shortcutFont = font(14, .medium)
            write(shortcut, shortcutFont, index == selected ? secondary : faint,
                  in: NSRect(x: windowWidth - 70, y: y + 17, width: 50, height: 20), align: .right)
        }
    case .grid(let items, let selected, let aspect):
        let cell = cellWidth()
        fill(NSBezierPath(rect: NSRect(x: 0, y: searchHeight, width: windowWidth, height: 1)), rgb(0xE6E6EB))
        for (index, item) in items.enumerated() {
            let row = CGFloat(index / 7), column = CGFloat(index % 7)
            let rect = NSRect(x: gridPad + column * (cell + gridGap), y: searchHeight + 1 + gridPad + row * (cell * aspect + gridGap),
                              width: cell, height: cell * aspect)
            let shape = rounded(rect, 12)
            fill(shape, index == selected ? rgb(0xD9E5FB) : rgb(0xF1F1F4))
            if index == selected {
                accent.withAlphaComponent(0.9).setStroke()
                shape.lineWidth = 2.5
                shape.stroke()
            }
            place(picture(of: item), in: rect.insetBy(dx: 2, dy: 2))
        }
        let footerTop = full - footerHeight
        fill(NSBezierPath(rect: NSRect(x: 0, y: footerTop, width: windowWidth, height: 1)), rgb(0xE6E6EB))
        let chosen = items.indices.contains(selected) ? items[selected] : [:]
        write(chosen["title"] as? String ?? "", font(15, .semibold), ink, in: NSRect(x: 20, y: footerTop + 9, width: windowWidth - 40, height: 20))
        write(chosen["subtitle"] as? String ?? "", font(13), secondary, in: NSRect(x: 20, y: footerTop + 30, width: windowWidth - 40, height: 18))
    }

    cg.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()
    return origin.y + full * scale
}

// MARK: - One frame

func render(_ frame: Frame) -> Data? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let cg = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    cg.translateBy(x: 0, y: canvas.height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    drawDesktop()
    drawMenuBar(clock: frame.clock)
    if frame.titleCard {
        drawTitleCard()
    } else {
        if let caption = frame.caption { drawCaption(caption) }
        var bottom = windowTop
        if let query = frame.query { bottom = drawWindow(frame, query: query) }
        if let key = frame.key { drawKey(key, under: bottom) }
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let image = cg.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

// MARK: - The story

var frames: [Frame] = []
func hold(_ seconds: Double) { frames[frames.count - 1].seconds = seconds }
func type(_ text: String, after prefix: String = "", caption: String, content: (String) -> Content = { _ in .search }) {
    for count in 1...text.count {
        let typed = String(text.prefix(count))
        frames.append(Frame(seconds: 0.075, caption: caption, query: prefix + typed, content: content(typed)))
    }
}
func index(of uid: String?, in items: [Item]) -> Int { items.firstIndex { $0["uid"] as? String == uid } ?? 0 }

frames.append(Frame(seconds: 2.4, titleCard: true))

// 1. The agenda: the next meeting first.
let first = "Your next meeting, one keystroke away"
frames.append(Frame(seconds: 0.5, caption: first, query: "", key: "⌥ Space"))
type("cal", caption: first)
frames.append(Frame(seconds: 3.2, caption: first, query: "cal ", content: .list(agenda("list").items, selected: 0)))

// 2. A new event, read from plain words as you type.
let second = "Add an event in plain words"
type("+ Design sync 11:30", after: "cal ", caption: second) { typed in .list(agenda("list", typed).items, selected: 0) }
hold(3.4)

// 3. The month, then a step to another day.
let third = "The whole month at a glance"
frames.append(Frame(seconds: 0.5, caption: third, query: "", key: "⌥ Space"))
type("month", caption: third)
let month = agenda("month")
let today = index(of: month.preselect, in: month.items)
frames[frames.count - 1].content = .grid(month.items, selected: today, aspect: 1)
hold(1.6)
frames.append(Frame(seconds: 0.5, caption: third, query: "month", content: .grid(month.items, selected: today + 7, aspect: 1), key: "↓"))
for step in 1...4 {
    frames.append(Frame(seconds: 0.17, caption: third, query: "month", content: .grid(month.items, selected: today + 7 - step, aspect: 1), key: "←"))
}
frames.append(Frame(seconds: 2.2, caption: third, query: "month", content: .grid(month.items, selected: today + 3, aspect: 1)))

// 4. The week.
let fourth = "Your week, hour by hour"
frames.append(Frame(seconds: 0.5, caption: fourth, query: "", key: "⌥ Space"))
type("week", caption: fourth)
let week = agenda("week")
frames[frames.count - 1].content = .grid(week.items, selected: index(of: week.preselect, in: week.items), aspect: 1.5)
hold(2.5)

// 5. A day, down to a free gap you can block.
let fifth = "Free time you can block with ↩"
frames.append(Frame(seconds: 0.5, caption: fifth, query: "", key: "⌥ Space"))
type("day", caption: fifth)
let day = agenda("day").items
frames[frames.count - 1].query = "day "
frames[frames.count - 1].content = .list(day, selected: 0)
hold(0.8)
let gap = day.firstIndex { ($0["title"] as? String ?? "").hasPrefix("Free") && ($0["subtitle"] as? String ?? "").hasPrefix("2 h") } ?? 4
for row in 1...gap {
    frames.append(Frame(seconds: 0.13, caption: fifth, query: "day ", content: .list(day, selected: row), key: "↓"))
}
frames.append(Frame(seconds: 2.4, caption: fifth, query: "day ", content: .list(day, selected: gap)))

// 6. The alert: at 09:59 Alfred opens the join list by itself.
let sixth = "A nudge when it's time to join"
frames.append(Frame(seconds: 1.0, caption: sixth, clock: "09:58"))
frames.append(Frame(seconds: 0.4, caption: sixth, clock: "09:59"))
let pinned = (ProcessInfo.processInfo.environment["AGENDA_NOW"] ?? "").replacingOccurrences(of: "09:56:00", with: "09:59:00")
let join = agenda("join", "", ["AGENDA_NOW": pinned]).items
for appear in [0.3, 0.65, 1.0] {
    frames.append(Frame(seconds: 0.05, caption: sixth, clock: "09:59", query: "join", content: .list(join, selected: 0), appear: CGFloat(appear)))
}
hold(3.4)

// MARK: - Writing

var list = "ffconcat version 1.0\n"
for (number, frame) in frames.enumerated() {
    let name = String(format: "frame-%03d.png", number)
    guard let png = render(frame) else { fatalError("could not draw \(name)") }
    try png.write(to: out.appendingPathComponent(name))
    list += "file '\(name)'\nduration \(frame.seconds)\n"
}
// The concat demuxer takes the last file's duration only when that file is listed once more.
list += "file '\(String(format: "frame-%03d.png", frames.count - 1))'\n"
try list.write(to: out.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
print("\(frames.count) frames, \(String(format: "%.1f", frames.reduce(0) { $0 + $1.seconds })) s")
