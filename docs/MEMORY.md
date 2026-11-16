# Agenda — shared memory

The memory every agent and model shares for this workflow; a model's private memory stays invisible to the others. Read it at the start of a task. Add what you learn as you go (a verified behaviour, a decision and its reason, a gotcha), dated, under the heading it belongs to. Fix or delete entries that prove wrong, and mark anything unverified.

This folder is a public git repository, https://github.com/situmorang-com/alfred-agenda, so everything here is public. Keep out event titles, people's names, email addresses, meeting links, and anything about the owner, their Mac or their schedule: that goes in `docs/LOCAL.md`, which git ignores and which exists only on the owner's Mac.

## Environment

Built and tested in November 2026 on macOS 27.2 (Apple silicon) with Alfred 5.8.1 and the Powerpack, Swift 6.4.2, and calendars from Exchange, iCloud and Google accounts in macOS Calendar.

## Calendars in practice

Seen on a real calendar, 13–15 Nov 2026.

- Two calendars can share a title: an Exchange account and iCloud both have one called "Calendar". Hence the "Name (Account)" form in the settings and on new-event rows.
- Birthdays can appear twice, from a Google account and from the system Birthdays calendar.
- Exchange invitations carry the Teams link in the notes, usually wrapped in Outlook Safe Links. Most are `teams.microsoft.com/meet/<id>?p=<passcode>`, some `/l/meetup-join/`.

## Verified: Alfred 5.8

- Grid View (`alfred.workflow.userinterface.grid`, version 1): `columncount` 1–12; `imageaspect` 0 square, 1 portrait (2:3), 2 landscape; `inputtype` 1 runs the script in `inputfile` and passes the upstream argument as `$1`; `fixedorder` keeps the script's order; `filterable` adds the search field. Read from Alfred's config nib, 13 Nov.
- Grid View JSON is Script Filter JSON plus a top-level `preselect` (a `uid`). `rerun` is ignored, so grids never refresh themselves. Item `variables` and `mods` work. With titles and subtitles *in footer*, the footer shows the selected item, and a mod's subtitle while that modifier is held (seen 15 Nov).
- Alfred draws each grid cell's rounded background and the selection highlight behind the image, so tiles are drawn transparent (seen 13 Nov).
- Script Filter `skipknowledge: true` keeps the script's order and still remembers the selected row between reruns.
- `open alfred://runtrigger/<bundle id>/<trigger>/?argument=…` runs an External Trigger with no confirmation, also from a LaunchAgent that has no Automation permission (seen 13 and 15 Nov).
- `tell application id "com.runningwithcrayons.Alfred" to reload workflow "<bundle id>"` reloads a workflow after its files change.
- User configuration reaches scripts as environment variables; Alfred writes changed values to `prefs.plist` in the workflow folder.
- Alfred's Markdown (About text, Text View) has no tables before Alfred 6. Alfred 6 was in closed beta in autumn 2026 with a native "Alfred UI" toolkit; no technical details were public.

## Verified: macOS calendar access

