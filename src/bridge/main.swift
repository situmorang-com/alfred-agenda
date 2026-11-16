// agenda-calendar — the only part of the Agenda workflow that touches your calendar.
//
// It is deliberately small and rarely changes: macOS ties the "Full Calendar Access"
// grant to this exact binary, so rebuilding it means being asked for access again.
// Everything that formats, filters or draws lives in the separate `agenda` binary.
//
// Commands (all print JSON on stdout):
//   status                      -> {"status": "..."}            never prompts
//   auth                        -> asks macOS for full access, then prints status
//   calendars                   -> {"status": "...", "calendars": [...]}
//   events <fromEpoch> <toEpoch>-> {"status": "...", "events": [...]}
//   event <identifier>          -> the same shape, for one event
//   create                     -> reads an event as JSON on stdin, saves it
//   delete                      -> reads {"id", "start", "span"} on stdin, removes that event
//   version                     -> {"version": N}

import CoreGraphics
import EventKit
import Foundation

let bridgeVersion = 2

// MARK: - Own the permission instead of borrowing the launcher's

// A program started by another app normally inherits that app's privacy identity
// (Alfred's, in this case, and Alfred only declares the pre-macOS-14 calendar key,
// which macOS now treats as add-only). Re-launching ourselves with "responsibility
// disclaimed" makes macOS evaluate calendar access against this binary instead.
let childMarker = "AGENDA_CALENDAR_CHILD"

func spawnSelfDisclaimed() -> Int32? {
    typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    // Looked up at runtime so a future macOS without this symbol degrades to
    // "run in place" rather than failing to launch.
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim"),
          let exe = Bundle.main.executablePath
    else { return nil }
    let disclaim = unsafeBitCast(symbol, to: Disclaim.self)

    var attr: posix_spawnattr_t?
    guard posix_spawnattr_init(&attr) == 0 else { return nil }
    defer { posix_spawnattr_destroy(&attr) }
    guard disclaim(&attr, 1) == 0 else { return nil }

    var env = ProcessInfo.processInfo.environment
    env[childMarker] = "1"
    let argv: [UnsafeMutablePointer<CChar>?] = ([exe] + CommandLine.arguments.dropFirst()).map { strdup($0) } + [nil]
    let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]

    var pid: pid_t = 0
    guard posix_spawn(&pid, exe, nil, &attr, argv, envp) == 0 else { return nil }
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    return (status & 0x7f) == 0 ? (status >> 8) & 0xff : 1
}

if ProcessInfo.processInfo.environment[childMarker] == nil, let code = spawnSelfDisclaimed() {
    exit(code)
}

// MARK: - Output helpers

func emit(_ object: [String: Any]) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: ["error": message, "status": statusName()])) ?? Data()
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(code)
}

func statusName() -> String {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .fullAccess: return "fullAccess"
    case .writeOnly: return "writeOnly"
    @unknown default: return "unknown"
    }
}

func hex(_ color: CGColor?) -> String {
    guard let color,
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let rgb = color.converted(to: space, intent: .defaultIntent, options: nil),
          let c = rgb.components, c.count >= 3
    else { return "#8E8E93" }
    func byte(_ v: CGFloat) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
    return String(format: "#%02X%02X%02X", byte(c[0]), byte(c[1]), byte(c[2]))
}

// MARK: - Mapping EventKit to plain JSON

func participantStatus(_ s: EKParticipantStatus) -> String {
    switch s {
    case .accepted: return "accepted"
    case .declined: return "declined"
    case .tentative: return "tentative"
    case .pending: return "pending"
    case .delegated: return "delegated"
    case .completed: return "completed"
    case .inProcess: return "inProcess"
    case .unknown: return "unknown"
    @unknown default: return "unknown"
    }
}

func participant(_ p: EKParticipant) -> [String: Any] {
    var d: [String: Any] = ["status": participantStatus(p.participantStatus), "me": p.isCurrentUser]
    if let name = p.name { d["name"] = name }
    let address = p.url.absoluteString
    if address.lowercased().hasPrefix("mailto:") { d["email"] = String(address.dropFirst(7)) }
    switch p.participantRole {
    case .optional: d["role"] = "optional"
    case .chair: d["role"] = "chair"
    case .nonParticipant: d["role"] = "nonParticipant"
    default: d["role"] = "required"
    }
    switch p.participantType {
    case .room: d["type"] = "room"
    case .resource: d["type"] = "resource"
    case .group: d["type"] = "group"
    default: d["type"] = "person"
    }
    return d
}

