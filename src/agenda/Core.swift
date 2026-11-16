// Core.swift — environment, settings, the event model and the call into the calendar bridge.

import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
    /// Lower-cased and accent-free, for forgiving text matching.
    var folded: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    func truncated(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(max(0, limit - 1))).trimmed + "…"
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? { self?.trimmed.nonEmpty }
}

// MARK: - Environment

enum Env {
    static let vars = ProcessInfo.processInfo.environment
    static let exe = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).resolvingSymlinksInPath()
    /// The workflow folder: this binary lives in <workflow>/bin/.
    static let workflowDir = exe.deletingLastPathComponent().deletingLastPathComponent()
    static let bundleID = vars["alfred_workflow_bundleid"].nonEmpty ?? "com.situmorang.agenda"
    static let insideAlfred = vars["alfred_workflow_bundleid"] != nil
    static let cacheDir = directory(vars["alfred_workflow_cache"], "Library/Caches/com.runningwithcrayons.Alfred/Workflow Data")
    static let dataDir = directory(vars["alfred_workflow_data"], "Library/Application Support/Alfred/Workflow Data")

    /// "Now" can be pinned with AGENDA_NOW (ISO 8601) so views can be tested deterministically.
    static let now: Date = {
        if let pinned = vars["AGENDA_NOW"], let date = ISO8601DateFormatter().date(from: pinned) { return date }
        return Date()
    }()

    /// Whether Alfred's current theme is dark, so drawn tiles use legible text colours.
    static let dark: Bool = {
        if let forced = vars["AGENDA_THEME"] { return forced != "light" }
        guard let background = vars["alfred_theme_background"] else { return true }
        let parts = background.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
        guard parts.count >= 3 else { return true }
        return (0.299 * parts[0] + 0.587 * parts[1] + 0.114 * parts[2]) / 255 < 0.55
    }()

    private static func directory(_ fromEnv: String?, _ fallback: String) -> URL {
        let url = fromEnv.nonEmpty.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(fallback).appendingPathComponent(bundleID)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - Settings

/// Settings come from Alfred's Workflow Configuration. Alfred passes them as environment
/// variables; the background alert job runs outside Alfred, so it reads the same values
/// straight from the workflow's info.plist (defaults) and prefs.plist (your changes).
enum Config {
    private static let fileValues: [String: String] = {
        var values: [String: String] = [:]
        func text(_ any: Any?) -> String? {
            switch any {
            case let s as String: return s
            case let n as NSNumber:
                return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "1" : "0") : n.stringValue
            default: return nil
            }
        }
        if let info = NSDictionary(contentsOf: Env.workflowDir.appendingPathComponent("info.plist")),
           let fields = info["userconfigurationconfig"] as? [[String: Any]] {
            for field in fields {
                guard let name = field["variable"] as? String, let config = field["config"] as? [String: Any] else { continue }
                if let value = text(config["default"]) ?? text(config["defaultvalue"]) { values[name] = value }
            }
        }
        if let prefs = NSDictionary(contentsOf: Env.workflowDir.appendingPathComponent("prefs.plist")) as? [String: Any] {
            for (name, value) in prefs { if let value = text(value) { values[name] = value } }
        }
        return values
    }()

    static func string(_ key: String, _ fallback: String = "") -> String {
        if let value = Env.vars[key] { return value }
        return fileValues[key] ?? fallback
    }

    static func int(_ key: String, _ fallback: Int) -> Int {
        Double(string(key).trimmed).map { Int($0.rounded()) } ?? fallback
    }

    static func bool(_ key: String, _ fallback: Bool) -> Bool {
        let value = string(key).trimmed.lowercased()
        return value.isEmpty ? fallback : ["1", "true", "yes"].contains(value)
    }

    static var lookaheadDays: Int { min(90, max(1, int("lookahead_days", 14))) }
    static var workStart: Int { min(23, max(0, int("work_start", 8))) }
    static var workEnd: Int { max(workStart + 1, min(24, int("work_end", 18))) }
    /// 1 = Sunday, 2 = Monday, nil = follow the system setting.
    static var weekStart: Int? { ["1": 1, "2": 2][string("week_start", "system")] }
    static var showDeclined: Bool { bool("show_declined", false) }
    static var ignoredCalendars: Set<String> {
        Set(string("ignored_calendars").split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { String($0).trimmed.folded }.filter { !$0.isEmpty })
    }
    /// prompt | notify | auto | off
    static var alertStyle: String {
        let style = string("alert_style", "prompt")
        return ["prompt", "notify", "auto", "off"].contains(style) ? style : "prompt"
    }
    static var alertLead: Int { min(30, max(0, int("alert_lead", 1))) }
    static var alertLinksOnly: Bool { bool("alert_links_only", true) }
    static var teamsApp: Bool { bool("teams_app", true) }
    static var zoomApp: Bool { bool("zoom_app", true) }
    static var blockTitle: String { string("block_title", "Focus time").trimmed.nonEmpty ?? "Focus time" }
    static var blockCalendar: String { string("block_calendar").trimmed }
    /// Minutes before the start from which ↩ joins a meeting instead of opening it.
    static let joinWindow = 15
}

