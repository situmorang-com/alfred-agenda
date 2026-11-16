// alfui — helper for live tests in Alfred: find Alfred's window, capture only that window,
// read the text in Alfred's search field, and send plain keys to Alfred. docs/TESTING.md has
// the rules (ask first, check for a meeting, dry-run on) and how to hold a modifier.
//
//   swiftc -O tests/tools/alfui.swift -o "$TMPDIR/alfui"
//   alfui window                      "<window id> <width>x<height>", or "none"
//   alfui shot <file.png> [seconds]   wait (default 6 s) for the window to settle, then capture it
//   alfui field                       the search field's text (needs Accessibility), or "none"
//   alfui key <return|escape|down|up|tab>

import AppKit
import ApplicationServices

func alfred() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.runningwithcrayons.Alfred").first
}

/// Alfred's largest on-screen window: the main window (the small ones are icons and helpers).
func mainWindow() -> (id: Int, width: Int, height: Int)? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var best: (id: Int, width: Int, height: Int)?
    for info in list where (info[kCGWindowOwnerName as String] as? String) == "Alfred" {
        let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let width = Int(bounds["Width"] ?? 0), height = Int(bounds["Height"] ?? 0)
        guard width > 200, height > 40 else { continue }
        if best.map({ width * height > $0.width * $0.height }) ?? true {
            best = ((info[kCGWindowNumber as String] as? Int) ?? 0, width, height)
        }
    }
    return best
}

func textField(in element: AXUIElement, depth: Int = 0) -> String? {
    guard depth < 8 else { return nil }
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    if (role as? String) == (kAXTextFieldRole as String) {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        return (value as? String) ?? ""
    }
    var children: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
          let kids = children as? [AXUIElement] else { return nil }
    for kid in kids {
        if let text = textField(in: kid, depth: depth + 1) { return text }
    }
    return nil
}

func searchField() -> String? {
    guard let app = alfred() else { return nil }
    var windows: CFTypeRef?
    let element = AXUIElementCreateApplication(app.processIdentifier)
    guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
          let list = windows as? [AXUIElement] else { return nil }
    for window in list {
        if let text = textField(in: window) { return text }
    }
    return nil
}

let keyCodes: [String: CGKeyCode] = ["return": 36, "escape": 53, "down": 125, "up": 126, "tab": 48]

/// A plain key press sent to Alfred alone. Held modifiers need real key state: see docs/TESTING.md.
func press(_ code: CGKeyCode) {
    guard let pid = alfred()?.processIdentifier, let source = CGEventSource(stateID: .hidSystemState) else { return }
    for down in [true, false] {
        CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)?.postToPid(pid)
        usleep(30_000)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first ?? "" {
case "window":
    print(mainWindow().map { "\($0.id) \($0.width)x\($0.height)" } ?? "none")

case "shot":
    guard args.count > 1 else { print("usage: alfui shot <file.png> [seconds]"); exit(2) }
    let deadline = Date().addingTimeInterval(args.count > 2 ? Double(args[2]) ?? 6 : 6)
    var last: (id: Int, width: Int, height: Int)?
    var steady = 0
    while Date() < deadline, steady < 4 {
        usleep(150_000)
        let current = mainWindow()
        if let current, let previous = last, current.id == previous.id, current.width == previous.width, current.height == previous.height {
            steady += 1
        } else {
            steady = 0
        }
        last = current
    }
    guard let window = last else { print("none"); exit(1) }
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l", String(window.id), args[1]]
    try capture.run()
    capture.waitUntilExit()
    print("\(window.width)x\(window.height) \(args[1])")

case "field":
    print(searchField() ?? "none")

case "key":
    guard args.count > 1, let code = keyCodes[args[1]] else {
        print("keys: \(keyCodes.keys.sorted().joined(separator: ", "))")
        exit(2)
    }
    press(code)

default:
    print("usage: alfui window | shot <file.png> [seconds] | field | key <name>")
    exit(2)
}
