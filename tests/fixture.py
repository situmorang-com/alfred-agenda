#!/usr/bin/env python3
"""A made-up calendar for testing Agenda without touching the real one.

Writes JSON shaped like the calendar bridge's replies (`agenda-calendar events` plus
`agenda-calendar calendars`) around Friday 13 November 2026 in this Mac's time zone, and
prints that day's UTC offset (for example +07:00) so callers can pin "now":

    offset=$(python3 tests/fixture.py events.json)
    AGENDA_FIXTURE=events.json AGENDA_NOW=2026-11-13T09:56:00$offset bin/agenda list ""

tests/smoke.sh checks against these events, so change the two together. All names are invented.
"""
import json
import sys
from datetime import datetime, timedelta

DAY0 = datetime(2026, 11, 13)  # a Friday. Naive datetimes are local time, so offsets follow DST.

CALENDARS = [
    # Two calendars share the title "Calendar", as Exchange and iCloud accounts often do.
    {"id": "CAL-EX", "title": "Calendar", "source": "Exchange", "color": "#1E90FF", "writable": True},
    {"id": "CAL-IC", "title": "Calendar", "source": "iCloud", "color": "#5AC8FA", "writable": True},
    {"id": "CAL-HOME", "title": "Home", "source": "iCloud", "color": "#FF3B30", "writable": True},
    {"id": "CAL-WORK", "title": "Work", "source": "iCloud", "color": "#FFCC00", "writable": True},
    {"id": "CAL-DESIGN", "title": "Design", "source": "Google", "color": "#AF52DE", "writable": True},
    {"id": "CAL-HOL", "title": "Hari Libur Indonesia", "source": "Subscribed Calendars", "color": "#34C759", "writable": False},
    {"id": "CAL-BDAY", "title": "Birthdays", "source": "Other", "color": "#FF9500", "writable": False},
]
DEFAULT_CALENDAR = "CAL-IC"

# A Teams invite the way Outlook writes it: the join link wrapped in Safe Links, plus help links.
TEAMS_NOTES = (
    "Agenda: sprint goals\n\n________________\nMicrosoft Teams meeting\nJoin: "
    "https://apc01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fmeet%2F412206769%3Fp%3DAbCdEf"
    "&data=05%7C02&reserved=0\n"
    "Meeting ID: 412 206 769\nNeed help? https://aka.ms/JoinTeamsMeeting?omkt=en-GB | "
    "Meeting options <https://teams.microsoft.com/meetingOptions/?organizerId=1>"
)


def ts(day, hour=0, minute=0):
    """Epoch seconds for a local time `day` days after DAY0."""
    return (DAY0 + timedelta(days=day, hours=hour, minutes=minute)).timestamp()


def people(count):
    return [{"name": f"Person {k}", "status": "accepted", "me": k == 0, "type": "person"} for k in range(count)]


def event(n, title, day, start=None, end=None, calendar="CAL-EX", days=1, **fields):
    """`start` and `end` are (hour, minute); leave them out for an all-day event lasting `days`."""
    cal = next(c for c in CALENDARS if c["id"] == calendar)
    all_day = start is None
    e = {
        "id": f"FX-{n}", "itemId": f"ITEM-{n}", "title": title, "allDay": all_day,
        "start": ts(day) if all_day else ts(day, *start),
        "end": ts(day + days) - 1 if all_day else ts(day, *end),
        "calendarId": cal["id"], "calendar": cal["title"], "color": cal["color"], "source": cal["source"],
        "status": "none", "availability": "busy",
    }
    e.update(fields)
    return e


EVENTS = [
    # Friday 13 November: "today", with now pinned to 09:56.
    event(1, "Hari Pahlawan (observed)", 0, calendar="CAL-HOL"),      # two all-day events fold into one row
    event(2, "Budi's birthday", 0, calendar="CAL-BDAY"),
    event(3, "Daily stand-up", 0, (9, 0), (9, 30), notes=TEAMS_NOTES,
          attendees=people(6), myStatus="accepted"),                    # finished: drops off the agenda
    event(4, "Sprint kickoff", 0, (10, 0), (10, 30), notes=TEAMS_NOTES, location="Microsoft Teams Meeting",
          attendees=people(5), myStatus="accepted"),                    # in 4 min: next up, ↩ joins, alert due at 09:59
    event(5, "Website design review", 0, (11, 0), (12, 0), calendar="CAL-DESIGN",
          url="https://acme.zoom.us/j/98765432100?pwd=QWERTY",
          attendees=people(3), myStatus="accepted"),                    # Zoom app link with passcode
    event(6, "1:1 with Rina", 0, (14, 0), (15, 0), myStatus="tentative", attendees=people(2),
          notes="Join: <https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d>"),
    event(7, "Dentist", 0, (15, 30), (16, 0), calendar="CAL-HOME",
          location="Klinik Gigi Sehat\nJl. Sudirman 12"),               # no link: no alert unless links-only is off
    event(8, "Declined thing", 0, (16, 0), (17, 0), myStatus="declined", attendees=people(4)),  # hidden
    event(9, "Cancelled thing", 0, (16, 0), (17, 0), status="canceled"),                        # hidden
    event(10, "Groceries", 0, (18, 30), (19, 0), calendar="CAL-IC", recurring=True),  # the other "Calendar" (iCloud); repeats

    # The weeks around it.
    event(11, "Catch-up", 3, (9, 0), (9, 30), calendar="CAL-WORK",
          location="https://meet.google.com/abc-defg-hij", attendees=people(2), myStatus="pending"),
    event(12, "Architecture workshop", 3, (13, 0), (17, 0), notes=TEAMS_NOTES,
          attendees=people(12), myStatus="accepted"),
    event(13, "Vendor call", 3, (14, 0), (15, 0), calendar="CAL-DESIGN",
          url="https://acme.webex.com/meet/vendor", attendees=people(3)),   # overlaps the workshop
    event(14, "Partner summit", 4, calendar="CAL-WORK", days=3),            # all-day across three days
    event(15, "Late release window", 5, (20, 0), (23, 30), calendar="CAL-HOME"),  # widens the week's hours
    event(16, "Early breakfast briefing", 6, (6, 30), (7, 30)),
    event(17, "Overnight deploy", 7, (22, 0), (26, 0), calendar="CAL-HOME"),       # crosses midnight
    event(18, "Quarterly planning", -3, (10, 0), (12, 0), notes=TEAMS_NOTES, attendees=people(9)),  # a past day
    event(19, "Team lunch", -2, (12, 0), (13, 0), location="Warung Tekko"),
    event(20, "Board prep", 11, (9, 0), (10, 0)),                           # a busy day: "+N more" on its tile
    event(21, "Budget review", 11, (10, 30), (11, 30)),
    event(22, "Hiring sync", 11, (13, 0), (13, 30)),
    event(23, "Customer demo", 11, (15, 0), (16, 0), notes=TEAMS_NOTES),
    event(24, "Retro", 11, (16, 30), (17, 30)),
    event(25, "Month-end close", 17, calendar="CAL-WORK"),
]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: fixture.py <output.json>")
    reply = {"status": "fullAccess", "events": EVENTS, "calendars": CALENDARS, "defaultCalendarId": DEFAULT_CALENDAR}
    with open(sys.argv[1], "w") as f:
        json.dump(reply, f, indent=1)
    offset = (DAY0 + timedelta(hours=9, minutes=56)).astimezone().strftime("%z")
    print(f"{offset[:3]}:{offset[3:]}")


if __name__ == "__main__":
    main()
