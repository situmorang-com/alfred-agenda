# Agenda — product requirements

**Status:** v1.1.0, released 16 Nov 2026 (in daily use since 13 Nov) · **Last reviewed:** 16 Nov 2026
An Alfred workflow that shows the user's macOS calendar and gets them into meetings on time.
How it is built: [ARCHITECTURE.md](ARCHITECTURE.md) · What was learned and decided: [MEMORY.md](MEMORY.md)

## Problem

Raycast's *My Schedule* puts the day's meetings and a "next up" summary in the launcher. The user works in Alfred and wanted that there, plus two things My Schedule lacks: real day, week and month views, and help joining a meeting at the moment it starts.

## Goals

1. One keystroke shows what is next and the days ahead, from the accounts already in macOS Calendar.
2. A day, a week or a month reads at a glance.
3. ↩ joins a video meeting that is on, and a prompt appears when one starts.
4. Free time can be blocked, and an event added, without opening a calendar app.
5. Local and fast: nothing leaves the Mac, and every view opens in under 300 ms.

## Non-goals (v1)

- Accepting or declining invitations: EventKit cannot answer invites (Outlook and Calendar can).
- Editing events, and deleting meetings with other people: that cancels or declines them for everyone, which Calendar and Outlook handle properly. New events carry a title, a time and a calendar only: no invitees, places, alerts or repeats (the separate Add Calendar Event workflow, `calx`, sets places and alarms).
- Calendars that are not in macOS Calendar, Google or Microsoft APIs, anything over the network.

## User and environment

