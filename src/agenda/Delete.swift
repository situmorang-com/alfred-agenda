// Delete.swift — "cal - dentist" lists the events that match. ↩ on one opens a confirmation
// whose first, preselected row keeps the event; only the row below it deletes. Events with
// other people, or in read-only calendars, aren't offered: removing a meeting would cancel or
// decline it for everyone, so ↩ opens those in Calendar instead.

import Foundation

/// "Calendar (iCloud)": the account tells apart calendars that share a name.
func eventCalendarLabel(_ e: Ev) -> String {
    let name = e.calendar ?? "Calendar"
    return e.source.nonEmpty.map { "\(name) (\($0))" } ?? name
}

/// Why an event can't be deleted from here, or nil when it can.
func deleteBlocker(_ e: Ev, writable: Set<String>) -> String? {
    if let id = e.calendarId, !writable.contains(id) { return "read-only calendar" }
    let others = e.people.filter { $0.me != true }.count
    if others > 0 { return "has \(others) other \(others == 1 ? "person" : "people"): delete it in Calendar or Outlook" }
    if e.organizer?.me == false { return "an invitation: decline it in Calendar or Outlook" }
    return nil
}

private func whenText(_ e: Ev) -> String {
    e.allDay ? "\(Fmt.dayLabel(e.startDate)) · all day" : "\(Fmt.dayLabel(e.startDate)) \(Fmt.range(e.startDate, e.endDate))"
}

/// After "-": the matching events from a week ago to 60 days ahead, coming ones first.
func viewDeleteSearch(_ text: String) -> Never {
    let q = text.trimmed
    let (status, all) = Bridge.events(from: addDays(today, -7), to: addDays(today, 61))
    guard status == "fullAccess" else { Alfred.emit(setupRows(status)) }
    let writable = Set((writableCalendars()?.calendars ?? []).map { $0.id })

    let found = q.isEmpty ? all.filter { $0.endDate > now && $0.startDate < addDays(today, Config.lookaheadDays + 1) } : all.filter { matches($0, q) }
    let coming = found.filter { $0.endDate > now }.sorted { $0.start < $1.start }
    let past = found.filter { $0.endDate <= now }.sorted { $0.start > $1.start }

    var items: [Item] = []
    if q.isEmpty {
        items.append(Alfred.info("Delete an event", "Type part of its name, e.g. cal - dentist · ↩ on an event asks before deleting", icon: "warning"))
    } else if found.isEmpty {
        items.append(Alfred.info("No events match “\(q)”", "Searched from a week ago to 60 days ahead"))
    }
    for e in (coming + past).prefix(30) {
        var row: Item = ["uid": "delete-\(e.occurrenceKey)", "title": e.name, "arg": e.name,
                         "icon": ["path": Render.badge(day: e.startDate, color: e.color)]]
        if let blocker = deleteBlocker(e, writable: writable) {
            row["subtitle"] = "\(whenText(e)) · \(blocker) · ↩ opens it"
            row["variables"] = ["act": "cal", "eid": e.id]
        } else {
            row["subtitle"] = "\(whenText(e)) · \(eventCalendarLabel(e)) · ↩ asks before deleting"
            // Back into the agenda's own Script Filter, which shows the confirmation.
            row["variables"] = ["act": "v:agenda", "confirm": e.id, "cstart": String(e.start)]
        }
        items.append(row)
    }
    Alfred.emit(items)
}

/// The confirmation. "Keep it" comes first, so a stray ↩ deletes nothing.
func viewConfirmDelete(_ id: String, start: Double?) -> Never {
    let around = start.map { Date(timeIntervalSince1970: $0) } ?? now
    let (status, events) = Bridge.events(from: around.addingTimeInterval(-60), to: around.addingTimeInterval(60))
    guard status == "fullAccess" else { Alfred.emit(setupRows(status)) }
    let back: Item = ["title": "Keep it", "subtitle": "Back to the agenda · nothing is deleted", "arg": "keep",
                      "icon": Alfred.icon("back"), "variables": ["act": "v:agenda", "confirm": "", "cstart": ""]]
    guard let e = events.first(where: { event in event.id == id && (start.map { abs(event.start - $0) < 1 } ?? true) }) else {
        Alfred.emit([Alfred.info("That event has moved or is gone", "Nothing was deleted", icon: "warning"), back])
    }
    let writable = Set((writableCalendars()?.calendars ?? []).map { $0.id })
    if let blocker = deleteBlocker(e, writable: writable) {
        Alfred.emit([Alfred.info("“\(e.name)” can’t be deleted here", blocker, icon: "warning"), back])
    }

    let label = eventCalendarLabel(e)
    let repeating = e.recurring == true
    let target: [String: String] = ["act": "delete", "eid": e.id, "start": String(e.start), "title": e.name, "callabel": label]
    var items: [Item] = [back, [
        "title": "Delete “\(e.name)”",
        "subtitle": (repeating ? "Only this one · " : "") + "\(whenText(e)) · \(label) · can’t be undone from Alfred",
        "arg": "delete", "icon": Alfred.icon("warning"),
        "variables": target.merging(["span": "this"]) { $1 },
    ]]
    if repeating {
        let day = Fmt.dayLabel(e.startDate)
        items.append([
            "title": "Delete it from \(["Today", "Tomorrow", "Yesterday"].contains(day) ? day.lowercased() : day) on",
            "subtitle": "This one and every later one in the series · \(label)",
            "arg": "delete", "icon": Alfred.icon("warning"),
            "variables": target.merging(["span": "future"]) { $1 },
        ])
    }
    Alfred.emit(items)
}
