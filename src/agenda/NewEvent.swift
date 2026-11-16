// NewEvent.swift — typing "+ dentist tomorrow 15:00" in the agenda adds an event. The words
// that say when are read out of the text and the rest becomes the title. Each calendar that
// takes new events gets a row, the one from the settings first, and ↩ saves it through the
// bridge's `create` (act `create`).

import Foundation

struct Draft {
    var title = ""
    var start: Date?
    var end: Date?
    var allDay = false
    var calendarHint: String?
}

// MARK: - Reading the text

/// The groups of a whole-string, case-insensitive match, or nil.
private func wholeMatch(_ pattern: String, _ text: String) -> [String?]? {
    guard let regex = try? NSRegularExpression(pattern: "^(?:\(pattern))$", options: .caseInsensitive),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } }
}

/// Minutes after midnight for "15:00", "15.00", "3pm", "3:30pm", "3p", "noon", "midnight".
/// A bare number ("15") is a time only where one is expected: after "at", or in a range.
/// Times are 24-hour unless they say am or pm.
private func clockMinutes(_ token: String, bare: Bool = false) -> Int? {
    switch token.lowercased() {
    case "noon": return 12 * 60
    case "midnight": return 0
    default: break
    }
    guard let g = wholeMatch(#"(\d{1,2})(?:[:.](\d{2}))?(am|pm|a|p)?"#, token), let hour = g[1].flatMap({ Int($0) }) else { return nil }
    let minute = g[2].flatMap { Int($0) }
    let half = g[3]?.lowercased()
    guard minute != nil || half != nil || bare, (minute ?? 0) < 60 else { return nil }
    if let half {
        guard (1...12).contains(hour) else { return nil }
        return (hour % 12 + (half.hasPrefix("p") ? 12 : 0)) * 60 + (minute ?? 0)
    }
    return hour < 24 ? hour * 60 + (minute ?? 0) : nil
}

/// "15-16", "3-4pm", "10:30-11:15", "9.30-10.30". The end's am/pm carries over to a bare
/// start ("3-4pm" is 15:00–16:00), and a bare end before the start means the afternoon
/// ("9-5" is 09:00–17:00). Otherwise an end before the start is on the next day.
private func clockRange(_ token: String) -> (start: Int, end: Int)? {
    let halves = token.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "–" }).map(String.init)
    guard halves.count == 2, let end = clockMinutes(halves[1], bare: true) else { return nil }
    let isBare: (String) -> Bool = { $0.allSatisfy { $0.isNumber || $0 == ":" || $0 == "." } }
    let suffix = String(halves[1].drop { $0.isNumber || $0 == ":" || $0 == "." })
    var start = clockMinutes(halves[0], bare: true)
    if !suffix.isEmpty, isBare(halves[0]), let carried = clockMinutes(halves[0] + suffix), carried < end { start = carried }
    guard let start else { return nil }
    if end <= start, isBare(halves[1]), end + 12 * 60 > start, end + 12 * 60 < 24 * 60 { return (start, end + 12 * 60) }
    return (start, end)
}

/// Seconds for "30m", "45min", "1h", "1h30", "1h30m", "1.5h", "2hrs", "90minutes".
private func lengthSeconds(_ token: String) -> Double? {
    let t = token.replacingOccurrences(of: ",", with: ".")
    if let g = wholeMatch(#"(\d+(?:\.\d+)?)(?:h|hr|hrs|hour|hours)(?:(\d{1,2})(?:m|min|mins)?)?"#, t), let hours = g[1].flatMap({ Double($0) }) {
        return hours * 3600 + Double(g[2].flatMap { Int($0) } ?? 0) * 60
    }
    if let g = wholeMatch(#"(\d+)(?:m|min|mins|minute|minutes)"#, t), let minutes = g[1].flatMap({ Double($0) }) {
        return minutes * 60
    }
    return nil
}