- Since macOS 14, reading events needs `NSCalendarsFullAccessUsageDescription`. Alfred 5.8 declares only the old `NSCalendarsUsageDescription`, so code Alfred starts gets add-only access at best (Calendar++ users hit this).
- A helper started by Alfred is judged as Alfred. Re-spawning itself with responsibility disclaimed, plus a linked-in Info.plist, gives it an identity of its own. Measured 13 Nov from a terminal: a plain child read `writeOnly` (inherited), a disclaimed child `notDetermined` (its own); `agenda-calendar auth` then showed the macOS prompt. The grant holds when Alfred or the LaunchAgent starts the bridge. The extra hop costs about 12 ms.
- The bridge is ad-hoc signed, which identifies code by its hash, so a rebuilt bridge is asked about again. Seen 16 Nov: the rebuilt helper (version 2) read `notDetermined` until `agenda-calendar auth` showed the prompt and access was allowed. Rebuild between two of the alert job's checks, with the owner ready to click, and the job misses nothing.
- Signing the bridge with a stable identity instead might keep the grant across rebuilds; untested.
- Writing works with the grant: on 16 Nov `agenda do` (act `create`, the row's variables from `agenda list "+ …"`) saved a test event through the bridge to the system's default calendar. Read back: right start and end, timed, busy; `day` listed it.
- `open "ical://ekevent/<event id>?method=show&options=more"` opens that event in Calendar: ↩ on the test event in `day tomorrow` opened it (16 Nov).
- Deleting works: on 16 Nov the test event went through `cal -`, the confirmation and its Delete row (`agenda do`, act `delete`) and was gone from the calendar.

## Verified: the alert job

- An alert that comes due while the display sleeps opens Alfred's join list behind the lock screen, unseen (15 Nov). Where the screen locks as soon as the display sleeps (`sysadminctl -screenLock status` says "immediate"), a sleeping display is a locked screen. Hence AL-5.
- That alert was first thought skipped: the `jq` query reading `alerted.json` broke on a Google event id that contains `@` and printed "none". Keys are `<event id>@<start>`: split on the last `@`, and don't read a failed query as "no record" (corrected 16 Nov).
- At Background priority launchd ran the job in fewer than half the minutes the Mac was awake (13–15 Nov). At Standard priority every awake minute had a check, and so did every dark-wake minute; checks started 5–7 s after the minute (16 Nov). `tests/tools/alert-coverage.py` makes this comparison.
- While the Mac sleeps no check runs; on waking, launchd runs one at once, which still alerts up to 5 minutes after the start.
- The helpers write nothing to the system log: `ticks.log` and `alerted.json` are the record.
- Screen state: `CGSessionCopyCurrentDictionary()` answers inside the LaunchAgent, and carries `CGSSessionScreenIsLocked` while the lock screen is up (absent when unlocked). On 16 Nov a background check logged `screen=locked` while the display slept.
- In daily use alerts fire on the minute (16 Nov). None has yet come due while the screen was locked.

## Live testing in Alfred

Seen while testing, 13–16 Nov; the procedure is in TESTING.md.

- Alfred reads held modifiers from the session's real keyboard state. A Return posted to Alfred's process with modifier flags acts as a plain Return. An instant System Events chord (`key code 36 using {option down}`) worked once in a list and was missed by the Grid View. Reliable every time: System Events `key down option`, `delay 0.5`, `key code 36`, `key up option`.
- The mouse pointer resting over Alfred's window moves the selection, and walking with arrow keys is unreliable: a 13 Nov attempt to reach a free-gap row pressed Return on the day header instead. Screenshot before pressing keys.
- Another agent may be driving Alfred at the same time; its typed text once landed in a test window. Check that Alfred's search field holds your text before pressing keys.
- Check for a meeting before a live test: `pgrep -x CptHost` finds a Zoom meeting in progress.
- On 13 Nov an interrupted run left the `.dry-run` file behind, and ↩ did nothing for two days. Create and remove test switches in the same command, with `trap … EXIT`.
- Run `bin/agenda tick` by hand only with `AGENDA_DRY_RUN=1` (or a fixture) and `alfred_workflow_data` pointing at a throwaway folder: a real tick fires due alerts, and even a dry run marks them done in `alerted.json`.

## Decisions

- 13 Nov — A new workflow rather than extending Calendar++: it is closed source, has no alert at start time, and drops the sixth week of long months.
- 13 Nov — EventKit through our own Swift bridge rather than icalBuddy or AppleScript: about 150 ms for 14 days, full detail (attendees, reply state, notes), and a permission of its own.
- 13 Nov — Two binaries, so the one holding the calendar permission rarely changes.
- 13 Nov — Month and week as Grid Views of drawn tiles: Alfred's Markdown has no tables, and Grid View gives seven real columns with keyboard navigation.
- 13 Nov — Alerts from a once-a-minute LaunchAgent rather than a resident process: nothing stays running, it survives logins, and it costs about 120 ms a minute.
- 13 Nov — *prompt* is the default alert style (it opens Alfred's join list) and auto-join is opt-in. Alerts come 1 minute ahead, once per occurrence, only for linked meetings. ↩ joins from 15 minutes before the start.
- 13 Nov — Month tiles give meetings their three lines first; holidays and birthdays had crowded them out.
- 13 Nov — The week's hour range widens at most 3 hours earlier, so one early flight doesn't squash every day.
- 15 Nov — The agenda's keyword is `cal` (the owner's request; it was `agenda`). Another workflow that used `cal` moved aside.
- 15 Nov — Fixture runs never act: with `AGENDA_FIXTURE` set, `agenda do` logs and `agenda tick` prints, so a test can't join a meeting or write an event.
- 15 Nov — *Hidden calendars* also accepts "Name (Account)", as the setting's description already promised.
- 15 Nov — Docs and memory live in this folder, so any model can pick up the work (the owner's request).
- 15 Nov — The alert job runs at Standard priority, not Background, because launchd skipped more than half the awake minutes at Background, and it logs one line per check. Made while the 15 Nov alert was thought skipped; it wasn't (see the alert job above), but the skipped minutes justify the change on their own.
- 16 Nov — While the screen is locked or the display asleep, *prompt* and *auto* post one notification and wait for the first check after the unlock, within the window; *notify* doesn't wait. The owner's choice after an alert opened unseen. It keeps "nothing stays running": no resident helper needed.
- 16 Nov — Events are added from the agenda, `cal +` then what and when (the owner's request). Our own rules read the text, not `NSDataDetector`: they reuse `day`'s day words, read times written with a dot as some locales write them (15.00), and behave predictably, while the row shows the result before ↩. So a dotted date reads as a time ("15.11" is 15:11) and dates take a slash. The bridge's `create` already took all-day, place and calendar, so calendar access was untouched.
- 16 Nov — Deleting (the owner's request, "with confirmation"): `cal -` lists matches, and ↩ opens a confirmation through the router's `v:agenda` branch, so no new Alfred wiring. Its first, preselected row is *Keep it*, so a second ↩ deletes nothing. Meetings with other people, invitations and read-only calendars are refused, in the view and again in the helper, because removing a meeting through EventKit can cancel or decline it for everyone. The helper gained `delete` (bridge version 2): the first change that needed the helper rebuilt and calendar access granted again.
- 16 Nov — The README's animation, `docs/images/demo.gif`, is drawn by `tests/demo.sh` from the fixture and the workflow's own rows and tiles, in an Alfred-style window on a desktop (the owner asked for a GIF to attract people). Not a screen recording: no real calendar can appear in it, nobody's screen is taken over, and anyone can redraw it after a change. Times come out as 10:00 because `demo.swift` passes `-AppleLocale en_GB` to `bin/agenda`.
- 16 Nov — Published like Calculate Anything: MIT licence, `bin/`, `prefs.plist` and `docs/LOCAL.md` ignored by git, and installed by cloning into Alfred's workflows folder and running `build.sh`, because the calendar helper must be built (and granted access) on each Mac.

## Known gaps

- Teams `/meet/` links opened as `msteams://`: untested; the first real join will tell.
- Block time in Alfred, from gap to options to saved event: never completed live (the bridge's `create` it uses does work, see calendar access above).
- `cal +` and `cal -` inside Alfred (typing them, the rows that type `+ ` and `- `, the confirmation reached through `v:agenda` with *Keep it* preselected): tested through the scripts and against a real calendar only.
- The *Allow calendar access* and *switched off* rows: never shown in Alfred.
- The *notify* and *auto* alert styles; Alfred's notify trigger has never been seen working.
- The lock-screen hold (AL-5) is fixture-tested; live, the job has seen the screen locked, but no alert has come due while locked, so the notification and the prompt after the unlock are unseen.
- Changed settings reaching the background job through `prefs.plist`: untested.
- Typed grid arguments in Alfred (`month dec`, `week +1`): tested through the scripts only.
- A packaged `.alfredworkflow` release: none yet. The binaries would need building universal and testing on a Mac that downloaded them.

## History

- 13 Nov 2026 — Research (Raycast, Calendar++, MeetingBar, Alfred 5.5–5.8, Apple TN3152). v1.0.0 built, calendar access granted, alert job installed, views checked live.
- 15 Nov 2026 — A leftover dry-run file found and removed; modifier keys checked live; rows of past days fixed; "Name (Account)" in *Hidden calendars* fixed; fixture tests, previews and these docs added. The agenda's keyword changed from `agenda` to `cal`. The first real alert was thought missed; the alert job moved to Standard priority and now logs every check.
- 16 Nov 2026 — The 15 Nov alert found to have run on time and opened behind the lock screen; docs corrected. Check coverage at Standard priority measured; `tests/tools/alert-coverage.py` added. Alerts due while the screen is locked now notify and wait for the unlock (AL-5); `ticks.log` records the screen state. New events from the agenda: `cal +` (NE-1 to NE-5). *Open in Calendar* confirmed. Deleting with a confirmation: `cal -` (DL-1 to DL-4), with a `delete` command in the helper (version 2). An animated demo and a feature list in the README; notes about the owner's Mac moved to `docs/LOCAL.md`, and the folder published as github.com/situmorang-com/alfred-agenda.

## References

- Apple: [TN3152, migrating to the latest Calendar access levels](https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels)
- Alfred: [Grid View](https://www.alfredapp.com/help/workflows/user-interface/grid/), [Script Filter JSON](https://www.alfredapp.com/help/workflows/inputs/script-filter/json/), [External Trigger](https://www.alfredapp.com/help/workflows/triggers/external/), [changelog](https://www.alfredapp.com/changelog/), [Alfred 6](https://www.alfredapp.com/v6/)
