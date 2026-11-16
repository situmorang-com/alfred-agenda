// Actions.swift — what happens after you press ↩: open a meeting, show an event in Calendar,
// copy a link, block time. Whatever this prints becomes the text of an Alfred notification.

import AppKit

@discardableResult
func shell(_ path: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return -1 }
    process.waitUntilExit()
    return process.terminationStatus
}

/// Opens the app link, falling back to the browser link if the app is not installed.
func openLink(_ link: String, fallback: String? = nil) {
    if shell("/usr/bin/open", [link]) != 0, let fallback, fallback != link {
        shell("/usr/bin/open", [fallback])
    }
}

/// Shows a day in the Calendar app. Needs Alfred's permission to control Calendar the first
/// time; if that is refused, Calendar still opens, just not on the right day.
private func showInCalendar(_ day: Date) {
    let parts = cal.dateComponents([.year, .month, .day], from: day)
    let script = """
    set target to current date
    set time of target to 0
    set day of target to 1
    set year of target to \(parts.year ?? 2000)
    set month of target to \(parts.month ?? 1)
    set day of target to \(parts.day ?? 1)
    tell application "Calendar"
        activate
        switch view to day view
        view calendar at target
    end tell
    """
    if shell("/usr/bin/osascript", ["-e", script]) != 0 { shell("/usr/bin/open", ["-b", "com.apple.iCal"]) }
}

func runAction() -> Never {
    let v = Env.vars
    func say(_ message: String) { FileHandle.standardOutput.write(Data(message.utf8)) }

    // While a file named ".dry-run" exists in the workflow's data folder (live tests), and
    // always in fixture runs, actions are written to dry-run.log there instead of being
    // carried out, so a test can never join a meeting or write to the real calendar.
    let dryRun = Env.dataDir.appendingPathComponent(".dry-run")
    if Env.vars["AGENDA_FIXTURE"] != nil || FileManager.default.fileExists(atPath: dryRun.path) {
        let link = v["url"].nonEmpty.flatMap { URLComponents(string: $0) }.map { "\($0.scheme ?? "")://\($0.host ?? "")…" } ?? "-"
        let fields = ["date", "slot", "start", "end", "allday", "span", "title", "calid", "note"].filter { v[$0].nonEmpty != nil }.map { "\($0)=\(v[$0] ?? "")" }
        let line = "act=\(v["act"] ?? "-") link=\(link) event=\(v["eid"].nonEmpty == nil ? "no" : "yes") \(fields.joined(separator: " "))\n"
        let log = Env.dataDir.appendingPathComponent("dry-run.log")
        let existing = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        try? (existing + line).write(to: log, atomically: true, encoding: .utf8)
        exit(0)
    }

    switch v["act"] ?? "" {
    case "open":
        if let link = v["url"].nonEmpty { openLink(link, fallback: v["web"].nonEmpty) }

    case "cal":
        if let id = v["eid"].nonEmpty {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            if shell("/usr/bin/open", ["ical://ekevent/\(encoded)?method=show&options=more"]) != 0 {
                shell("/usr/bin/open", ["-b", "com.apple.iCal"])
            }
        }

    case "calday":
        showInCalendar(v["date"].nonEmpty.flatMap { Fmt.date(key: $0) } ?? today)

    case "copy":
        if let text = v["text"].nonEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            say(v["note"].nonEmpty ?? "Copied")
        }

    case "block":
        guard let start = v["start"].flatMap({ Double($0) }), let end = v["end"].flatMap({ Double($0) }), end > start else {
            say("Couldn’t block that time")
            break
        }
        let title = v["title"].nonEmpty ?? Config.blockTitle
        var spec: [String: Any] = ["title": title, "start": start, "end": end, "availability": "busy"]
        if let calendar = v["calid"].nonEmpty { spec["calendarId"] = calendar }
        let reply = (try? JSONSerialization.data(withJSONObject: spec)).flatMap { Bridge.run(["create"], input: $0) }
        if reply?.ok == true {
            let range = Fmt.range(Date(timeIntervalSince1970: start), Date(timeIntervalSince1970: end))
            say("Blocked \(range) · \(title)" + (reply?.calendar.nonEmpty.map { " · \($0)" } ?? ""))
        } else {
            say("Couldn’t block that time" + (reply?.error.nonEmpty.map { ": \($0)" } ?? ""))
        }

    case "create":
        guard let start = v["start"].flatMap({ Double($0) }), let end = v["end"].flatMap({ Double($0) }), end > start else {
            say("Couldn’t add that event")
            break
        }
        let title = v["title"].nonEmpty ?? "New event"
        let allDay = v["allday"] == "1"
        var spec: [String: Any] = ["title": title, "start": start, "end": end, "allDay": allDay]
        if let calendar = v["calid"].nonEmpty { spec["calendarId"] = calendar }
        let reply = (try? JSONSerialization.data(withJSONObject: spec)).flatMap { Bridge.run(["create"], input: $0) }
        if reply?.ok == true {
            let from = Date(timeIntervalSince1970: start), to = Date(timeIntervalSince1970: end)
            let when = allDay ? "\(Fmt.dayLabel(from)) · all day" : "\(Fmt.dayLabel(from)) \(Fmt.range(from, to))"
            // The bridge names the calendar without its account; the row knew both.
            say("Added “\(title)” · \(when)" + ((v["callabel"].nonEmpty ?? reply?.calendar.nonEmpty).map { " · \($0)" } ?? ""))
        } else {
            say("Couldn’t add that event" + (reply?.error.nonEmpty.map { ": \($0)" } ?? ""))
        }

    case "delete":
        // Reached only from the confirmation row (see Delete.swift).
        let title = v["title"].nonEmpty.map { "“\($0)”" } ?? "that event"
        guard let id = v["eid"].nonEmpty else {
            say("Couldn’t delete \(title)")
            break
        }
        var spec: [String: Any] = ["id": id, "span": v["span"] == "future" ? "future" : "this"]
        if let start = v["start"].flatMap({ Double($0) }) { spec["start"] = start }
        let reply = (try? JSONSerialization.data(withJSONObject: spec)).flatMap { Bridge.run(["delete"], input: $0) }
        if reply?.ok == true {
            let later = v["span"] == "future" ? " and its later repeats" : ""
            say("Deleted \(title)\(later)" + ((v["callabel"].nonEmpty ?? reply?.calendar.nonEmpty).map { " · \($0)" } ?? ""))
        } else {
            say("Couldn’t delete \(title)" + (reply?.error.nonEmpty.map { ": \($0)" } ?? ""))
        }

    case "auth":
        switch Bridge.run(["auth"])?.status {
        case "fullAccess": say("Calendar access granted — open Agenda again")
        case .some(let status): say("Calendar access is \(status). Allow it in System Settings › Privacy & Security › Calendars")
        case nil: say("The calendar helper didn’t respond. Run build.sh in the workflow folder")
        }

    case "settings":
        shell("/usr/bin/open", ["x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"])

    default:
        break
    }
    exit(0)
}
