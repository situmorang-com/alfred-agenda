// Meeting.swift — finds the video-call link inside an event and turns it into the link to open.

import Foundation

struct Meeting {
    /// Short service name shown in results, e.g. "Teams".
    let service: String
    /// The plain https link (what gets copied).
    let web: String
    /// What ↩ opens: the native app link where one exists, otherwise the https link.
    let open: String
}

enum MeetingDetector {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are fixed strings in this file; a typo should fail loudly during development.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Order matters only where one link could match two services; the first match wins.
    private static let services: [(name: String, pattern: NSRegularExpression)] = [
        ("Teams", regex(#"^https://(?:[a-z0-9-]+\.)?teams\.(?:microsoft\.com|microsoft\.us|live\.com)/(?:l/meetup-join/|meet/|v2/\?meetingjoin)"#)),
        ("Zoom", regex(#"^https://(?:[a-z0-9-]+\.)?(?:zoom\.us|zoom\.com|zoomgov\.com|zoom\.com\.cn)/(?:j|my|w|s|wc/join)/"#)),
        ("Zoom", regex(#"^zoommtg://"#)),
        ("Meet", regex(#"^https://meet\.google\.com/(?:[a-z]{3,4}-[a-z]{4}-[a-z]{3,4}|lookup/|_meet/)"#)),
        ("Webex", regex(#"^https://[a-z0-9.-]+\.webex\.com/\S+"#)),
        ("Slack", regex(#"^https://app\.slack\.com/huddle/"#)),
        ("FaceTime", regex(#"^https://facetime\.apple\.com/join"#)),
        ("Jitsi", regex(#"^https://meet\.jit\.si/\S+"#)),
        ("Whereby", regex(#"^https://(?:[a-z0-9-]+\.)?whereby\.com/\S+"#)),
        ("Skype", regex(#"^https://join\.skype\.com/\S+"#)),
        ("GoTo", regex(#"^https://(?:meet\.goto\.com|gotomeet\.me|(?:global\.|www\.)?gotomeeting\.com/join)/\S+"#)),
        ("Chime", regex(#"^https://(?:[a-z0-9-]+\.)?chime\.aws/\S+"#)),
        ("RingCentral", regex(#"^https://(?:v\.ringcentral\.com/join|meetings\.ringcentral\.com/j)/\S+"#)),
        ("Lark", regex(#"^https://vc\.(?:larksuite\.com|feishu\.cn)/j/\S+"#)),
        ("Tencent", regex(#"^https://(?:meeting\.tencent\.com|voovmeeting\.com)/\S+"#)),
        ("Zoho", regex(#"^https://(?:meet|meeting)\.zoho\.(?:com|eu|in)/\S+"#)),
        ("Gather", regex(#"^https://app\.gather\.town/\S+"#)),
        ("Cal.com", regex(#"^https://app\.cal\.com/video/\S+"#)),
        ("Livestorm", regex(#"^https://app\.livestorm\.co/\S+"#)),
        ("Around", regex(#"^https://meet\.around\.co/\S+"#)),
    ]

    private static let anyLink = regex(#"(?:https?://|zoommtg://)[^\s<>"'\\\]\)]+"#)

    /// Checks the event's own link first, then the location, then the notes.
    static func detect(_ event: Ev) -> Meeting? {
        for text in [event.url, event.location, event.notes] {
            if let text, let meeting = detect(in: text) { return meeting }
        }
        return nil
    }

    static func detect(in text: String) -> Meeting? {
        guard text.contains("://") else { return nil }
        let source = text as NSString
        for match in anyLink.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let link = unwrap(clean(source.substring(with: match.range)))
            let range = NSRange(location: 0, length: (link as NSString).length)
            if let service = services.first(where: { $0.pattern.firstMatch(in: link, range: range) != nil }) {
                return Meeting(service: service.name, web: link, open: native(service.name, link))
            }
        }
        return nil
    }

    private static func clean(_ link: String) -> String {
        var link = link.replacingOccurrences(of: "&amp;", with: "&")
        while let last = link.last, ".,;:!?*".contains(last) { link.removeLast() }
        return link
    }

    /// Mail security services wrap links in a redirect; open the real destination instead.
    private static func unwrap(_ link: String) -> String {
        guard let components = URLComponents(string: link), let host = components.host?.lowercased() else { return link }
        func query(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value.nonEmpty
        }
        if host.hasSuffix("safelinks.protection.outlook.com"), let target = query("url") { return clean(target) }
        if host.hasSuffix("google.com"), components.path == "/url", let target = query("q") ?? query("url") { return clean(target) }
        if host == "urldefense.com", let start = link.range(of: "/v3/__"), let end = link.range(of: "__;", range: start.upperBound..<link.endIndex) {
            return clean(String(link[start.upperBound..<end.lowerBound]))
        }
        return link
    }

    /// Teams and Zoom can be opened straight in their apps, skipping the browser hand-off page.
    private static func native(_ service: String, _ link: String) -> String {
        guard link.lowercased().hasPrefix("https://") else { return link }
        let rest = link.dropFirst("https://".count)
        switch service {
        case "Teams" where Config.teamsApp:
            return "msteams://" + rest
        case "Zoom" where Config.zoomApp:
            // Personal rooms (/my/…) and webinars have no app link, so they stay in the browser.
            guard rest.contains("/j/") else { return link }
            return "zoommtg://" + rest.replacingOccurrences(of: "?", with: "&").replacingOccurrences(of: "/j/", with: "/join?confno=")
        default:
            return link
        }
    }
}