func sourceType(_ t: EKSourceType) -> String {
    switch t {
    case .local: return "local"
    case .exchange: return "exchange"
    case .calDAV: return "caldav"
    case .mobileMe: return "icloud"
    case .subscribed: return "subscribed"
    case .birthdays: return "birthdays"
    @unknown default: return "other"
    }
}

func calendarJSON(_ c: EKCalendar) -> [String: Any] {
    [
        "id": c.calendarIdentifier,
        "title": c.title,
        "color": hex(c.cgColor),
        "source": c.source?.title ?? "",
        "sourceType": c.source.map { sourceType($0.sourceType) } ?? "other",
        "writable": c.allowsContentModifications,
        "subscribed": c.isSubscribed,
    ]
}

func eventJSON(_ e: EKEvent) -> [String: Any] {
    var d: [String: Any] = [
        "id": e.eventIdentifier ?? "",
        "itemId": e.calendarItemIdentifier,
        "title": e.title ?? "",
        "start": e.startDate.timeIntervalSince1970,
        "end": e.endDate.timeIntervalSince1970,
        "allDay": e.isAllDay,
        "recurring": e.hasRecurrenceRules,
        "detached": e.isDetached,
        "birthday": e.birthdayContactIdentifier != nil,
    ]
    if let c = e.calendar {
        d["calendarId"] = c.calendarIdentifier
        d["calendar"] = c.title
        d["color"] = hex(c.cgColor)
        d["source"] = c.source?.title ?? ""
        d["sourceType"] = c.source.map { sourceType($0.sourceType) } ?? "other"
    }
    if let v = e.location, !v.isEmpty { d["location"] = v }
    if let v = e.structuredLocation?.title, !v.isEmpty { d["place"] = v }
    if let v = e.url?.absoluteString, !v.isEmpty { d["url"] = v }
    if let v = e.notes, !v.isEmpty { d["notes"] = v }
    if let v = e.timeZone?.identifier { d["tz"] = v }
    if let v = e.creationDate { d["created"] = v.timeIntervalSince1970 }
    if let v = e.lastModifiedDate { d["modified"] = v.timeIntervalSince1970 }
    if let v = e.occurrenceDate { d["occurrence"] = v.timeIntervalSince1970 }
    if let v = e.calendarItemExternalIdentifier, !v.isEmpty { d["externalId"] = v }

    switch e.status {
    case .confirmed: d["status"] = "confirmed"
    case .tentative: d["status"] = "tentative"
    case .canceled: d["status"] = "canceled"
    default: d["status"] = "none"
    }
    switch e.availability {
    case .busy: d["availability"] = "busy"
    case .free: d["availability"] = "free"
    case .tentative: d["availability"] = "tentative"
    case .unavailable: d["availability"] = "unavailable"
    default: d["availability"] = "unknown"
    }

    if let organizer = e.organizer {
        var o: [String: Any] = ["me": organizer.isCurrentUser]
        if let name = organizer.name { o["name"] = name }
        d["organizer"] = o
    }
    if let attendees = e.attendees, !attendees.isEmpty {
        d["attendees"] = attendees.map(participant)
        if let mine = attendees.first(where: { $0.isCurrentUser }) {
            d["myStatus"] = participantStatus(mine.participantStatus)
        }
    }
    return d
}

// MARK: - Commands

let args = Array(CommandLine.arguments.dropFirst())
let store = EKEventStore()

func requireFullAccess() {
    if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
        emit(["status": statusName()])
    }
}

switch args.first ?? "status" {
case "version":
    emit(["version": bridgeVersion])

case "status":
    emit(["status": statusName(), "version": bridgeVersion])

case "auth":
    // Only this command may show the macOS permission prompt.
    if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
        let done = DispatchSemaphore(value: 0)
        store.requestFullAccessToEvents { _, _ in done.signal() }
        done.wait()
    }
    emit(["status": statusName(), "version": bridgeVersion])

case "calendars":
    requireFullAccess()
    let calendars = store.calendars(for: .event).map(calendarJSON)
    var out: [String: Any] = ["status": "fullAccess", "calendars": calendars]
    if let d = store.defaultCalendarForNewEvents { out["defaultCalendarId"] = d.calendarIdentifier }
    emit(out)

