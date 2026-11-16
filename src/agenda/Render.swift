// Render.swift — draws the pictures Alfred shows: date badges for rows, and the day tiles
// that make up the month and week grids. Each picture is cached under a hash of its content,
// so a tile is only drawn again when something on it changes.
//
// Alfred's Grid View already draws a rounded cell (and the selection highlight) behind every
// tile, so tiles have a transparent background and only today gets a frame of its own.

import AppKit

struct Palette {
    let dark: Bool
    var primary: NSColor { dark ? NSColor(white: 1, alpha: 0.93) : NSColor(white: 0, alpha: 0.87) }
    var secondary: NSColor { dark ? NSColor(white: 1, alpha: 0.56) : NSColor(white: 0, alpha: 0.54) }
    var line: NSColor { dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.11) }
    var accent: NSColor { dark ? NSColor(srgbRed: 0.36, green: 0.64, blue: 1.0, alpha: 1) : NSColor(srgbRed: 0.0, green: 0.42, blue: 0.94, alpha: 1) }
    var nowLine: NSColor { NSColor(srgbRed: 1.0, green: 0.27, blue: 0.23, alpha: 1) }
    /// How strongly a calendar's colour tints an event line.
    var tint: CGFloat { dark ? 0.40 : 0.36 }
}

func nsColor(_ hex: String?) -> NSColor {
    guard let hex, hex.count == 7, hex.hasPrefix("#"), let value = Int(hex.dropFirst(), radix: 16) else {
        return NSColor(srgbRed: 0.56, green: 0.56, blue: 0.58, alpha: 1)
    }
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

/// Black or white, whichever reads better on the given fill.
func ink(on color: NSColor) -> NSColor {
    let c = color.usingColorSpace(.sRGB) ?? color
    let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
    return luminance > 0.62 ? NSColor(white: 0, alpha: 0.85) : NSColor.white
}

private func text(_ string: String, _ rect: CGRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, align: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineBreakMode = .byTruncatingTail
    let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    (string as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                              attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
}

private func fill(_ rect: CGRect, radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

private func stroke(_ rect: CGRect, radius: CGFloat, _ color: NSColor, width: CGFloat) {
    color.setStroke()
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), xRadius: radius, yRadius: radius)
    path.lineWidth = width
    path.stroke()
}

struct DayTile {
    let day: Date
    let events: [Ev]
    var inMonth = true
    var isToday: Bool { day == today }
}

enum Render {
    /// Bump when the look changes, so stale cached pictures are not reused.
    static let style = "5"

    private static func hash(_ string: String) -> String {
        var value: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 { value = (value ^ UInt64(byte)) &* 0x100000001b3 }
        return String(value, radix: 16)
    }

    private static func folder(_ name: String) -> URL {
        let url = Env.cacheDir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Draws into a PNG with the origin at the top left, the way the layouts below are written.
    static func png(_ width: Int, _ height: Int, to url: URL, _ draw: (CGRect) -> Void) {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let bitmap = NSGraphicsContext(bitmapImageRep: rep)
        else { return }
        let cg = bitmap.cgContext
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        draw(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
    }

    private static func cached(_ kind: String, _ key: String, _ width: Int, _ height: Int, _ draw: (CGRect, Palette) -> Void) -> String {
        let url = folder(kind).appendingPathComponent(hash("\(style)|\(Env.dark)|\(key)") + ".png")
        if !FileManager.default.fileExists(atPath: url.path) {
            png(width, height, to: url) { draw($0, Palette(dark: Env.dark)) }
        }
        return url.path
    }

    /// Removes pictures that have not been needed for a few days. Runs at most once a day.
    static func prune() {
        let stamp = Env.cacheDir.appendingPathComponent(".pruned")
        let fm = FileManager.default
        if let date = (try? fm.attributesOfItem(atPath: stamp.path))?[.modificationDate] as? Date, Date().timeIntervalSince(date) < 86400 { return }
        fm.createFile(atPath: stamp.path, contents: nil)
        let cutoff = Date().addingTimeInterval(-3 * 86400)
        for kind in ["tiles", "badges"] {
            let dir = folder(kind)
            for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                if modified < cutoff { try? fm.removeItem(at: file) }
            }
        }
    }

    private static func todayFrame(_ bounds: CGRect, _ p: Palette) {
        let frame = bounds.insetBy(dx: 2, dy: 2)
        fill(frame, radius: 26, p.accent.withAlphaComponent(p.dark ? 0.24 : 0.16))
        stroke(frame, radius: 26, p.accent, width: 5)
    }

    // MARK: Row badge

    /// A small calendar page: weekday on a strip in the calendar's colour, day number below.
    static func badge(day: Date, color: String?) -> String {
        let weekday = Fmt.weekday(day).uppercased()
        let number = String(cal.component(.day, from: day))
        return cached("badges", "badge|\(weekday)|\(number)|\(color ?? "-")", 128, 128) { bounds, p in
            let body = bounds.insetBy(dx: 8, dy: 8)
            let shape = NSBezierPath(roundedRect: body, xRadius: 24, yRadius: 24)
            (p.dark ? NSColor(white: 1, alpha: 0.13) : NSColor(white: 0, alpha: 0.07)).setFill()
            shape.fill()
            let strip = color.map { nsColor($0) } ?? (p.dark ? NSColor(white: 1, alpha: 0.22) : NSColor(white: 0, alpha: 0.22))
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            strip.setFill()
            CGRect(x: body.minX, y: body.minY, width: body.width, height: 34).fill()
            NSGraphicsContext.restoreGraphicsState()
            text(weekday, CGRect(x: body.minX, y: body.minY + 5, width: body.width, height: 26), size: 19, weight: .bold,
                 color: color == nil ? p.primary : ink(on: strip), align: .center)
            text(number, CGRect(x: body.minX, y: body.minY + 38, width: body.width, height: 70), size: 56, weight: .bold, color: p.primary, align: .center)
        }
    }

    // MARK: Month tile

    private static func signature(_ events: [Ev]) -> String {
        events.map { "\($0.allDay ? "" : Fmt.compact($0.startDate))~\($0.end - $0.start)~\($0.name)~\($0.color ?? "")" }.joined(separator: "|")
    }

    static func monthTile(_ tile: DayTile) -> String {
        let weekday = Fmt.weekday(tile.day).uppercased()
        let number = String(cal.component(.day, from: tile.day))
        let allDay = tile.events.filter { $0.allDay }
        var timed = tile.events.filter { !$0.allDay }
        // On today's tile, what is still to come matters more than what is over.
        if tile.isToday { timed = timed.filter { $0.endDate > now } + timed.filter { $0.endDate <= now } }

        // Three lines fit on a tile. Meetings get them first; all-day entries (holidays,
        // birthdays) take a line only when there is room, otherwise they shrink to dots.
        var lines: [(label: String, color: String?)] = []
        let allDayAsLine = !allDay.isEmpty && timed.count <= 2
        if allDayAsLine, let first = allDay.first {
            lines.append((allDay.count > 1 ? "\(first.name) +\(allDay.count - 1)" : first.name, first.color))
        }
        let room = 3 - lines.count
        let timedShown = timed.count <= room ? timed : Array(timed.prefix(room - 1))
        for event in timedShown {
            // An event carried over from the day before has no start time on this day.
            lines.append((event.startDate < tile.day ? event.name : "\(Fmt.compact(event.startDate)) \(event.name)", event.color))
        }
        let hidden = timed.count - timedShown.count
        let dots = allDayAsLine ? [] : allDay.prefix(4).map { $0.color }

        let key = "month|\(weekday)|\(number)|\(tile.inMonth)|\(tile.isToday)|\(hidden)|"
            + lines.map { "\($0.label)~\($0.color ?? "")" }.joined(separator: "|") + "#" + dots.map { $0 ?? "" }.joined(separator: ",")
        return cached("tiles", key, 240, 240) { bounds, p in
            if !tile.inMonth { NSGraphicsContext.current?.cgContext.setAlpha(0.42) }
            if tile.isToday { todayFrame(bounds, p) }

            text(weekday, CGRect(x: 14, y: 14, width: 110, height: 32), size: 25, weight: .semibold, color: tile.isToday ? p.accent : p.secondary)
            text(number, CGRect(x: 96, y: 2, width: 132, height: 62), size: 50, weight: .bold, color: tile.isToday ? p.accent : p.primary, align: .right)
            for (index, dot) in dots.enumerated() {
                fill(CGRect(x: 14 + CGFloat(index) * 22, y: 53, width: 16, height: 10), radius: 5, nsColor(dot))
            }

            var y: CGFloat = 76
            for line in lines {
                let bar = CGRect(x: 8, y: y, width: 224, height: 46)
                let color = nsColor(line.color)
                fill(bar, radius: 10, color.withAlphaComponent(p.tint))
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10).addClip()
                color.setFill()
                CGRect(x: bar.minX, y: bar.minY, width: 8, height: bar.height).fill()
                NSGraphicsContext.restoreGraphicsState()
                text(line.label, CGRect(x: bar.minX + 16, y: bar.minY + 7, width: bar.width - 20, height: 34), size: 25, weight: .medium, color: p.primary)
                y += 53
            }
            if hidden > 0 {
                text("+\(hidden) more", CGRect(x: 14, y: y + 6, width: 210, height: 34), size: 25, weight: .medium, color: p.secondary)
            }
        }
    }

    // MARK: Week tile

    /// A day as a column: header, optional all-day strip, then a timeline with the events as blocks.
    /// `hours` and `allDayRow` are the same for all seven tiles so the blocks line up across the week.
    static func weekTile(_ tile: DayTile, hours: ClosedRange<Int>, allDayRow: Bool) -> String {
        let weekday = Fmt.weekday(tile.day).uppercased()
        let number = String(cal.component(.day, from: tile.day))
        let dayStart = tile.day, dayEnd = addDays(tile.day, 1)
        let allDay = tile.events.filter { $0.allDay || ($0.startDate <= dayStart && $0.endDate >= dayEnd) }
        let timed = tile.events.filter { e in !allDay.contains { $0.occurrenceKey == e.occurrenceKey } }
        // The "now" line moves in 5-minute steps so today's tile is not redrawn every minute.
        let nowSlot = tile.isToday ? Int(now.timeIntervalSince(dayStart) / 300) : -1
        let key = "week|\(weekday)|\(number)|\(tile.isToday)|\(hours)|\(allDayRow)|\(nowSlot)|\(signature(allDay))#\(signature(timed))"

        return cached("tiles", key, 300, 450) { bounds, p in
            if tile.isToday { todayFrame(bounds, p) }
            text(weekday, CGRect(x: 14, y: 16, width: 130, height: 36), size: 27, weight: .semibold, color: tile.isToday ? p.accent : p.secondary)
            text(number, CGRect(x: 150, y: 2, width: 138, height: 60), size: 48, weight: .bold, color: tile.isToday ? p.accent : p.primary, align: .right)

            var top: CGFloat = 74
            if allDayRow {
                if let first = allDay.first {
                    let chip = CGRect(x: 8, y: 68, width: 284, height: 36)
                    fill(chip, radius: 9, nsColor(first.color).withAlphaComponent(p.tint))
                    let label = allDay.count > 1 ? "\(first.name) +\(allDay.count - 1)" : first.name
                    text(label, CGRect(x: chip.minX + 10, y: chip.minY + 4, width: chip.width - 18, height: 30), size: 22, weight: .medium, color: p.primary)
                }
                top = 116
            }

            let bottom: CGFloat = 440
            let span = CGFloat(hours.upperBound - hours.lowerBound)
            let perHour = (bottom - top) / span
            let gridLeft: CGFloat = 36, left: CGFloat = 40, right: CGFloat = 294
            func y(_ date: Date) -> CGFloat {
                let hoursIn = CGFloat(date.timeIntervalSince(dayStart) / 3600) - CGFloat(hours.lowerBound)
                return top + min(max(hoursIn, 0), span) * perHour
            }

            let labelEvery = perHour < 22 ? 3 : (perHour < 34 ? 2 : 1)
            for hour in hours.lowerBound...hours.upperBound {
                let lineY = top + CGFloat(hour - hours.lowerBound) * perHour
                p.line.setFill()
                CGRect(x: gridLeft, y: lineY, width: right - gridLeft, height: 1.5).fill()
                if hour < hours.upperBound, (hour - hours.lowerBound) % labelEvery == 0 {
                    let label = Fmt.uses12Hour ? String(hour % 12 == 0 ? 12 : hour % 12) : String(format: "%02d", hour)
                    text(label, CGRect(x: 0, y: lineY + 1, width: 31, height: 24), size: 18, weight: .regular, color: p.secondary, align: .right)
                }
            }

            // Side-by-side columns for events that overlap.
            var columnEnds: [Double] = []
            var placed: [(event: Ev, column: Int, group: Int)] = []
            var groupEnd = -Double.infinity
            var group = -1
            for event in timed.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
                if event.start >= groupEnd {
                    group += 1
                    columnEnds = []
                    groupEnd = event.end
                }
                groupEnd = max(groupEnd, event.end)
                let column = columnEnds.firstIndex { $0 <= event.start } ?? columnEnds.count
                if column == columnEnds.count { columnEnds.append(event.end) } else { columnEnds[column] = event.end }
                placed.append((event, column, group))
            }
            for entry in placed {
                let columns = CGFloat((placed.filter { $0.group == entry.group }.map { $0.column }.max() ?? 0) + 1)
                let width = (right - left) / columns
                let startY = y(max(entry.event.startDate, dayStart)), endY = y(min(entry.event.endDate, dayEnd))
                let block = CGRect(x: left + CGFloat(entry.column) * width, y: startY + 1, width: width - 3, height: max(endY - startY - 2, 10))
                let color = nsColor(entry.event.color)
                fill(block, radius: 6, color.withAlphaComponent(0.92))
                if block.height >= 24 {
                    text(entry.event.name, CGRect(x: block.minX + 6, y: block.minY, width: block.width - 9, height: 26), size: 19, weight: .semibold, color: ink(on: color))
                }
                if block.height >= 50 {
                    text(Fmt.compact(entry.event.startDate), CGRect(x: block.minX + 6, y: block.minY + 24, width: block.width - 9, height: 24), size: 17, weight: .regular, color: ink(on: color).withAlphaComponent(0.85))
                }
            }

            if tile.isToday, now > at(dayStart, hour: hours.lowerBound), now < at(dayStart, hour: hours.upperBound) {
                let lineY = y(now)
                p.nowLine.setFill()
                CGRect(x: gridLeft - 2, y: lineY - 2, width: right - gridLeft + 2, height: 4).fill()
                NSBezierPath(ovalIn: CGRect(x: gridLeft - 8, y: lineY - 7, width: 14, height: 14)).fill()
            }
        }
    }

    // MARK: Fixed icons (drawn once by build.sh)

    static func symbol(_ name: String, to file: String, color: NSColor, in dir: URL, pointSize: CGFloat = 78) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium).applying(.init(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
            FileHandle.standardError.write(Data("missing symbol \(name)\n".utf8))
            return
        }
        png(128, 128, to: dir.appendingPathComponent(file + ".png")) { bounds in
            let size = image.size
            let scale = min(104 / size.width, 104 / size.height, 1.4)
            let rect = CGRect(x: bounds.midX - size.width * scale / 2, y: bounds.midY - size.height * scale / 2, width: size.width * scale, height: size.height * scale)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    static func staticIcons() {
        let dir = Env.workflowDir.appendingPathComponent("icons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let blue = NSColor(srgbRed: 0.24, green: 0.55, blue: 1.0, alpha: 1)
        let green = NSColor(srgbRed: 0.20, green: 0.74, blue: 0.45, alpha: 1)
        let grey = NSColor(srgbRed: 0.56, green: 0.58, blue: 0.62, alpha: 1)
        let amber = NSColor(srgbRed: 0.98, green: 0.66, blue: 0.14, alpha: 1)
        symbol("video.fill", to: "video", color: green, in: dir)
        symbol("clock", to: "next", color: blue, in: dir)
        symbol("calendar.badge.plus", to: "free", color: green, in: dir)
        symbol("calendar.day.timeline.left", to: "day", color: blue, in: dir)
        symbol("calendar", to: "month", color: blue, in: dir)
        symbol("rectangle.split.3x1", to: "week", color: blue, in: dir)
        symbol("chevron.right.circle", to: "forward", color: grey, in: dir)
        symbol("chevron.left.circle", to: "back", color: grey, in: dir)
        symbol("info.circle", to: "info", color: grey, in: dir)
        symbol("lock.circle", to: "lock", color: amber, in: dir)
        symbol("exclamationmark.triangle", to: "warning", color: amber, in: dir)

        // Workflow icon: a calendar page.
        png(512, 512, to: Env.workflowDir.appendingPathComponent("icon.png")) { bounds in
            let page = bounds.insetBy(dx: 44, dy: 44)
            let shape = NSBezierPath(roundedRect: page, xRadius: 96, yRadius: 96)
            NSColor.white.setFill()
            shape.fill()
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            NSColor(srgbRed: 0.17, green: 0.47, blue: 0.98, alpha: 1).setFill()
            CGRect(x: page.minX, y: page.minY, width: page.width, height: 132).fill()
            NSGraphicsContext.restoreGraphicsState()
            for row in 0..<3 {
                for column in 0..<4 {
                    let dot = CGRect(x: page.minX + 62 + CGFloat(column) * 84, y: page.minY + 178 + CGFloat(row) * 74, width: 48, height: 48)
                    let highlighted = row == 1 && column == 2
                    (highlighted ? NSColor(srgbRed: 0.17, green: 0.47, blue: 0.98, alpha: 1) : NSColor(white: 0, alpha: 0.16)).setFill()
                    NSBezierPath(roundedRect: dot, xRadius: 14, yRadius: 14).fill()
                }
            }
        }
        print("icons written to \(dir.path)")
    }
}
