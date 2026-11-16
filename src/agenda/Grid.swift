// Grid.swift — the month and week views. Alfred's Grid View lays the tiles out seven to a row;
// each tile is one day, drawn by Render.swift.

import Foundation

/// The footer line for the selected day: meetings first (what is still to come, on today),
/// then all-day entries if there is nothing timed.
private func daySummary(_ events: [Ev], on day: Date) -> String {
    guard !events.isEmpty else { return "No events" }
    let allDay = events.filter { $0.allDay }
    var timed = events.filter { !$0.allDay }
    if day == today { timed = timed.filter { $0.endDate > now } + timed.filter { $0.endDate <= now } }

    var counts: [String] = []
    if !timed.isEmpty { counts.append("\(timed.count) timed") }
    if !allDay.isEmpty { counts.append("\(allDay.count) all-day") }
    let listed = timed.isEmpty ? allDay.prefix(3).map { $0.name } : timed.prefix(3).map { "\(Fmt.compact($0.startDate)) \($0.name.truncated(28))" }
    let rest = (timed.isEmpty ? allDay.count : timed.count) - listed.count
    return counts.joined(separator: ", ") + " · " + listed.joined(separator: " · ") + (rest > 0 ? " · +\(rest) more" : "")
}

/// The words a tile answers to when you type in the grid's filter field.
private func dayMatch(_ day: Date, _ events: [Ev]) -> String {
    ([Fmt.longDay(day), Fmt.key(day), String(cal.component(.day, from: day))] + events.map { $0.name }).joined(separator: " ")
}

private func dayItem(_ day: Date, _ events: [Ev], icon: String, mods: [String: Any]) -> Item {
    var all = mods
    all["cmd"] = ["subtitle": "Open this day in Calendar", "arg": Fmt.key(day), "variables": ["act": "calday", "date": Fmt.key(day)]]
    return [
        "uid": Fmt.key(day),
        "title": Fmt.longDay(day) + (day == today ? " · Today" : "") + " · week \(Fmt.weekNumber(day))",
        "subtitle": daySummary(events, on: day),
        "arg": Fmt.key(day),
        "icon": ["path": icon],
        "match": dayMatch(day, events),
        "variables": ["act": "v:day", "date": Fmt.key(day)],
        "mods": all,
    ]
}

// MARK: - Month

/// Accepts "2026-12", "+1" / "-1" (months from now), or a month name such as "dec".
private func monthStart(from text: String) -> Date? {
    let token = text.trimmed.folded
    guard !token.isEmpty else { return nil }
    if token.count == 7, let date = Fmt.date(monthKey: token) { return startOfMonth(date) }
    if token.hasPrefix("+") || token.hasPrefix("-"), let offset = Int(token), abs(offset) < 600 {
        return cal.date(byAdding: .month, value: offset, to: startOfMonth(today))
    }
    if token.count >= 3 {
        let english = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        let local = cal.monthSymbols.map { $0.folded }
        for month in 0..<12 where english[month].hasPrefix(token) || (local.count == 12 && local[month].hasPrefix(token)) {
            var parts = cal.dateComponents([.year], from: today)
            parts.month = month + 1
            parts.day = 1
            // A month already past this year means next year's.
            if month + 1 < cal.component(.month, from: today) { parts.year = (parts.year ?? 0) + 1 }
            return cal.date(from: parts)
        }
    }
    return nil
}