// MARK: - Time

let now = Env.now

let cal: Calendar = {
    var calendar = Calendar.current
    if let first = Config.weekStart { calendar.firstWeekday = first }
    return calendar
}()

let today = cal.startOfDay(for: now)

func addDays(_ date: Date, _ count: Int) -> Date { cal.date(byAdding: .day, value: count, to: date) ?? date }
func startOfWeek(_ date: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date) }
func startOfMonth(_ date: Date) -> Date { cal.dateInterval(of: .month, for: date)?.start ?? cal.startOfDay(for: date) }
func at(_ day: Date, hour: Int) -> Date { cal.date(byAdding: .hour, value: hour, to: cal.startOfDay(for: day)) ?? day }

enum Fmt {
    private static func localized(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = .current
        f.calendar = cal
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static func fixed(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f
    }

    static let uses12Hour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
    private static let compactFormatter: DateFormatter = {
        let f = localized(uses12Hour ? "hmma" : "Hm")
        f.amSymbol = "a"
        f.pmSymbol = "p"
        return f
    }()
    private static let keyFormatter = fixed("yyyy-MM-dd")
    private static let monthKeyFormatter = fixed("yyyy-MM")
    private static let slotFormatter = fixed("yyyy-MM-dd'T'HH:mm")
    private static let weekdayFormatter = localized("EEE")
    private static let dayMonthFormatter = localized("EEEdMMM")
    private static let longDayFormatter = localized("EEEEdMMMM")
    private static let monthYearFormatter = localized("MMMMyyyy")

    static func time(_ d: Date) -> String { timeFormatter.string(from: d) }
    /// "09:00" or "9:00a": short enough for a calendar tile.
    static func compact(_ d: Date) -> String {
        compactFormatter.string(from: d).filter { !$0.isWhitespace }
    }
    static func range(_ a: Date, _ b: Date) -> String { "\(time(a)) – \(time(b))" }
    static func key(_ d: Date) -> String { keyFormatter.string(from: d) }
    static func monthKey(_ d: Date) -> String { monthKeyFormatter.string(from: d) }
    static func slot(_ d: Date) -> String { slotFormatter.string(from: d) }
    static func weekday(_ d: Date) -> String { weekdayFormatter.string(from: d) }
    static func dayMonth(_ d: Date) -> String { dayMonthFormatter.string(from: d) }
    static func longDay(_ d: Date) -> String { longDayFormatter.string(from: d) }
    static func monthYear(_ d: Date) -> String { monthYearFormatter.string(from: d) }
    static func date(key: String) -> Date? { keyFormatter.date(from: key) }
    static func date(monthKey: String) -> Date? { monthKeyFormatter.date(from: monthKey) }
    static func date(slot: String) -> Date? { slotFormatter.date(from: slot) }

    static func duration(_ seconds: Double) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        if hours < 24 { return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min" }
        return "\(hours / 24) d"
    }

    /// "in 4 min", "in 2 h 5 min", "in 3 d" — rounded up so a meeting never reads as later than it is.
    static func until(_ date: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "now" }
        return "in " + duration((seconds / 60).rounded(.up) * 60)
    }

    static func dayLabel(_ date: Date) -> String {
        let offset = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: date)).day ?? 0
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return dayMonth(date)
        }
    }

    static func weekNumber(_ date: Date) -> Int { cal.component(.weekOfYear, from: date) }
}

