#!/bin/zsh --no-rcs
# Fixture tests for Agenda: every view, the actions and the alert check, run against the
# made-up calendar in tests/fixture.py with "now" pinned to Friday 13 Nov 2026, 09:56, in a
# throwaway cache and data folder. Fixture runs never touch the real calendar, Alfred or the
# background job: actions and alerts only report what they would do.
#
#   tests/smoke.sh        one line per check; exit status = number of failures
set -u
cd "${0:A:h:h}"

# Rebuild bin/agenda when a source file is newer. The calendar bridge is never rebuilt here.
if [[ ! -x bin/agenda || -n "$(find src/agenda -name '*.swift' -newer bin/agenda)" ]]; then
  print "building bin/agenda…"
  swiftc -O src/agenda/*.swift -o bin/agenda || exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/agenda-smoke.XXXXXX")
trap 'rm -rf "$work"' EXIT
offset=$(python3 tests/fixture.py "$work/events.json") || exit 1

export AGENDA_FIXTURE="$work/events.json"
export AGENDA_NOW="2026-11-13T09:56:00$offset"
export alfred_workflow_cache="$work/cache" alfred_workflow_data="$work/data"
export week_start=1   # Sunday, so grid sizes don't depend on this Mac's setting
unset alfred_workflow_bundleid alfred_theme_background AGENDA_THEME AGENDA_DRY_RUN

A=./bin/agenda
failures=0
pass() { print -r -- "ok    $1" }
fail() { print -r -- "FAIL  $1${2:+  ($2)}"; (( failures++ )) }

# expect "<what>" '<jq test>' <command…>     the command's JSON satisfies the jq test
expect() {
  local what=$1 test=$2; shift 2
  if "$@" 2>/dev/null | jq -e "$test" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi
}
# says "<what>" "<exact output>" <command…>  the command prints exactly that
says() {
  local what=$1 want=$2; shift 2
  local got; got=$("$@" 2>/dev/null)
  if [[ "$got" == "$want" ]]; then pass "$what"; else fail "$what" "got: ${got:-nothing}"; fi
}
# has "<what>" "<text>" <command…>           the command's output contains the text
has() {
  local what=$1 want=$2; shift 2
  local got; got=$("$@" 2>/dev/null)
  if [[ "$got" == *"$want"* ]]; then pass "$what"; else fail "$what" "got: ${got:-nothing}"; fi
}
at() { print -r -- "2026-11-13T$1$offset" }   # a pinned time on the fixture day
fresh() { rm -rf "$work/data" }                # forget which meetings were already alerted

print "— agenda"
expect "next-up row is the meeting in 4 minutes, and ↩ joins it" \
  '.items[0].uid == "next-up" and (.items[0].title | contains("Sprint kickoff")) and .items[0].variables.act == "open"' $A list ""
expect "Teams link is unwrapped from Safe Links and opens in the Teams app" \
  '(.items[0].variables.url | startswith("msteams://teams.microsoft.com/meet/412206769")) and (.items[0].variables.web | startswith("https://teams.microsoft.com/"))' $A list ""
expect "all-day events of one day fold into one row" '[.items[] | select(.uid == "allday-2026-11-13")] | length == 1' $A list ""
expect "declined and cancelled events are hidden" '[.items[].title | select(test("Declined thing|Cancelled thing"))] | length == 0' $A list ""
expect "finished events drop off" '[.items[].title | select(contains("Daily stand-up"))] | length == 0' $A list ""
expect "refreshes every 5 s while a meeting is near" '.rerun == 5' $A list ""
expect "typing searches the next 60 days" '(.items | length == 1) and (.items[0].title | contains("Vendor call"))' $A list "vendor"

print "— day"
expect "today's header" '.items[0].arg == "2026-11-13"' $A day ""
expect "a free gap between meetings can be blocked" '[.items[] | select(.variables.slot == "2026-11-13T12:00~2026-11-13T14:00")] | length == 1' $A day ""
expect "day word: tomorrow" '.items[0].arg == "2026-11-14"' $A day tomorrow
expect "day word: 24/11" '.items[0].arg == "2026-11-24"' $A day 24/11
expect "day word: +3" '.items[0].arg == "2026-11-16"' $A day +3
expect "rows of a past day point at that day" '.items[1].mods.ctrl.variables.date == "2026-11-10"' $A day 2026-11-10
expect "hidden calendar by name and account hides only that one" \
  '([.items[].title | select(contains("Groceries"))] | length == 0) and ([.items[].title | select(contains("Sprint kickoff"))] | length == 1)' \
  env ignored_calendars="Calendar (iCloud)" $A day ""
expect "hidden calendar by name hides every calendar with it" \
  '[.items[].title | select(test("Groceries|Sprint kickoff"))] | length == 0' env ignored_calendars="calendar" $A day ""

print "— join"
expect "the meeting about to start comes first" '.items[0].title | contains("Sprint kickoff")' $A join ""
expect "Zoom link opens in the Zoom app with its passcode" \
  '[.items[] | select(.title | contains("Website design review")) | .variables.url][0] == "zoommtg://acme.zoom.us/join?confno=98765432100&pwd=QWERTY"' $A join ""
expect "⌥ copies the web link" '.items[0].mods.alt.variables.act == "copy" and (.items[0].mods.alt.variables.text | startswith("https://teams.microsoft.com/"))' $A join ""
expect "⌘ opens the event in Calendar" '.items[0].mods.cmd.variables.act == "cal"' $A join ""

print "— block time"
gap="2026-11-13T12:00~2026-11-13T14:00"
expect "a 2-hour gap offers the whole gap, 30 min and 1 hour" \
  '(.items | length == 3) and .items[0].variables.act == "block" and ((.items[0].variables.end | tonumber) - (.items[0].variables.start | tonumber) == 7200)' \
  env slot="$gap" $A block ""
expect "blocks go to the default calendar" '.items[0].subtitle | contains("Calendar (iCloud)")' env slot="$gap" $A block ""
expect "the block calendar setting picks the account" '.items[0].variables.calid == "CAL-EX"' env slot="$gap" block_calendar="Calendar (Exchange)" $A block ""
expect "typed text becomes the title; a whole day offers 3 presets" '(.items | length == 3) and .items[0].variables.title == "Deep work"' env slot=2026-11-14 $A block "Deep work"

print "— month and week"
expect "month grid: whole weeks, today preselected" '(.items | length == 35) and .preselect == "2026-11-13"' $A month ""
expect "⌥ and ⌃ move a month" '.items[0].mods.alt.variables.month == "2026-12" and .items[0].mods.ctrl.variables.month == "2026-10"' $A month ""
expect "month word: dec" '.items[0].uid == "2026-11-29" and .preselect == "2026-12-01"' $A month dec
missing=0
for tile in ${(f)"$($A month "" | jq -r '.items[].icon.path')"}; do [[ -s $tile ]] || (( missing++ )); done
(( missing == 0 )) && pass "every month tile is drawn" || fail "every month tile is drawn" "$missing missing"
light=$(env AGENDA_THEME=light $A month "" | jq -r '.items[0].icon.path')
dark=$(env AGENDA_THEME=dark $A month "" | jq -r '.items[0].icon.path')
[[ -n $light && $light != "$dark" ]] && pass "light and dark themes draw separate tiles" || fail "light and dark themes draw separate tiles"
expect "week grid: 7 days, today preselected" '(.items | length == 7) and .items[0].uid == "2026-11-08" and .preselect == "2026-11-13"' $A week ""
expect "week word: +1" '.items[0].uid == "2026-11-15"' $A week +1

print "— meeting links"
has "Google redirect is unwrapped" "Meet" $A detect "see https://www.google.com/url?q=https://meet.google.com/abc-defg-hij&sa=D"
has "Zoom personal rooms stay in the browser" "open: https://acme.zoom.us/my/someone" $A detect "https://acme.zoom.us/my/someone"
says "plain text has no meeting" "no meeting link found" $A detect "lunch at noon"

print "— alerts (fixture runs only report)"
fresh
says "90 s before a 1-minute alert: nothing yet" "" env AGENDA_NOW="$(at 09:58:30)" $A tick
says "1 minute before: alert" "would alert (prompt): Sprint kickoff starts in 1 min" env AGENDA_NOW="$(at 09:59:00)" $A tick
says "same meeting again: no second alert" "" env AGENDA_NOW="$(at 09:59:30)" $A tick
fresh
says "up to 5 minutes late: still alerts" "would alert (prompt): Sprint kickoff has started" env AGENDA_NOW="$(at 10:03:00)" $A tick
fresh
says "more than 5 minutes late: no alert" "" env AGENDA_NOW="$(at 10:06:00)" $A tick
says "a meeting without a link: no alert" "" env AGENDA_NOW="$(at 15:29:00)" $A tick
says "…unless links-only is off" "would alert (prompt): Dentist starts in 1 min" env AGENDA_NOW="$(at 15:29:00)" alert_links_only=0 $A tick
fresh
says "lead time and style are settings" "would alert (auto): Website design review starts in 5 min" \
  env AGENDA_NOW="$(at 10:55:00)" alert_lead=5 alert_style=auto $A tick
says "style off: no alert" "" env AGENDA_NOW="$(at 10:59:00)" alert_style=off $A tick
ticks="$work/data/ticks.log"
[[ -f $ticks ]] && grep -q 'calendar=ok events=[0-9]* due=1 took=[0-9]*ms screen=on test$' "$ticks" && pass "every check is logged" || fail "every check is logged"
[[ -f $ticks ]] && ! grep -qiE 'website|sprint|dentist|review' "$ticks" && pass "the check log holds no event titles" || fail "the check log holds no event titles"

print "— alerts while the screen is locked (AGENDA_SCREEN stands in for the real screen)"
fresh
says "locked: one notification, and the prompt waits" "would notify (screen locked; prompt held): Sprint kickoff starts in 1 min" \
  env AGENDA_NOW="$(at 09:59:00)" AGENDA_SCREEN=locked $A tick
says "still locked: no second notification" "" env AGENDA_NOW="$(at 10:00:00)" AGENDA_SCREEN=locked $A tick
says "unlocked within 5 minutes: the prompt opens" "would alert (prompt): Sprint kickoff has started" env AGENDA_NOW="$(at 10:01:00)" $A tick
says "…once" "" env AGENDA_NOW="$(at 10:02:00)" $A tick
fresh
says "display asleep: auto-join waits too" "would notify (screen asleep; auto held): Sprint kickoff starts in 1 min" \
  env AGENDA_NOW="$(at 09:59:00)" AGENDA_SCREEN=asleep alert_style=auto $A tick
fresh
says "the notify style doesn't wait" "would alert (notify): Sprint kickoff starts in 1 min" \
  env AGENDA_NOW="$(at 09:59:00)" AGENDA_SCREEN=locked alert_style=notify $A tick

print "— new events (typed after + in the agenda)"
epoch() { date -j -f '%Y-%m-%dT%H:%M:%S' "$1:00" +%s }   # local time, as the views use
expect "a day and a time: a new event in the default calendar" \
  ".items[0].variables.act == \"create\" and .items[0].title == \"Dentist\" and .items[0].variables.calid == \"CAL-IC\" and (.items[0].variables.start | tonumber) == $(epoch 2026-11-14T15:00) and ((.items[0].variables.end | tonumber) - (.items[0].variables.start | tonumber)) == 3600" \
  $A list "+ Dentist tomorrow 3pm"
expect "a time already past today means tomorrow" "(.items[0].variables.start | tonumber) == $(epoch 2026-11-14T09:00)" $A list "+ Standup 9:00"
expect "a range, with the title around it" \
  ".items[0].title == \"Lunch with Ana\" and (.items[0].variables.start | tonumber) == $(epoch 2026-11-13T12:00) and (.items[0].variables.end | tonumber) == $(epoch 2026-11-13T13:00)" \
  $A list "+ Lunch with Ana 12-13"
expect "a date, a dotted time and a length" \
  ".items[0].title == \"Review\" and (.items[0].variables.start | tonumber) == $(epoch 2026-11-24T14:00) and (.items[0].variables.end | tonumber) == $(epoch 2026-11-24T14:30)" \
  $A list "+ Review 24/11 14.00 for 30 min"
expect "a day alone makes an all-day event" ".items[0].variables.allday == \"1\" and (.items[0].variables.start | tonumber) == $(epoch 2026-11-16T00:00)" $A list "+ Offsite mon"
expect "a name that looks like a day stays in the title" \
  ".items[0].title == \"Coffee with Tom\" and (.items[0].variables.start | tonumber) == $(epoch 2026-11-14T09:00)" $A list "+ Coffee with Tom tomorrow 9am"
expect "an overlap is named" '.items[0].subtitle | contains("overlaps Sprint kickoff")' $A list "+ Call 10:00"
expect "a row per calendar that takes events, none for read-only ones" \
  '[.items[].variables.calid] | sort == ["CAL-DESIGN","CAL-EX","CAL-HOME","CAL-IC","CAL-WORK"]' $A list "+ Call 10:00"
expect "@ picks the calendar" '.items[0].variables.calid == "CAL-EX" and .items[0].title == "Planning"' $A list "+ Planning tomorrow 10:00 @exchange"
expect "the calendar from the settings comes first" '.items[0].variables.calid == "CAL-EX"' env block_calendar="Calendar (Exchange)" $A list "+ Planning tomorrow 10:00"
expect "without a day or time: a hint, nothing to save" '(.items | length == 1) and .items[0].valid == false' $A list "+ Dentist"
expect "the agenda ends with rows that type + and -" '.items[-2].autocomplete == "+ " and .items[-1].autocomplete == "- " and .items[-1].valid == false' $A list ""

print "— deleting (typed after - in the agenda)"
expect "- lists matching events, and ↩ asks first" \
  ".items[0].title == \"Dentist\" and .items[0].variables.act == \"v:agenda\" and .items[0].variables.confirm == \"FX-7\" and (.items[0].variables.cstart | tonumber) == $(epoch 2026-11-13T15:30)" \
  $A list "- dentist"
expect "a meeting with other people isn't offered: ↩ opens it" '.items[0].variables.act == "cal" and (.items[0].subtitle | contains("other people"))' $A list "- sprint"
expect "an event in a read-only calendar isn't offered" '.items[0].variables.act == "cal" and (.items[0].subtitle | contains("read-only"))' $A list "- birthday"
expect "the confirmation keeps the event on its first row" \
  '(.items | length == 2) and .items[0].title == "Keep it" and .items[0].variables.confirm == "" and .items[1].variables.act == "delete" and .items[1].variables.span == "this" and .items[1].variables.eid == "FX-7"' \
  env confirm=FX-7 cstart=$(epoch 2026-11-13T15:30) $A list ""
expect "a repeating event also offers this and later ones" '(.items | length == 3) and .items[2].variables.span == "future"' env confirm=FX-10 cstart=$(epoch 2026-11-13T18:30) $A list ""
expect "the confirmation refuses a meeting with other people" '(.items | length == 2) and .items[0].valid == false and .items[1].title == "Keep it"' \
  env confirm=FX-4 cstart=$(epoch 2026-11-13T10:00) $A list ""
expect "Keep it goes back to the agenda" '.items[0].uid == "next-up"' env confirm="" cstart="" $A list ""

print "— actions (fixture runs only log)"
fresh
env act=copy text="hello" note="Copied" $A do >/dev/null 2>&1
env act=block title="Deep work" calid=CAL-EX start=1794549600 end=1794553200 $A do >/dev/null 2>&1
env act=create title="Planning" calid=CAL-EX start=1794624000 end=1794627600 allday=0 $A do >/dev/null 2>&1
env act=delete eid=FX-7 start=$(epoch 2026-11-13T15:30) span=this title=Dentist $A do >/dev/null 2>&1
log="$work/data/dry-run.log"
[[ -f $log ]] && grep -q '^act=copy ' "$log" && pass "copy is logged, not done" || fail "copy is logged, not done"
[[ -f $log ]] && grep -q '^act=block .*title=Deep work calid=CAL-EX' "$log" && pass "block is logged, not written to a calendar" || fail "block is logged, not written to a calendar"
[[ -f $log ]] && grep -q '^act=create .*allday=0 title=Planning calid=CAL-EX' "$log" && pass "a new event is logged, not written to a calendar" || fail "a new event is logged, not written to a calendar"
[[ -f $log ]] && grep -q '^act=delete .*event=yes .*span=this title=Dentist' "$log" && pass "a delete is logged, not done" || fail "a delete is logged, not done"

print -- "\n$failures failure(s)"
exit $failures