People who live in Alfred and keep their calendars in macOS Calendar: typically a work Exchange account with Teams meetings, next to iCloud and Google. Built on macOS 27 with Alfred 5.8 and the Powerpack ([MEMORY.md › Environment](MEMORY.md#environment)).

Hard requirements: macOS 14 or later (the calendar access model), Alfred 5.5 or later (Grid View); to build from source, Xcode's command line tools.

## Requirements

Status: **Live** — checked in Alfred on the user's Mac · **Fixture** — checked by `tests/smoke.sh` · **Untested** — not exercised yet.
The workflow's About text in Alfred describes keys and settings for the user; where it and this file disagree, this file is the reference.

### Agenda — `cal`

| ID | Requirement | Status |
|---|---|---|
| AG-1 | The top row is the meeting that matters now: the one in progress, unless the next timed event starts within 10 minutes, then that one. It shows a countdown ("in 4 min", "now · 1 h 8 min left"). | Live |
| AG-2 | While that meeting is on or starts within 20 minutes, the list refreshes every 5 seconds. | Fixture |
| AG-3 | Below it, events from now to `lookahead_days` ahead (default 14) in day order. A row shows time, title, day, a countdown within 24 h, the meeting service or place, the number of people, a reply state (tentative, not answered) and the calendar. Finished events drop off; all-day events stay for their day. | Live |
| AG-4 | Several all-day events on one day fold into one row ("All day  <first> +N more"); ↩ opens that day. | Live |
| AG-5 | Cancelled events are hidden, and so are meetings the user declined unless *Show meetings I declined* is on. | Fixture |
| AG-6 | Typing searches titles, places, calendars, organisers and attendee names over the next 60 days. | Fixture |
| AG-7 | The last rows open today's day view, the week and the month, then *New event…* (NE-5) and *Delete an event…* (DL-4). | Fixture |

### Event rows — every list

| ID | Requirement | Status |
|---|---|---|
| EV-1 | ↩ joins when the event has a meeting link and is on or starts within 15 minutes; otherwise ↩ opens the event in Calendar. | Live (dry run); *open in Calendar* Live (16 Nov); a real join Untested |
| EV-2 | ⌘↩ does the other of join and open. | Live (dry run) |
| EV-3 | ⌥↩ copies the meeting link, or the event details when there is no link, and confirms with a notification. | Live (dry run) |
| EV-4 | ⌃↩ shows that event's day. | Live |
| EV-5 | ⌘C copies and ⌘L shows the details: title, time, place or link, organiser, people, calendar. ⇧ previews the meeting link. | Untested |

### Day — `day`

| ID | Requirement | Status |
|---|---|---|
| DY-1 | A header with the date, number of events, time in meetings and week number. ↩ opens the day in Calendar; ⌥↩ and ⌃↩ go to the next and previous day. | Live (render); keys Untested |
| DY-2 | All-day events first, then timed events and free gaps in time order. On today, finished events collapse into one "N earlier events finished" row. | Live |
| DY-3 | Free gaps of 30 minutes or more within working hours (`work_start`–`work_end`, default 8–18); on today they begin at the next 5 minutes. ↩ on a gap offers to block it. | Live (render); ↩ Fixture |
| DY-4 | A day after the keyword: today, tomorrow, yesterday (and short forms), a weekday name (English or the system language), +N or −N days, YYYY-MM-DD, D/M or D/M/YY. Other words filter that day's events. | `day tomorrow` Live; the rest Fixture |
| DY-5 | Footer rows: *Block time…*, *Next day*, *Previous day*. | Fixture |

### Week — `week`

| ID | Requirement | Status |
|---|---|---|
| WK-1 | A grid of seven day tiles for the current week, first weekday from `week_start` or the system; today is framed and selected. | Live |
| WK-2 | Each tile: weekday and date, an all-day strip when any day that week has one, and an hour grid with events as blocks in their calendar's colour, overlaps side by side, and a now-line on today. One hour range serves the whole week: working hours, widened to fit that week's events (at most 3 hours earlier, up to midnight later). | Live |
| WK-3 | The footer names the selected day, its week number and its first events. | Live |
| WK-4 | ↩ opens the day, ⌥↩ and ⌃↩ go to the next and previous week, ⌘↩ opens the day in Calendar; typing filters days by date or event title. | Fixture (the same wiring is Live in the month grid) |
| WK-5 | `week +1`, `week -1` or a day word chooses the week. | Fixture |

### Month — `month`

| ID | Requirement | Status |
|---|---|---|
| MO-1 | Whole weeks covering the month (35 or 42 tiles); days outside the month are dimmed; today is framed and selected. | Live |
| MO-2 | A tile shows the weekday, date and up to three lines. Meetings get the lines first, with "+N more" when they don't fit; all-day events take a line only when there is room, otherwise they show as coloured dots. On today, meetings still to come are listed before finished ones. | Live |
| MO-3 | ↩ opens the day; ⌥↩ and ⌃↩ go to the next and previous month; ⌘↩ opens the day in Calendar; typing filters days. | ↩, ⌥↩, ⌃↩ Live; ⌘↩ and typing Untested |
| MO-4 | `month dec`, `month +1` or `month 2027-01` chooses the month; a month name already past this year means next year's. | Fixture |

### Join — `join`, and the alert prompt

| ID | Requirement | Status |
|---|---|---|
| JN-1 | Meetings with a link: those on or starting within 15 minutes first, nearest start first, then the rest of today; if there are none, the next linked meeting ahead. | Live (render); order Fixture |
| JN-2 | ↩ opens the meeting: Teams links in the Teams app, Zoom meeting links in the Zoom app with the passcode, everything else in the browser; the browser link is the fallback when an app link can't open. The *Open … links in the … app* settings switch the app links off. | Links Fixture; a real join Untested |
| JN-3 | The link is taken from the event's URL, then location, then notes; Outlook Safe Links, Google and URLDefense redirects are removed. Twenty services are recognised ([ARCHITECTURE.md › Meeting links](ARCHITECTURE.md#meeting-links)). | Fixture; checked on a real calendar (15 Nov) |
| JN-4 | While a meeting is on or near, the list refreshes every 5 seconds. | Fixture |

### Block time

| ID | Requirement | Status |
|---|---|---|
| BT-1 | From a free gap: the whole gap, the first 30 minutes, first hour or first 2 hours (only those shorter than the gap). From *Block time…*: workday, morning or afternoon within working hours; on today from the next quarter hour. | Fixture |
| BT-2 | What the user types becomes the title; empty means `block_title` ("Focus time"). | Fixture |
| BT-3 | The block is saved as busy in the calendar named by `block_calendar` ("Calendar (Exchange)" when names clash), otherwise the system's default calendar, and a notification confirms it. | Untested; the bridge's `create` it uses works (NE-1) |

### New event — `cal +`

| ID | Requirement | Status |
|---|---|---|
| NE-1 | Typing `+` and then what and when in the agenda shows the event before it is saved: title, day, time, calendar, and the meeting it overlaps (or how many). ↩ saves it, and a notification confirms with the calendar's name and account. | Fixture. Saving Live through `agenda do` (16 Nov: a test event reached Calendar (iCloud) with the right time and showed in `day`); typing it in Alfred Untested |
| NE-2 | When: any day word `day` accepts; times `15:00`, `15.00`, `3pm`, `3:30pm`, `3 pm`, `noon`, `at 15`, 24-hour unless am or pm; ranges `12-13`, `3-4pm`, `10:30-11:15`, `3pm to 4:30pm`; lengths `30m`, `45 min`, `1h30`, `for 2 hours`. One hour by default. A time alone that has passed today means tomorrow; a day alone makes an all-day event. When two words could be the day, the last counts ("coffee with Tom tomorrow"). Everything else is the title. | Fixture |
| NE-3 | One row per calendar that takes events (at most six): the one from the settings (`block_calendar`) or the system default first; `@word` puts the calendar or account containing that word first (`@exchange`). | Fixture; real calendars listed 16 Nov |
| NE-4 | Without a day or time, one row shows the forms and nothing can be saved. | Fixture |
| NE-5 | The agenda's *New event…* row puts `+ ` after the keyword. | Fixture |

### Delete — `cal -`

| ID | Requirement | Status |
|---|---|---|
| DL-1 | Typing `-` and part of a name lists the matching events from a week ago to 60 days ahead, coming ones first; with nothing typed, the coming days. | Fixture |
| DL-2 | ↩ on an event opens a confirmation whose first, preselected row is *Keep it* (back to the agenda); the row below deletes it, and a repeating event adds *Delete it from <day> on* (this and every later one). A notification confirms. | Fixture. Deleting Live through `agenda do` (16 Nov: the test event, via the search row, the confirmation and its Delete row; gone from the calendar); inside Alfred Untested |
| DL-3 | Not offered, with the reason on the row and ↩ opening the event in Calendar: events with other people (deleting cancels or declines for everyone), invitations, and events in read-only calendars. The helper refuses them too. | Fixture |
| DL-4 | The agenda's last row, *Delete an event…*, puts `- ` after the keyword. | Fixture |

### Meeting alerts

| ID | Requirement | Status |
|---|---|---|
| AL-1 | A background job checks at the start of every minute and acts once per meeting occurrence, from `alert_lead` minutes before the start (default 1) until 5 minutes after it. | Fixture. Live since 15 Nov: alerts fire on the minute, and no awake minute goes unchecked (measured 16 Nov). |
| AL-2 | Styles: *prompt* (default) opens Alfred's join list; *notify* posts a notification; *auto* opens the meeting and notifies; *off* removes the job. | prompt Live (`bin/agenda alerts test`); notify and auto Untested. On 15 Nov a prompt opened behind the lock screen, unseen, hence AL-5. |
| AL-3 | Only meetings with a link, unless *Only for meetings with a video link* is off. | Fixture |
| AL-4 | Opening the agenda or join list installs, updates or removes the job to match the setting (checked at most every 10 minutes unless the setting changed). | Live (installed on first open) |
| AL-5 | While the screen is locked or the display asleep, *prompt* and *auto* post one notification instead, and the first check after the unlock opens the join list or joins, if that is still within the window. *notify* doesn't wait. | Fixture; the job saw the screen locked live (16 Nov), but no alert has come due while locked yet |

### Setup, settings, privacy

| ID | Requirement | Status |
|---|---|---|
| SU-1 | Without calendar access a view shows one row: *Allow calendar access* (↩ shows the macOS prompt) or, once refused, a row that opens Privacy & Security › Calendars. | Untested in Alfred (access was granted from Terminal) |
| SU-2 | Calendar access belongs to `bin/agenda-calendar`, not to Alfred, and survives rebuilds of `bin/agenda`. | Live |
| ST-1 | *Configure Workflow…* sets the keywords, lookahead, week start, working hours, hidden calendars, declined meetings, alert style, lead time and links-only, Teams and Zoom app links, block title and block calendar. The background job uses the same values. | Defaults Live; changed values reaching the job Untested |
| ST-2 | *Hidden calendars* takes a name ("Calendar" hides every calendar with that name) or a name and account ("Calendar (iCloud)"). | Fixture |
| PV-1 | Calendar data stays on the Mac: no network calls; files hold counts and identifiers, never event content. | By design |

### Quality

| ID | Requirement | Status |
|---|---|---|
| NF-1 | Each view opens in under 300 ms on the real calendar; the background check costs about 120 ms a minute. | Measured 15 Nov: agenda 158, day 114, join 159, month 240, week 135–258 ms; tick 121 ms |
| NF-2 | Tiles stay legible in Alfred's light and dark themes. | Light Live; dark in previews only |
| NF-3 | Everything works from the keyboard. | Live |
| NF-4 | Builds with `./build.sh` and the Swift toolchain alone. | Live |
| NF-5 | Ships as one `Agenda.alfredworkflow` for Apple silicon and Intel Macs on macOS 14 or later, and its helpers run after a download although Apple hasn't notarized them. | Apple silicon: a flagged copy of the package ran (16 Nov). Intel: built, never run. Imported into Alfred from a real download: Untested |

## Compared with Raycast My Schedule

| | Agenda | Raycast |
|---|---|---|
| Next-up summary, join with ↩ | Yes | Yes |
| Day, week and month views | Day list, week and month grids | One list grouped by time |
| Alert when a meeting starts | Prompt, notification or auto-join | Auto-join with confirmation, menu bar |
| Block time | From any free gap, or presets | Yes |
| Accept or decline, email attendees, AI questions, menu bar agenda | No | Yes |

## Next ideas, most useful first

1. Keep calendar access across bridge rebuilds by signing `bin/agenda-calendar` with a stable self-signed certificate (untested).
2. A next-meeting item in the menu bar, through SketchyBar or SwiftBar calling `bin/agenda`.
3. Snooze or skip one alert.
4. A front end on Alfred 6's native UI toolkit once it ships.
5. Accept or decline through Outlook, if it turns out to be needed.

## Risks and open questions

- Most Teams invites here use `teams.microsoft.com/meet/<id>?p=<passcode>`. Opening that as `msteams://` is untested. If the first real join opens Teams without joining, switch off *Open Teams links in the Teams app* and record the result in MEMORY.md.
- With the screen locked, the alert is a notification waiting on the lock screen: macOS doesn't wake the display for it, so it is seen only when someone looks. The join list follows within a minute of the unlock, and not at all once the meeting is more than 5 minutes old.
- Week tiles are small in Alfred's 808-pt window: good for the shape of a week, not for reading titles.
- *Join automatically* can drop the user into a meeting they meant to skip; it is opt-in and only for linked meetings.

## Prior art (researched 13 Nov 2026)

- [Raycast Calendar](https://manual.raycast.com/calendar) — My Schedule, the inspiration.
- [Calendar++](https://github.com/zeitlings/alfred-calendar) — month block and agenda in Alfred; closed source, no alert at start time. Installed here but never run.
- [MeetingBar](https://github.com/leits/MeetingBar) — menu-bar app; its link patterns and app-link rewrites informed `Meeting.swift`.
- [Open Conference URL](https://alfred.app/workflows/caleb531/open-conference-url) — Alfred workflow listing meetings near now.
