// Views.swift — the list views Alfred shows as rows: agenda, one day, join and block time.

import Foundation

typealias Item = [String: Any]

enum Alfred {
    /// Prints Script Filter JSON and ends the program. `skipknowledge` keeps rows in the
    /// order given here while still letting Alfred remember the selection between refreshes.
    static func emit(_ items: [Item], rerun: Double? = nil, extra: [String: Any] = [:]) -> Never {
        var out: [String: Any] = ["items": items, "skipknowledge": true]
        if let rerun { out["rerun"] = rerun }
        for (key, value) in extra { out[key] = value }
        let data = (try? JSONSerialization.data(withJSONObject: out)) ?? Data(#"{"items":[]}"#.utf8)
        FileHandle.standardOutput.write(data)
        exit(0)
    }

    static func icon(_ name: String) -> [String: Any] { ["path": "icons/\(name).png"] }

    static func info(_ title: String, _ subtitle: String = "", icon name: String = "info") -> Item {
        ["title": title, "subtitle": subtitle, "valid": false, "icon": icon(name)]
    }

    /// A row that switches to another view. The view reads its target from the variables.
    static func nav(_ title: String, _ subtitle: String, icon name: String, vars: [String: String]) -> Item {
        ["title": title, "subtitle": subtitle, "arg": title, "icon": icon(name), "variables": vars]
    }
}

/// What to show when the calendar can't be read yet.
func setupRows(_ status: String) -> [Item] {
    switch status {
    case "notDetermined":
        return [[
            "title": "Allow calendar access",
            "subtitle": "↩ shows the macOS prompt — choose Allow Full Access",
            "arg": "auth", "icon": Alfred.icon("lock"), "variables": ["act": "auth"],
        ]]
    case "denied", "writeOnly", "restricted":
        return [[
            "title": "Calendar access is switched off",
            "subtitle": "↩ opens Privacy & Security › Calendars — give “agenda-calendar” Full Access",
            "arg": "settings", "icon": Alfred.icon("lock"), "variables": ["act": "settings"],
        ]]
    default:
        return [Alfred.info("The calendar helper isn’t responding", "Run build.sh in the workflow folder, then try again (\(status))", icon: "warning")]
    }
}

// MARK: - Describing an event

func timeText(_ e: Ev) -> String {
    let lastMoment = e.endDate.addingTimeInterval(-1)
    if e.allDay {
        return cal.isDate(e.startDate, inSameDayAs: lastMoment) ? "All day" : "All day · until \(Fmt.dayMonth(lastMoment))"
    }
    if cal.isDate(e.startDate, inSameDayAs: lastMoment) { return Fmt.range(e.startDate, e.endDate) }
    return "\(Fmt.time(e.startDate)) – \(Fmt.dayMonth(e.endDate)) \(Fmt.time(e.endDate))"
}

func relativeText(_ e: Ev) -> String? {
    if e.allDay { return nil }
    if e.inProgress { return "now · \(Fmt.duration(e.endDate.timeIntervalSince(now))) left" }
    let seconds = e.startDate.timeIntervalSince(now)
    return seconds > 0 && seconds <= 24 * 3600 ? Fmt.until(e.startDate) : nil
}

func replyFlag(_ e: Ev) -> String? {
    switch e.myStatus {
    case "tentative": return "tentative"
    case "pending": return "not answered"
    case "declined": return "declined"
    default: return e.status == "tentative" ? "tentative" : nil
    }
}

func canJoinNow(_ e: Ev, _ meeting: Meeting?) -> Bool {
    guard meeting != nil, !e.allDay else { return false }
    return now >= e.startDate.addingTimeInterval(-Double(Config.joinWindow) * 60) && now < e.endDate
}

/// Plain-text summary used for ⌘C and ⌘L (Large Type).
func details(_ e: Ev, _ meeting: Meeting?) -> String {
    var lines = [e.name]
    let day = Fmt.dayMonth(e.startDate)
    lines.append(e.allDay ? "\(day) · \(timeText(e))" : "\(day) · \(timeText(e)) (\(Fmt.duration(e.end - e.start)))")
    if let place = e.location.nonEmpty, meeting == nil || !place.lowercased().contains("http") { lines.append(place.truncated(120)) }
    if let meeting { lines.append("\(meeting.service): \(meeting.web)") }
    if let organizer = e.organizer?.name.nonEmpty { lines.append("Organiser: \(organizer)") }
    let people = e.people.compactMap { $0.name.nonEmpty }
    if !people.isEmpty {
        lines.append("With: " + people.prefix(12).joined(separator: ", ") + (people.count > 12 ? " and \(people.count - 12) more" : ""))
    }
    if let calendar = e.calendar { lines.append("Calendar: \(calendar)") }
    return lines.joined(separator: "\n")
}

/// One event as a result row.
/// ↩ does the likeliest thing (join when the meeting is on, otherwise open it); ⌘↩ does the other.
func eventItem(_ e: Ev, showDay: Bool = true, titlePrefix: String? = nil, icon: [String: Any]? = nil, on shownDay: Date? = nil) -> Item {
    let meeting = MeetingDetector.detect(e)
    let joinable = canJoinNow(e, meeting)
    // In the agenda, something that began before today (a multi-day event) is listed under today.
    // The day view names the day it is showing instead.
    let day = shownDay ?? cal.startOfDay(for: max(e.startDate, today))

    var parts: [String] = []
    // The "Next"/"Now" row is about today unless it says otherwise.
    if showDay, !(titlePrefix != nil && day == today) { parts.append(Fmt.dayLabel(day)) }
    if let relative = relativeText(e) { parts.append(relative) }
    if let meeting {
        // When the row already leads with "↩ Join Teams", don't name the service twice.
        if !joinable { parts.append(meeting.service) }
    } else if let place = (e.place ?? e.location).nonEmpty, !place.lowercased().hasPrefix("http") {
        parts.append(place.replacingOccurrences(of: "\n", with: ", ").truncated(40))
    }
    if e.people.count > 1 { parts.append("\(e.people.count) people") }
    if let flag = replyFlag(e) { parts.append(flag) }
    if let calendar = e.calendar { parts.append(calendar) }
    let summary = parts.joined(separator: " · ")

    let openInCalendar: [String: String] = ["act": "cal", "eid": e.id]
    let join: [String: String] = meeting.map { ["act": "open", "url": $0.open, "web": $0.web] } ?? openInCalendar
    let primary = joinable ? join : openInCalendar
    let secondary = joinable ? openInCalendar : join
    let secondaryLabel = joinable || meeting == nil ? "Open in Calendar" : "Join \(meeting!.service) now"

    let text = details(e, meeting)
    var item: Item = [
        "uid": e.occurrenceKey,
        "title": (titlePrefix.map { "\($0) · " } ?? "") + (titlePrefix == nil ? "\(timeText(e))  \(e.name)" : e.name),
        "subtitle": (joinable ? "↩ Join \(meeting!.service) · " : "") + (titlePrefix == nil ? summary : "\(timeText(e)) · \(summary)"),
        "arg": e.id,
        "icon": icon ?? ["path": Render.badge(day: day, color: e.color)],
        "variables": primary,
        "text": ["copy": text, "largetype": text],
        "mods": [
            "cmd": ["subtitle": secondaryLabel, "arg": e.id, "variables": secondary],
            "alt": [
                "subtitle": meeting == nil ? "Copy event details" : "Copy the \(meeting!.service) link",
                "arg": e.id,
                "variables": ["act": "copy", "text": meeting?.web ?? text, "note": meeting == nil ? "Event details copied" : "Meeting link copied"],
            ],
            "ctrl": ["subtitle": "Show the whole day · \(Fmt.dayLabel(day))", "arg": e.id, "variables": ["act": "v:day", "date": Fmt.key(day)]],
        ] as [String: Any],
    ]
    if let web = meeting?.web { item["quicklookurl"] = web }
    return item
}

func matches(_ e: Ev, _ query: String) -> Bool {
    let haystack = [e.title, e.location ?? "", e.calendar ?? "", e.organizer?.name ?? "", e.people.compactMap { $0.name }.joined(separator: " ")]
        .joined(separator: " ").folded
    return query.folded.split(separator: " ").allSatisfy { haystack.contains($0) }
}

// MARK: - Agenda

func viewList(_ query: String) -> Never {
    // A row in "cal -" comes back here with the event to confirm in `confirm`.
    if let id = Env.vars["confirm"].nonEmpty { viewConfirmDelete(id, start: Env.vars["cstart"].flatMap { Double($0) }) }
    let q = query.trimmed
    if q.hasPrefix("+") { viewNewEvent(String(q.dropFirst())) }
    if q.hasPrefix("-") { viewDeleteSearch(String(q.dropFirst())) }
    let days = q.isEmpty ? Config.lookaheadDays : max(Config.lookaheadDays, 60)
    let (status, all) = Bridge.events(from: today, to: addDays(today, days + 1))
    guard status == "fullAccess" else { Alfred.emit(setupRows(status)) }
    Alerts.syncIfNeeded()

    // Finished meetings drop off; all-day events stay for their whole day.
    var events = all.filter { $0.endDate > now }
    if !q.isEmpty { events = events.filter { matches($0, q) } }
    let dayOf: (Ev) -> Date = { cal.startOfDay(for: max($0.startDate, today)) }
    events.sort { a, b in
        if dayOf(a) != dayOf(b) { return dayOf(a) < dayOf(b) }
        if a.allDay != b.allDay { return a.allDay }
        return (a.start, a.end) < (b.start, b.end)
    }

    var items: [Item] = []
    var refresh = false

    if q.isEmpty, let next = nextUp(events) {
        let meeting = MeetingDetector.detect(next)
        let joinable = canJoinNow(next, meeting)
        refresh = next.startDate.timeIntervalSince(now) < 20 * 60
        var row = eventItem(next, titlePrefix: next.inProgress ? "Now" : "Next", icon: Alfred.icon(joinable ? "video" : "next"))
        row["uid"] = "next-up"
        items.append(row)
    }

    // Several all-day entries on one day (holidays, birthdays) fold into a single row.
    var index = 0
    while index < events.count {
        let e = events[index]
        if e.allDay, q.isEmpty {
            var group = [e]
            while index + 1 < events.count, events[index + 1].allDay, dayOf(events[index + 1]) == dayOf(e) {
                index += 1
                group.append(events[index])
            }
            if group.count > 1 {
                let names = group.map { $0.name }
                let day = dayOf(e)
                items.append([
                    "uid": "allday-\(Fmt.key(day))",
                    "title": "All day  \(names[0].truncated(46)) +\(names.count - 1) more",
                    "subtitle": "\(Fmt.dayLabel(day)) · \(group.count) all-day events · ↩ show the day",
                    "arg": Fmt.key(day),
                    "icon": ["path": Render.badge(day: day, color: nil)],
                    "variables": ["act": "v:day", "date": Fmt.key(day)],
                    "text": ["copy": names.joined(separator: "\n"), "largetype": names.joined(separator: "\n")],
                ])
                index += 1
                continue
            }
        }
        items.append(eventItem(e))
        index += 1
    }

    if events.isEmpty {
        items.append(Alfred.info(q.isEmpty ? "Nothing scheduled in the next \(days) days" : "No events match “\(q)”",
                                 q.isEmpty ? "" : "Searched the next \(days) days"))
    }
    if q.isEmpty {
        items.append(Alfred.nav("Today’s schedule", "Free time, and time you can block", icon: "day", vars: ["act": "v:day", "date": Fmt.key(today)]))
        items.append(Alfred.nav("Week view", "Seven days at a glance", icon: "week", vars: ["act": "v:week", "week": Fmt.key(today)]))
        items.append(Alfred.nav("Month view", Fmt.monthYear(today), icon: "month", vars: ["act": "v:month", "month": Fmt.monthKey(today)]))
        // ↩ puts "+ " after the keyword; typing what and when then shows the new event.
        items.append(["title": "New event…", "subtitle": "Type + with what and when, e.g. + dentist tomorrow 15:00",
                      "autocomplete": "+ ", "valid": false, "icon": Alfred.icon("free")])
        items.append(["title": "Delete an event…", "subtitle": "Type - and part of its name, e.g. - dentist · asks before deleting",
                      "autocomplete": "- ", "valid": false, "icon": Alfred.icon("warning")])
    }
    Alfred.emit(items, rerun: refresh ? 5 : nil)
}

/// The meeting that matters right now: the one in progress, unless the next starts within ten minutes.
func nextUp(_ events: [Ev]) -> Ev? {
    let timed = events.filter { !$0.allDay && $0.endDate > now }.sorted { $0.start < $1.start }
    guard let first = timed.first else { return nil }
    if first.inProgress, let following = timed.dropFirst().first(where: { !$0.inProgress }),
       following.startDate.timeIntervalSince(now) <= 10 * 60 {
        return following
    }
    return first
}

// MARK: - One day

/// Accepts "tomorrow", "fri", "+3", "2026-11-18", "18/11"; anything else is treated as filter text.
func dayFromToken(_ raw: String) -> Date? {
    let token = raw.folded
    switch token {
    case "today", "tod", "now": return today
    case "tomorrow", "tom", "tmr", "tmrw": return addDays(today, 1)
    case "yesterday", "yest": return addDays(today, -1)
    default: break
    }
    if token.hasPrefix("+") || token.hasPrefix("-"), let offset = Int(token), abs(offset) < 3660 { return addDays(today, offset) }
    if token.count == 10, token.filter({ $0 == "-" }).count == 2, let date = Fmt.date(key: token) { return cal.startOfDay(for: date) }

    let pieces = token.split(whereSeparator: { "/.".contains($0) }).map { Int($0) }
    if (2...3).contains(pieces.count), let day = pieces[0], let month = pieces[1] {
        var parts = DateComponents()
        parts.day = day
        parts.month = month
        parts.year = pieces.count == 3 ? pieces[2].map { $0 < 100 ? 2000 + $0 : $0 } : cal.component(.year, from: today)
        if let date = cal.date(from: parts), cal.component(.day, from: date) == day { return cal.startOfDay(for: date) }
    }

    if token.count >= 3 {
        let english = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let local = cal.weekdaySymbols.map { $0.folded }
        for weekday in 0..<7 where english[weekday].hasPrefix(token) || (local.count == 7 && local[weekday].hasPrefix(token)) {
            let ahead = (weekday + 1 - cal.component(.weekday, from: today) + 7) % 7
            return addDays(today, ahead)
        }
    }
    return nil
}

func freeGaps(on day: Date, _ events: [Ev]) -> [(start: Date, end: Date)] {
    guard day >= today else { return [] }
    var windowStart = at(day, hour: Config.workStart)
    let windowEnd = at(day, hour: Config.workEnd)
    if day == today {
        let step = 5.0 * 60
        windowStart = max(windowStart, Date(timeIntervalSince1970: (now.timeIntervalSince1970 / step).rounded(.up) * step))
    }
    guard windowEnd > windowStart else { return [] }

    let busy = events.filter { !$0.allDay && $0.availability != "free" }
        .map { (max($0.startDate, windowStart), min($0.endDate, windowEnd)) }
        .filter { $0.0 < $0.1 }
        .sorted { $0.0 < $1.0 }
    var gaps: [(start: Date, end: Date)] = []
    var cursor = windowStart
    for (start, end) in busy {
        if start.timeIntervalSince(cursor) >= 30 * 60 { gaps.append((cursor, start)) }
        cursor = max(cursor, end)
    }
    if windowEnd.timeIntervalSince(cursor) >= 30 * 60 { gaps.append((cursor, windowEnd)) }
    return gaps
}

func viewDay(_ query: String) -> Never {
    var filter = query.trimmed
    var day = today
    let words = filter.split(separator: " ", maxSplits: 1).map(String.init)
    if let first = words.first, let parsed = dayFromToken(first) {
        day = parsed
        filter = words.count > 1 ? words[1].trimmed : ""
    } else if let key = Env.vars["date"].nonEmpty, let stored = Fmt.date(key: key) {
        day = cal.startOfDay(for: stored)
    }

    let next = addDays(day, 1), previous = addDays(day, -1)
    let (status, all) = Bridge.events(from: day, to: next)
    guard status == "fullAccess" else { Alfred.emit(setupRows(status)) }
    let events = filter.isEmpty ? all : all.filter { matches($0, filter) }
    let timed = events.filter { !$0.allDay }
    let busySeconds = timed.reduce(0.0) { $0 + min($1.end, next.timeIntervalSince1970) - max($1.start, day.timeIntervalSince1970) }

    var summary = events.isEmpty ? "Nothing scheduled" : "\(events.count) event\(events.count == 1 ? "" : "s")"
    if busySeconds > 0 { summary += " · \(Fmt.duration(busySeconds)) in meetings" }
    summary += " · week \(Fmt.weekNumber(day))"

    let dayVars: (Date) -> [String: String] = { ["act": "v:day", "date": Fmt.key($0)] }
    var items: [Item] = [[
        "uid": "day-header",
        "title": Fmt.longDay(day) + (day == today ? " · Today" : ""),
        "subtitle": summary,
        "arg": Fmt.key(day),
        "icon": ["path": Render.badge(day: day, color: nil)],
        "variables": ["act": "calday", "date": Fmt.key(day)],
        "mods": [
            "alt": ["subtitle": "Next day · \(Fmt.dayMonth(next))", "arg": Fmt.key(next), "variables": dayVars(next)],
            "ctrl": ["subtitle": "Previous day · \(Fmt.dayMonth(previous))", "arg": Fmt.key(previous), "variables": dayVars(previous)],
        ] as [String: Any],
    ]]

    var timeline: [(when: Date, item: Item)] = []
    for e in timed where day != today || e.endDate > now || !filter.isEmpty {
        timeline.append((e.startDate, eventItem(e, showDay: false, on: day)))
    }
    if filter.isEmpty {
        for gap in freeGaps(on: day, all) {
            timeline.append((gap.start, [
                "uid": "gap-\(Int(gap.start.timeIntervalSince1970))",
                "title": "Free  \(Fmt.range(gap.start, gap.end))",
                "subtitle": "\(Fmt.duration(gap.end.timeIntervalSince(gap.start))) · ↩ block this time",
                "arg": "gap",
                "icon": Alfred.icon("free"),
                "variables": ["act": "v:block", "slot": "\(Fmt.slot(gap.start))~\(Fmt.slot(gap.end))"],
            ]))
        }
    }
    items += events.filter { $0.allDay }.map { eventItem($0, showDay: false, on: day) }
    items += timeline.sorted { $0.when < $1.when }.map { $0.item }

    if day == today, filter.isEmpty {
        let finished = timed.filter { $0.endDate <= now }.count
        if finished > 0 { items.append(Alfred.info("\(finished) earlier event\(finished == 1 ? "" : "s") finished", "Type a word to search the whole day")) }
    }
    if filter.isEmpty {
        if day >= today {
            items.append(Alfred.nav("Block time…", "Workday, morning or afternoon", icon: "free", vars: ["act": "v:block", "slot": Fmt.key(day)]))
        }
        items.append(Alfred.nav("Next day", Fmt.longDay(next), icon: "forward", vars: dayVars(next)))
        items.append(Alfred.nav("Previous day", Fmt.longDay(previous), icon: "back", vars: dayVars(previous)))
    } else if events.isEmpty {
        items.append(Alfred.info("No events match “\(filter)”", Fmt.longDay(day)))
    }
    Alfred.emit(items)
}

// MARK: - Join

func viewJoin(_ query: String) -> Never {
    let q = query.trimmed
    let (status, all) = Bridge.events(from: now.addingTimeInterval(-12 * 3600), to: addDays(today, Config.lookaheadDays + 1))
    guard status == "fullAccess" else { Alfred.emit(setupRows(status)) }
    Alerts.syncIfNeeded()

    let linked = all.filter { !$0.allDay && $0.endDate > now && MeetingDetector.detect($0) != nil }
    let window = Double(Config.joinWindow) * 60
    // The meeting whose start is closest to now comes first, so ↩ joins the one you are due in.
    let current = linked.filter { now >= $0.startDate.addingTimeInterval(-window) }
        .sorted { abs($0.startDate.timeIntervalSince(now)) < abs($1.startDate.timeIntervalSince(now)) }
    let later = linked.filter { now < $0.startDate.addingTimeInterval(-window) && $0.startDate < addDays(today, 1) }
    var candidates = current + later
    if candidates.isEmpty, let next = linked.first { candidates = [next] }
    if !q.isEmpty { candidates = candidates.filter { matches($0, q) } }

    guard !candidates.isEmpty else {
        Alfred.emit([Alfred.info(q.isEmpty ? "No meetings with a link coming up" : "No meeting matches “\(q)”",
                                 q.isEmpty ? "Checked the next \(Config.lookaheadDays) days" : "Press ⎋ to close")])
    }

    let items: [Item] = candidates.map { e in
        guard let meeting = MeetingDetector.detect(e) else { return eventItem(e) }
        let when: String
        if e.inProgress {
            when = "started \(Fmt.duration(now.timeIntervalSince(e.startDate))) ago · until \(Fmt.time(e.endDate))"
        } else {
            when = "starts \(Fmt.until(e.startDate)) · \(timeText(e))"
        }
        var row = eventItem(e, icon: Alfred.icon("video"))
        row["title"] = "Join · \(e.name)"
        row["subtitle"] = "\(meeting.service) · \(when)" + (cal.isDate(e.startDate, inSameDayAs: now) ? "" : " · \(Fmt.dayLabel(e.startDate))")
        row["variables"] = ["act": "open", "url": meeting.open, "web": meeting.web]
        if var mods = row["mods"] as? [String: Any] {
            mods["cmd"] = ["subtitle": "Open in Calendar", "arg": e.id, "variables": ["act": "cal", "eid": e.id]]
            row["mods"] = mods
        }
        return row
    }
    Alfred.emit(items, rerun: current.isEmpty ? nil : 5)
}

// MARK: - Block time

struct CalendarInfo: Codable {
    var id: String
    var title: String
    var source: String?
    var writable: Bool?
}

struct CalendarsReply: Codable {
    var status: String?
    var calendars: [CalendarInfo]?
    var defaultCalendarId: String?
}

/// Calendars that can take new events, and the id of the system's default one.
func writableCalendars() -> (calendars: [CalendarInfo], defaultId: String?)? {
    var data = Data()
    if let fixture = Env.vars["AGENDA_FIXTURE"] {
        // A fixture file carries a calendar list next to its events.
        data = (try? Data(contentsOf: URL(fileURLWithPath: fixture))) ?? Data()
    } else {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Bridge.path)
        process.arguments = ["calendars"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
    }
    guard let reply = try? JSONDecoder().decode(CalendarsReply.self, from: data) else { return nil }
    return ((reply.calendars ?? []).filter { $0.writable ?? false }, reply.defaultCalendarId)
}

/// "Calendar (Exchange)": the account tells apart calendars that share a name.
func calendarLabel(_ c: CalendarInfo) -> String { c.source.nonEmpty.map { "\(c.title) (\($0))" } ?? c.title }

/// Where new events and blocks go: the calendar named in the settings ("Calendar", or
/// "Calendar (Exchange)" when two share a name), otherwise the system default.
func preferredCalendar(_ calendars: [CalendarInfo], defaultId: String?) -> CalendarInfo? {
    let wanted = Config.blockCalendar.folded
    let match = wanted.isEmpty ? nil : (calendars.first { calendarLabel($0).folded == wanted } ?? calendars.first { $0.title.folded == wanted })
    return match ?? calendars.first { $0.id == defaultId } ?? calendars.first
}

func blockCalendar() -> (id: String, label: String)? {
    guard let found = writableCalendars(), let chosen = preferredCalendar(found.calendars, defaultId: found.defaultId) else { return nil }
    return (chosen.id, calendarLabel(chosen))
}

func viewBlock(_ query: String) -> Never {
    let title = query.trimmed.nonEmpty ?? Config.blockTitle
    let slot = Env.vars["slot"] ?? ""
    var options: [(label: String, start: Date, end: Date)] = []

    if slot.contains("~") {
        let ends = slot.split(separator: "~").map(String.init)
        if ends.count == 2, let start = Fmt.date(slot: ends[0]), let end = Fmt.date(slot: ends[1]), end > start {
            options.append(("Whole gap", start, end))
            for (label, minutes) in [("First 30 minutes", 30.0), ("First hour", 60.0), ("First 2 hours", 120.0)] where end.timeIntervalSince(start) > minutes * 60 {
                options.append((label, start, start.addingTimeInterval(minutes * 60)))
            }
        }
    } else {
        let day = Fmt.date(key: slot).map { cal.startOfDay(for: $0) } ?? today
        let open = at(day, hour: Config.workStart), close = at(day, hour: Config.workEnd), noon = at(day, hour: 12)
        // On today, a block starts at the next quarter hour rather than in the past.
        let step = 15.0 * 60
        let earliest = day == today ? Date(timeIntervalSince1970: (now.timeIntervalSince1970 / step).rounded(.up) * step) : open
        let presets: [(String, Date, Date)] = [("Workday", open, close), ("Morning", open, min(noon, close)), ("Afternoon", max(noon, open), close)]
        for (label, start, end) in presets {
            let from = max(start, earliest)
            if end.timeIntervalSince(from) >= step { options.append((label, from, end)) }
        }
    }

    guard !options.isEmpty else { Alfred.emit([Alfred.info("No time left to block", "Working hours for that day are over")]) }
    guard let target = blockCalendar() else { Alfred.emit([Alfred.info("No calendar can take new events", "Check the calendars in the Calendar app", icon: "warning")]) }

    let items: [Item] = options.map { option in
        [
            "title": "\(option.label)  \(Fmt.range(option.start, option.end))",
            "subtitle": "Adds “\(title)” to \(target.label) · \(Fmt.dayLabel(option.start)) · \(Fmt.duration(option.end.timeIntervalSince(option.start))) · type to rename",
            "arg": option.label,
            "icon": Alfred.icon("free"),
            "variables": [
                "act": "block", "title": title, "calid": target.id,
                "start": String(option.start.timeIntervalSince1970), "end": String(option.end.timeIntervalSince1970),
            ],
        ]
    }
    Alfred.emit(items)
}
