#!/usr/bin/env python3
"""Did the alert job check every minute the Mac was awake?

Lines up the job's check log (ticks.log, one line per check) with the sleep, wake and
display events in `pmset -g log`, minute by minute. A minute the Mac was fully awake with
no check is a missed check. Asleep or in dark wake (Power Nap) no check is expected:
launchd runs one check on waking instead, for the minutes it slept through.

    tests/tools/alert-coverage.py                                       the last 24 hours
    tests/tools/alert-coverage.py "2026-11-16 08:00" "2026-11-16 08:30"   from, to (exclusive)

Exit status 1 when a check was missed while awake. Both logs hold times and counts only.
"""
import bisect
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

TICKS = Path.home() / "Library/Application Support/Alfred/Workflow Data/com.situmorang.agenda/ticks.log"
STAMP = "%Y-%m-%d %H:%M:%S"
MINUTE = timedelta(minutes=1)
ORDER = ["awake, screen on", "awake, screen off", "dark wake", "asleep", "sleeping or waking"]


def power_events():
    """(time, kind) for sleep, wake, dark wake and display changes, oldest first."""
    log = subprocess.run(["pmset", "-g", "log"], capture_output=True, text=True).stdout
    events = []
    for line in log.splitlines():
        head, _, message = line.partition("\t")
        try:
            when = datetime.strptime(head[:19], STAMP)
        except ValueError:
            continue
        # The event type sits after "YYYY-MM-DD HH:MM:SS +ZZZZ ", padded with spaces.
        kind = {"Sleep": "sleep", "Wake": "wake", "DarkWake": "dark"}.get(head[26:].strip())
        if message.startswith("Display is turned on"):
            kind = "screen on"
        elif message.startswith("Display is turned off"):
            kind = "screen off"
        if kind:
            events.append((when, kind))
    events.sort(key=lambda event: event[0])
    return events


def timeline(events):
    """Change times, and the (power, screen) state from each of them on."""
    times, states = [], []
    power, screen = "awake", "on"
    for when, kind in events:
        if kind == "sleep":
            power, screen = "asleep", "off"
        elif kind == "dark":
            power, screen = "dark wake", "off"
        elif kind == "wake":
            power = "awake"
        else:
            screen = kind.split()[1]
        times.append(when)
        states.append((power, screen))
    return times, states


def checks():
    """Minute marks that had a check, mapped to how many seconds after the mark it started."""
    runs = {}
    for line in TICKS.read_text().splitlines():
        if line.endswith(" test"):  # dry runs
            continue
        try:
            when = datetime.strptime(line[:19], STAMP)
        except ValueError:
            continue
        runs.setdefault(when.replace(second=0), when.second)
    return runs


def ranges(minutes):
    """Consecutive (minute, kind) pairs grouped into [first, last, kind]."""
    groups = []
    for minute, kind in minutes:
        if groups and groups[-1][2] == kind and minute - groups[-1][1] == MINUTE:
            groups[-1][1] = minute
        else:
            groups.append([minute, minute, kind])
    return groups


def main():
    if not TICKS.exists():
        sys.exit(f"no check log at {TICKS}")
    now = datetime.now().replace(second=0, microsecond=0)
    given = [datetime.strptime(arg, "%Y-%m-%d %H:%M") for arg in sys.argv[1:3]]
    start = given[0] if given else now - timedelta(days=1)
    end = given[1] if len(given) > 1 else now

    events = power_events()
    times, states = timeline(events)
    switches = [when for when, kind in events if kind in ("sleep", "wake", "dark")]
    runs = checks()

    # Neither log reaches back forever: pmset keeps a few days, ticks.log about two.
    earliest = max(times[0] if times else start, min(runs) if runs else start)
    if start < earliest:
        start = earliest.replace(second=0) + MINUTE
        print(f"(the logs start at {earliest:%d %b %H:%M}; counting from there)")

    counts = {}  # kind of minute -> [minutes, minutes with a check]
    missed, late = [], []
    minute = start
    while minute < end:
        # launchd starts the job about 5 s after the mark; a sleep or wake right around it
        # makes the minute ambiguous, so it gets a row of its own.
        if bisect.bisect_right(switches, minute + timedelta(seconds=15)) > bisect.bisect_left(switches, minute - timedelta(seconds=1)):
            kind = "sleeping or waking"
        else:
            i = bisect.bisect_right(times, minute + timedelta(seconds=6)) - 1
            power, screen = states[i] if i >= 0 else ("awake", "on")
            kind = f"awake, screen {screen}" if power == "awake" else power
        row = counts.setdefault(kind, [0, 0])
        row[0] += 1
        if minute in runs:
            row[1] += 1
            if kind.startswith("awake"):
                late.append(runs[minute])
        elif kind.startswith("awake"):
            missed.append((minute, kind))
        minute += MINUTE

    print(f"Minutes from {start:%d %b %H:%M} to {end:%d %b %H:%M}, and how many had a check:")
    for kind in sorted(counts, key=lambda k: ORDER.index(k) if k in ORDER else len(ORDER)):
        total, checked = counts[kind]
        print(f"  {kind:<20} {total:5} min  {checked:5} checked")
    if late:
        late.sort()
        print(f"Checks while awake started {late[len(late) // 2]} s after the minute (median), {late[-1]} s at most")
    print(f"Missed while awake: {len(missed) or 'none'}")
    for first, last, kind in ranges(missed):
        span = f"{first:%d %b %H:%M}" + (f"–{last:%H:%M}" if last != first else "")
        print(f"  {span}  ({kind})")
    sys.exit(1 if missed else 0)


if __name__ == "__main__":
    main()