func viewMonth(_ argument: String) -> Never {
    let first = monthStart(from: argument) ?? Env.vars["month"].nonEmpty.flatMap { Fmt.date(monthKey: $0) }.map { startOfMonth($0) } ?? startOfMonth(today)
    let nextMonth = cal.date(byAdding: .month, value: 1, to: first) ?? first
    let previousMonth = cal.date(byAdding: .month, value: -1, to: first) ?? first
    let gridStart = startOfWeek(first)
    let gridEnd = addDays(startOfWeek(addDays(nextMonth, -1)), 7)

    let (status, events) = Bridge.events(from: gridStart, to: gridEnd)
    guard status == "fullAccess" else { Alfred.emit(setupRows(status)) }
    Render.prune()
    let byDay = eventsByDay(events, from: gridStart, to: gridEnd)

    let mods: [String: Any] = [
        "alt": ["subtitle": "Next month · \(Fmt.monthYear(nextMonth))", "arg": Fmt.monthKey(nextMonth),
                "variables": ["act": "v:month", "month": Fmt.monthKey(nextMonth)]],
        "ctrl": ["subtitle": "Previous month · \(Fmt.monthYear(previousMonth))", "arg": Fmt.monthKey(previousMonth),
                 "variables": ["act": "v:month", "month": Fmt.monthKey(previousMonth)]],
    ]
    var items: [Item] = []
    var day = gridStart
    while day < gridEnd {
        let dayEvents = byDay[Fmt.key(day)] ?? []
        let tile = DayTile(day: day, events: dayEvents, inMonth: cal.isDate(day, equalTo: first, toGranularity: .month))
        items.append(dayItem(day, dayEvents, icon: Render.monthTile(tile), mods: mods))
        day = addDays(day, 1)
    }
    let selected = cal.isDate(today, equalTo: first, toGranularity: .month) ? today : first
    Alfred.emit(items, extra: ["preselect": Fmt.key(selected)])
}

// MARK: - Week

func viewWeek(_ argument: String) -> Never {
    let token = argument.trimmed
    var anchor = today
    if let offset = Int(token), token.hasPrefix("+") || token.hasPrefix("-"), abs(offset) < 520 {
        anchor = addDays(today, offset * 7)
    } else if !token.isEmpty, let parsed = dayFromToken(token) {
        anchor = parsed
    } else if let key = Env.vars["week"].nonEmpty, let stored = Fmt.date(key: key) {
        anchor = cal.startOfDay(for: stored)
    }
    let weekStart = startOfWeek(anchor)
    let weekEnd = addDays(weekStart, 7)

    let (status, events) = Bridge.events(from: weekStart, to: weekEnd)
    guard status == "fullAccess" else { Alfred.emit(setupRows(status)) }
    Render.prune()
    let byDay = eventsByDay(events, from: weekStart, to: weekEnd)

    // One hour range for the whole week, widened beyond working hours when a meeting needs it.
    // Evenings stretch as far as needed; mornings by at most three hours, so one very early
    // event (a flight, say) doesn't squash every day's blocks. It shows as a sliver at the top.
    var firstHour = Config.workStart, lastHour = Config.workEnd
    let earliest = max(0, Config.workStart - 3), latest = 24
    var anyAllDay = false
    for index in 0..<7 {
        let day = addDays(weekStart, index), next = addDays(day, 1)
        for event in byDay[Fmt.key(day)] ?? [] {
            if event.allDay || (event.startDate <= day && event.endDate >= next) {
                anyAllDay = true
                continue
            }
            let start = max(event.startDate, day), end = min(event.endDate, next)
            firstHour = max(earliest, min(firstHour, cal.component(.hour, from: start)))
            let endHour = end == next ? 24 : cal.component(.hour, from: end) + (cal.component(.minute, from: end) > 0 ? 1 : 0)
            lastHour = min(latest, max(lastHour, endHour))
        }
    }

    let next = addDays(weekStart, 7), previous = addDays(weekStart, -7)
    let mods: [String: Any] = [
        "alt": ["subtitle": "Next week · from \(Fmt.dayMonth(next))", "arg": Fmt.key(next), "variables": ["act": "v:week", "week": Fmt.key(next)]],
        "ctrl": ["subtitle": "Previous week · from \(Fmt.dayMonth(previous))", "arg": Fmt.key(previous), "variables": ["act": "v:week", "week": Fmt.key(previous)]],
    ]
    var items: [Item] = []
    for index in 0..<7 {
        let day = addDays(weekStart, index)
        let dayEvents = byDay[Fmt.key(day)] ?? []
        let icon = Render.weekTile(DayTile(day: day, events: dayEvents), hours: firstHour...lastHour, allDayRow: anyAllDay)
        items.append(dayItem(day, dayEvents, icon: icon, mods: mods))
    }
    let selected = (weekStart..<weekEnd).contains(today) ? today : weekStart
    Alfred.emit(items, extra: ["preselect": Fmt.key(selected)])
}