/// Reads "what and when". Days are anything `day` accepts (tomorrow, fri, 24/11, 2026-11-24,
/// +3); times, ranges and lengths as above, also split over two words ("3 pm", "45 min") or
/// as two times ("3pm to 4pm"); "@name" picks a calendar or account. When a word could be a
/// day or time twice, the last one counts ("coffee with Tom tomorrow"). The rest is the title.
func parseDraft(_ text: String) -> Draft {
    let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let lower = words.map { $0.lowercased() }
    let units: Set<String> = ["m", "min", "mins", "minute", "minutes", "h", "hr", "hrs", "hour", "hours"]
    let halves: Set<String> = ["am", "pm", "a.m.", "p.m."]

    var day: (date: Date, span: ClosedRange<Int>)?
    var range: (start: Int, end: Int, span: ClosedRange<Int>)?
    var length: (seconds: Double, span: ClosedRange<Int>)?
    var hint: (name: String, span: ClosedRange<Int>)?
    var clocks: [(minutes: Int, span: ClosedRange<Int>)] = []

    var i = 0
    while i < words.count {
        let word = words[i], next = i + 1 < words.count ? lower[i + 1] : ""
        let isNumber = Double(word.replacingOccurrences(of: ",", with: ".")) != nil
        if word.hasPrefix("@"), word.count > 1 {
            hint = (String(word.dropFirst()), i...i)
        } else if isNumber, units.contains(next), let seconds = lengthSeconds(word + next) {
            length = (seconds, i...(i + 1)); i += 1
        } else if halves.contains(next), let minutes = clockMinutes(word + next.replacingOccurrences(of: ".", with: "")) {
            clocks.append((minutes, i...(i + 1))); i += 1
        } else if let seconds = lengthSeconds(word) {
            length = (seconds, i...i)
        } else if let found = clockRange(word) {
            range = (found.start, found.end, i...i)
        } else if let minutes = clockMinutes(word, bare: i > 0 && lower[i - 1] == "at") {
            clocks.append((minutes, i...i))
        } else if let date = dayFromToken(word), abs(date.timeIntervalSince(today)) < 400 * 86400 {
            day = (date, i...i)
        }
        i += 1
    }

    var used = Set<Int>()
    func take(_ span: ClosedRange<Int>, after connectors: Set<String>) {
        used.formUnion(span)
        if span.lowerBound > 0, connectors.contains(lower[span.lowerBound - 1]) { used.insert(span.lowerBound - 1) }
    }
    let lead: Set<String> = ["at", "on", "from", "by"]

    var startMinutes: Int?, endMinutes: Int?
    if let range {
        (startMinutes, endMinutes) = (range.start, range.end)
        take(range.span, after: lead)
    } else if clocks.count >= 2 {
        let a = clocks[clocks.count - 2], b = clocks[clocks.count - 1]
        let between = Array(lower[(a.span.upperBound + 1)..<b.span.lowerBound])
        if between.count <= 1, between.allSatisfy({ ["to", "-", "–", "until", "till"].contains($0) }) {
            (startMinutes, endMinutes) = (a.minutes, b.minutes)
            take(a.span, after: lead)
            used.formUnion(b.span)
            used.formUnion((a.span.upperBound + 1)..<b.span.lowerBound)
        } else {
            startMinutes = b.minutes
            take(b.span, after: lead)
        }
    } else if let only = clocks.last {
        startMinutes = only.minutes
        take(only.span, after: lead)
    }
    if let day { take(day.span, after: lead) }
    if let hint { used.formUnion(hint.span) }
    // A length only means something with a start time and no end.
    if let length, startMinutes != nil, endMinutes == nil { take(length.span, after: ["for"]) }

    var draft = Draft()
    draft.title = words.indices.filter { !used.contains($0) }.map { words[$0] }.joined(separator: " ")
    draft.calendarHint = hint?.name
    if let startMinutes {
        var start = cal.date(byAdding: .minute, value: startMinutes, to: day?.date ?? today) ?? now
        if day == nil, start <= now { start = addDays(start, 1) }  // a time alone means the next one
        var end = start.addingTimeInterval(length?.seconds ?? 3600)
        if let endMinutes {
            end = cal.date(byAdding: .minute, value: endMinutes, to: cal.startOfDay(for: start)) ?? end
            if end <= start { end = addDays(end, 1) }
        }
        (draft.start, draft.end) = (start, end)
    } else if let day {
        (draft.start, draft.end, draft.allDay) = (day.date, addDays(day.date, 1), true)
    }
    return draft
}

// MARK: - Rows

func viewNewEvent(_ text: String) -> Never {
    let draft = parseDraft(text)
    let title = draft.title.nonEmpty ?? "New event"
    guard let start = draft.start, let end = draft.end else {
        Alfred.emit([Alfred.info(draft.title.isEmpty ? "New event" : "New event  \(draft.title)",
                                 "Add when: + dentist tomorrow 15:00 · + lunch fri 12-13 · + offsite 24/11", icon: "free")])
    }
    let (status, events) = Bridge.events(from: start, to: end)
    guard status == "fullAccess" else { Alfred.emit(setupRows(status)) }
    guard let found = writableCalendars(), !found.calendars.isEmpty else {
        Alfred.emit([Alfred.info("No calendar can take new events", "Check the calendars in the Calendar app", icon: "warning")])
    }

    // The calendar named after "@" first, then the one from the settings (or the system's
    // default), then the rest in the bridge's order.
    let preferred = preferredCalendar(found.calendars, defaultId: found.defaultId)
    let hint = draft.calendarHint?.folded
    func rank(_ c: CalendarInfo) -> Int {
        if let hint, calendarLabel(c).folded.contains(hint) { return 0 }
        return c.id == preferred?.id ? 1 : 2
    }
    let ordered = found.calendars.enumerated()
        .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
        .map { $0.element }

    let when = draft.allDay ? "\(Fmt.dayLabel(start)) · all day" : "\(Fmt.dayLabel(start)) \(Fmt.range(start, end))"
    let clashes = draft.allDay ? [] : events.filter { !$0.allDay && $0.availability != "free" && $0.startDate < end && $0.endDate > start }
    let clash = clashes.isEmpty ? nil : clashes.count == 1 ? "overlaps \(clashes[0].name.truncated(32))" : "overlaps \(clashes.count) events"

    let items: [Item] = ordered.prefix(6).enumerated().map { index, c in
        let label = calendarLabel(c)
        let parts: [String?] = index == 0 ? ["New event", when, label, clash, "↩ add"] : [title, when, clash]
        return [
            "uid": "new-\(c.id)",
            "title": index == 0 ? title : "Add to \(label)",
            "subtitle": parts.compactMap { $0 }.joined(separator: " · "),
            "arg": title,
            "icon": Alfred.icon("free"),
            "variables": [
                "act": "create", "title": title, "calid": c.id, "callabel": label,
                "start": String(start.timeIntervalSince1970), "end": String(end.timeIntervalSince1970),
                "allday": draft.allDay ? "1" : "0",
            ],
        ]
    }
    Alfred.emit(items)
}
