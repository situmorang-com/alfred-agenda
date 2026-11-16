// agenda — the Alfred-facing half of the Agenda workflow.
//
//   agenda list [text]     agenda rows (Script Filter JSON)
//   agenda day [day text]  one day, with free gaps
//   agenda join [text]     meetings you can join now or soon
//   agenda block [title]   options for blocking the slot in $slot
//   agenda month [month]   month grid (Grid View JSON)
//   agenda week [day]      week grid (Grid View JSON)
//   agenda do              perform the action in $act
//   agenda tick            run by the background job once a minute
//   agenda alerts [status|sync|off|test]
//   agenda icons           redraw the fixed icons (build.sh does this)
//   agenda detect <text>   show which meeting link is found in some text

import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let input = arguments.count > 1 ? arguments[1] : ""

switch arguments.first ?? "list" {
case "list": viewList(input)
case "day": viewDay(input)
case "join": viewJoin(input)
case "block": viewBlock(input)
case "month": viewMonth(input)
case "week": viewWeek(input)
case "do": runAction()
case "tick": Alerts.tick()
case "alerts": Alerts.command(input)
case "icons": Render.staticIcons()
case "detect":
    if let meeting = MeetingDetector.detect(in: input) {
        print("\(meeting.service)\n  web:  \(meeting.web)\n  open: \(meeting.open)")
    } else {
        print("no meeting link found")
    }
default:
    FileHandle.standardError.write(Data("unknown command: \(arguments.first ?? "")\n".utf8))
    exit(2)
}
