// Alerts.swift — "tell me when it's time". A small macOS background job (a LaunchAgent) runs
// `agenda tick` once a minute. When a meeting is about to start it either pops Alfred's join
// prompt, posts a notification, or opens the meeting, depending on the Meeting alerts setting.
// While the screen is locked it posts a notification and keeps the prompt (or the join) for the
// first check after the unlock.
//
// The job is installed and removed automatically to match that setting; nothing else is left
// running, and switching the setting to Off deletes it.

import CoreGraphics
import Foundation

enum Alerts {
    static var label: String { Env.bundleID + ".alerts" }
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    private static var domain: String { "gui/\(getuid())" }
    private static var target: String { "\(domain)/\(label)" }
    private static var stateURL: URL { Env.dataDir.appendingPathComponent("alerted.json") }
    private static var tickStamp: URL { Env.dataDir.appendingPathComponent(".last-tick") }

    private static func jobDefinition() -> Data? {
        let job: [String: Any] = [
            "Label": label,
            "ProgramArguments": [Env.exe.path, "tick"],
            // Second 0 of every minute, so an alert lands exactly on the minute.
            "StartCalendarInterval": (0..<60).map { ["Minute": $0] },
            // Not "Background": with it, launchd ran the job in fewer than half of the minutes the
            // Mac was awake (13–15 Nov); with Standard it ran in every one (16 Nov).
            "ProcessType": "Standard",
            "StandardErrorPath": Env.dataDir.appendingPathComponent("alerts.log").path,
        ]
        return try? PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
    }

    static var isLoaded: Bool { shell("/bin/launchctl", ["print", target]) == 0 }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// Makes the background job match the setting. Returns a one-line description of what it did.
    @discardableResult
    static func sync() -> String {
        let fm = FileManager.default
        if Config.alertStyle == "off" {
            guard isInstalled || isLoaded else { return "Meeting alerts are off" }
            shell("/bin/launchctl", ["bootout", target])
            try? fm.removeItem(at: plistURL)
            return "Meeting alerts turned off and the background job removed"
        }
        guard let wanted = jobDefinition() else { return "Couldn’t describe the background job" }
        if (try? Data(contentsOf: plistURL)) != wanted {
            try? fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            shell("/bin/launchctl", ["bootout", target])
            do { try wanted.write(to: plistURL, options: .atomic) } catch { return "Couldn’t write \(plistURL.path)" }
            let result = shell("/bin/launchctl", ["bootstrap", domain, plistURL.path])
            return result == 0 ? "Meeting alerts turned on" : "The background job was written but macOS refused to start it (\(result))"
        }
        if !isLoaded {
            let result = shell("/bin/launchctl", ["bootstrap", domain, plistURL.path])
            return result == 0 ? "Meeting alerts restarted" : "macOS refused to start the background job (\(result))"
        }
        return "Meeting alerts are on"
    }

    /// Called when a view opens inside Alfred: cheap, and re-checks at most every ten minutes
    /// unless the setting or the workflow's location changed.
    static func syncIfNeeded() {
        guard Env.insideAlfred, Env.vars["AGENDA_FIXTURE"] == nil else { return }
        let stamp = Env.dataDir.appendingPathComponent(".alerts-synced")
        let wanted = "\(Config.alertStyle)|\(Env.exe.path)"
        let modified = (try? FileManager.default.attributesOfItem(atPath: stamp.path))?[.modificationDate] as? Date
        if let modified, Date().timeIntervalSince(modified) < 600, (try? String(contentsOf: stamp, encoding: .utf8)) == wanted { return }
        sync()
        try? wanted.write(to: stamp, atomically: true, encoding: .utf8)
    }

    // MARK: Once a minute

    private static func trigger(_ name: String, argument: String? = nil, inBackground: Bool) {
        var link = "alfred://runtrigger/\(Env.bundleID)/\(name)/"
        if let argument {
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&+=?#")
            link += "?argument=" + (argument.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }
        shell("/usr/bin/open", inBackground ? ["-g", link] : [link])
    }

    static func notify(_ message: String) { trigger("notify", argument: message, inBackground: true) }

    private static var tickLog: URL { Env.dataDir.appendingPathComponent("ticks.log") }

    private static let logStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// One line per check, so a missed alert can be traced afterwards: when the check really
    /// ran, how late after the minute, how long the calendar took, how many events and alerts.
    /// Counts only, never event content. Trimmed to roughly the last two days.
    private static func logTick(_ started: Date, _ fields: String) {
        let late = Int(started.timeIntervalSince1970) % 60
        let test = Env.vars["AGENDA_DRY_RUN"] != nil || Env.vars["AGENDA_FIXTURE"] != nil ? " test" : ""
        let line = Data("\(logStamp.string(from: started)) late=\(late)s \(fields)\(test)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: tickLog) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: tickLog)
        }
        if let size = (try? FileManager.default.attributesOfItem(atPath: tickLog.path))?[.size] as? Int, size > 256_000,
           let text = try? String(contentsOf: tickLog, encoding: .utf8) {
            let lines = text.split(separator: "\n")
            try? (lines.suffix(lines.count / 2).joined(separator: "\n") + "\n").write(to: tickLog, atomically: true, encoding: .utf8)
        }
    }

    static func tick() -> Never {
        let started = Date()
        let style = Config.alertStyle
        guard style != "off" else { exit(0) }
        let lead = Double(Config.alertLead) * 60
        let (status, events) = Bridge.events(from: now.addingTimeInterval(-600), to: now.addingTimeInterval(lead + 120))
        let took = Int(Date().timeIntervalSince(started) * 1000)
        try? "calendar: \(status), events starting around now: \(events.count)".write(to: tickStamp, atomically: true, encoding: .utf8)
        guard status == "fullAccess" else {
            logTick(started, "calendar=\(status) took=\(took)ms")
            exit(0)
        }

        var alerted = ((try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) }) ?? [:]
        let before = alerted.count
        alerted = alerted.filter { $0.value > now.timeIntervalSince1970 - 2 * 86400 }

        // Due: from the lead time before the start until five minutes after it, once per occurrence.
        let due = events.filter { e in
            guard !e.allDay, alerted[e.occurrenceKey] == nil else { return false }
            guard now >= e.startDate.addingTimeInterval(-lead), now < e.startDate.addingTimeInterval(300) else { return false }
            return !Config.alertLinksOnly || MeetingDetector.detect(e) != nil
        }
        let screen = screenState()
        logTick(started, "calendar=ok events=\(events.count) due=\(due.count) took=\(took)ms screen=\(screen)")
        guard !due.isEmpty else {
            if alerted.count != before { save(alerted) }
            exit(0)
        }

        // A prompt or a meeting opened behind the lock screen goes unseen (15 Nov). While the
        // screen is locked or dark: one notification now, and the prompt or join waits for the
        // first check after the unlock, as long as that is still within the window.
        if style != "notify", screen == "locked" || screen == "asleep" {
            let unannounced = due.filter { alerted[heldKey($0)] == nil }
            for event in unannounced { alerted[heldKey(event)] = now.timeIntervalSince1970 }
            if !unannounced.isEmpty || alerted.count != before { save(alerted) }
            if !unannounced.isEmpty {
                perform("would notify (screen \(screen); \(style) held): \(describe(unannounced))") { notify(describe(unannounced)) }
            }
            exit(0)
        }

        for event in due { alerted[event.occurrenceKey] = now.timeIntervalSince1970 }
        save(alerted)
        perform("would alert (\(style)): \(describe(due))") { fire(style, due) }
        exit(0)
    }