// MARK: - Events

struct Attendee: Codable {
    var name: String?
    var email: String?
    var status: String?
    var me: Bool?
    var role: String?
    var type: String?
}

struct Organizer: Codable {
    var name: String?
    var me: Bool?
}

struct Ev: Codable {
    var id: String
    var title: String
    var start: Double
    var end: Double
    var allDay: Bool
    var recurring: Bool?
    var calendarId: String?
    var calendar: String?
    var color: String?
    var source: String?
    var location: String?
    var place: String?
    var url: String?
    var notes: String?
    var status: String?
    var availability: String?
    var organizer: Organizer?
    var attendees: [Attendee]?
    var myStatus: String?
    var birthday: Bool?

    var startDate: Date { Date(timeIntervalSince1970: start) }
    var endDate: Date { Date(timeIntervalSince1970: end) }
    var name: String { title.trimmed.nonEmpty ?? "(No title)" }
    var inProgress: Bool { !allDay && startDate <= now && now < endDate }
    /// People other than rooms and equipment.
    var people: [Attendee] { (attendees ?? []).filter { ($0.type ?? "person") == "person" } }
    /// Stable per occurrence, so a repeating meeting alerts once per occurrence.
    var occurrenceKey: String { "\(id)@\(Int(start))" }
}

struct BridgeReply: Codable {
    var status: String?
    var events: [Ev]?
    var error: String?
    var ok: Bool?
    var id: String?
    var calendar: String?
}

enum Bridge {
    static let path = Env.workflowDir.appendingPathComponent("bin/agenda-calendar").path

    /// Runs the calendar bridge and decodes its JSON reply. The bridge is the only binary
    /// holding calendar permission; this program never talks to EventKit itself.
    static func run(_ arguments: [String], input: Data? = nil) -> BridgeReply? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        let stdin = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        do { try process.run() } catch { return nil }
        if let input {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return try? JSONDecoder().decode(BridgeReply.self, from: data)
    }

    /// Events overlapping [from, to), minus cancelled ones, ones you declined and ignored calendars.
    static func events(from: Date, to: Date) -> (status: String, events: [Ev]) {
        let reply: BridgeReply?
        if let fixture = Env.vars["AGENDA_FIXTURE"] {
            reply = (try? Data(contentsOf: URL(fileURLWithPath: fixture))).flatMap { try? JSONDecoder().decode(BridgeReply.self, from: $0) }
        } else {
            reply = run(["events", String(from.timeIntervalSince1970), String(to.timeIntervalSince1970)])
        }
        guard let reply else { return ("unavailable", []) }
        let status = reply.status ?? "unavailable"
        guard status == "fullAccess" else { return (status, []) }

        let ignored = Config.ignoredCalendars
        let showDeclined = Config.showDeclined
        let events = (reply.events ?? []).filter { e in
            guard e.end > from.timeIntervalSince1970, e.start < to.timeIntervalSince1970 else { return false }
            if e.status == "canceled" { return false }
            if !showDeclined, e.myStatus == "declined" { return false }
            // "Calendar" hides every calendar with that name; "Calendar (iCloud)" only that account's.
            if let name = e.calendar {
                let qualified = e.source.nonEmpty.map { "\(name) (\($0))" } ?? name
                if ignored.contains(name.folded) || ignored.contains(qualified.folded) { return false }
            }
            return true
        }
        return (status, events.sorted { ($0.start, $0.end) < ($1.start, $1.end) })
    }
}

/// Groups events under every day they touch. All-day events sort first within a day.
func eventsByDay(_ events: [Ev], from: Date, to: Date) -> [String: [Ev]] {
    var days: [String: [Ev]] = [:]
    for event in events {
        var day = cal.startOfDay(for: max(event.startDate, from))
        let last = min(event.endDate.addingTimeInterval(-1), to.addingTimeInterval(-1))
        while day <= last {
            days[Fmt.key(day), default: []].append(event)
            day = addDays(day, 1)
        }
    }
    for key in days.keys {
        days[key]?.sort { a, b in
            if a.allDay != b.allDay { return a.allDay }
            return (a.start, a.end) < (b.start, b.end)
        }
    }
    return days
}