case "events":
    requireFullAccess()
    guard args.count >= 3, let from = Double(args[1]), let to = Double(args[2]), to > from else {
        fail("usage: events <fromEpoch> <toEpoch>")
    }
    let predicate = store.predicateForEvents(
        withStart: Date(timeIntervalSince1970: from),
        end: Date(timeIntervalSince1970: to),
        calendars: nil)
    let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    emit(["status": "fullAccess", "events": events.map(eventJSON)])

case "event":
    requireFullAccess()
    guard args.count >= 2, let event = store.event(withIdentifier: args[1]) else {
        emit(["status": "fullAccess", "events": []])
    }
    emit(["status": "fullAccess", "events": [eventJSON(event)]])

case "create":
    requireFullAccess()
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let spec = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
          let title = spec["title"] as? String,
          let start = spec["start"] as? Double,
          let end = spec["end"] as? Double, end > start
    else { fail("create expects JSON with title, start and end (epoch seconds)") }

    let event = EKEvent(eventStore: store)
    event.title = title
    event.startDate = Date(timeIntervalSince1970: start)
    event.endDate = Date(timeIntervalSince1970: end)
    event.isAllDay = (spec["allDay"] as? Bool) ?? false
    if let v = spec["notes"] as? String, !v.isEmpty { event.notes = v }
    if let v = spec["location"] as? String, !v.isEmpty { event.location = v }
    if let v = spec["url"] as? String, let u = URL(string: v) { event.url = u }
    if let v = spec["availability"] as? String {
        event.availability = v == "free" ? .free : (v == "tentative" ? .tentative : .busy)
    }
    if let minutes = spec["alarmMinutes"] as? Double {
        event.addAlarm(EKAlarm(relativeOffset: -minutes * 60))
    }

    let wanted = (spec["calendarId"] as? String) ?? ""
    let wantedTitle = ((spec["calendar"] as? String) ?? "").lowercased()
    let writable = store.calendars(for: .event).filter { $0.allowsContentModifications }
    let target = writable.first { $0.calendarIdentifier == wanted }
        ?? (wantedTitle.isEmpty ? nil : writable.first { $0.title.lowercased() == wantedTitle })
        ?? store.defaultCalendarForNewEvents
    guard let target else { fail("no writable calendar found") }
    event.calendar = target

    do {
        try store.save(event, span: .thisEvent, commit: true)
        emit(["status": "fullAccess", "ok": true, "id": event.eventIdentifier ?? "", "calendar": target.title])
    } catch {
        fail("could not save the event: \(error.localizedDescription)")
    }

case "delete":
    // {"id": event identifier, "start": the occurrence's start (epoch seconds), "span": "this"
    // or "future"}. It refuses events with other people: removing one would cancel or decline
    // it for everyone, which is a job for Calendar or Outlook.
    requireFullAccess()
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let spec = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
          let id = spec["id"] as? String, !id.isEmpty
    else { fail("delete expects JSON with id and start") }

    let found: EKEvent?
    if let start = spec["start"] as? Double {
        // All occurrences of a repeating event share the identifier; the start picks one.
        // Without an exact match nothing is deleted, rather than some other occurrence.
        let when = Date(timeIntervalSince1970: start)
        let window = store.predicateForEvents(withStart: when.addingTimeInterval(-60), end: when.addingTimeInterval(60), calendars: nil)
        found = store.events(matching: window).first { $0.eventIdentifier == id && abs($0.startDate.timeIntervalSince(when)) < 1 }
    } else {
        found = store.event(withIdentifier: id)
    }
    guard let event = found else { fail("that event has moved or is gone") }
    guard event.calendar.allowsContentModifications else { fail("its calendar is read-only") }
    if (event.attendees ?? []).contains(where: { !$0.isCurrentUser }) { fail("it has other people; delete it in Calendar or Outlook") }

    let calendarTitle = event.calendar.title
    do {
        try store.remove(event, span: (spec["span"] as? String) == "future" ? .futureEvents : .thisEvent, commit: true)
        emit(["status": "fullAccess", "ok": true, "calendar": calendarTitle])
    } catch {
        fail("could not delete the event: \(error.localizedDescription)")
    }

default:
    fail("unknown command", code: 2)
}