    /// Marks an occurrence whose alert is waiting for the unlock and has had its notification.
    private static func heldKey(_ event: Ev) -> String { "held:" + event.occurrenceKey }

    /// Fixture runs and AGENDA_DRY_RUN print the report instead of popping anything up.
    private static func perform(_ report: String, _ action: () -> Void) {
        if Env.vars["AGENDA_DRY_RUN"] != nil || Env.vars["AGENDA_FIXTURE"] != nil { print(report) } else { action() }
    }

    /// Whether someone at the Mac could see Alfred's window: "on", "locked" (the lock screen
    /// is up), "asleep" (the display is off) or "unknown" (treated as on). AGENDA_SCREEN
    /// overrides it for tests; fixture runs otherwise assume "on".
    static func screenState() -> String {
        if let forced = Env.vars["AGENDA_SCREEN"] { return forced }
        if Env.vars["AGENDA_FIXTURE"] != nil { return "on" }
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return "unknown" }
        if (session["CGSSessionScreenIsLocked"] as? Bool) == true { return "locked" }
        return CGDisplayIsAsleep(CGMainDisplayID()) != 0 ? "asleep" : "on"
    }

    private static func save(_ alerted: [String: Double]) {
        if let data = try? JSONEncoder().encode(alerted) { try? data.write(to: stateURL, options: .atomic) }
    }

    private static func describe(_ events: [Ev]) -> String {
        guard let first = events.first else { return "" }
        let when = first.startDate > now ? "starts \(Fmt.until(first.startDate))" : "has started"
        return events.count == 1 ? "\(first.name) \(when)" : "\(events.count) meetings: " + events.map { $0.name }.joined(separator: ", ")
    }

    private static func fire(_ style: String, _ events: [Ev]) {
        switch style {
        case "prompt":
            trigger("join", inBackground: false)
        case "auto":
            if let meeting = events.lazy.compactMap({ MeetingDetector.detect($0) }).first {
                openLink(meeting.open, fallback: meeting.web)
                notify("Joining · " + describe(events))
            } else {
                notify(describe(events))
            }
        default:
            notify(describe(events))
        }
    }

    // MARK: Manual control (used by build.sh and for troubleshooting)

    static func command(_ argument: String) -> Never {
        switch argument {
        case "sync":
            print(sync())
        case "off":
            shell("/bin/launchctl", ["bootout", target])
            try? FileManager.default.removeItem(at: plistURL)
            print("Background job removed. It returns when a view is opened unless Meeting alerts is set to Off.")
        case "test":
            let style = Config.alertStyle
            if style == "prompt" { trigger("join", inBackground: false) } else { notify("Test alert from Agenda") }
            print("Sent a test alert (\(style))")
        default:
            let last = (try? FileManager.default.attributesOfItem(atPath: tickStamp.path))?[.modificationDate] as? Date
            print("setting: \(Config.alertStyle), \(Config.alertLead) min before, links only: \(Config.alertLinksOnly)")
            print("job file: \(isInstalled ? plistURL.path : "not installed")")
            print("running: \(isLoaded ? "yes" : "no")")
            let seen = (try? String(contentsOf: tickStamp, encoding: .utf8)).nonEmpty.map { " (\($0))" } ?? ""
            print("last check: \(last.map { "\(Int(Date().timeIntervalSince($0))) s ago" } ?? "never")\(seen)")
            if let text = try? String(contentsOf: tickLog, encoding: .utf8) {
                let hourAgo = Date().addingTimeInterval(-3600)
                let recent = text.split(separator: "\n").suffix(300).filter { line in
                    !line.hasSuffix(" test") && (logStamp.date(from: String(line.prefix(19))).map { $0 >= hourAgo } ?? false)
                }
                print("checks in the last hour: \(recent.count) (one a minute while the Mac is awake; details in \(tickLog.path))")
            }
        }
        exit(0)
    }
}
