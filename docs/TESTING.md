# Testing Agenda

Cheapest first: fixture tests for behaviour, previews for the look, live tests in Alfred only for the wiring. What each part does: [ARCHITECTURE.md](ARCHITECTURE.md).

## Fixture tests

```sh
tests/smoke.sh
```

Runs every view, the actions and the alert check against the made-up calendar in `tests/fixture.py`, with "now" pinned to Friday 13 Nov 2026 at 09:56 in this Mac's time zone, in a throwaway cache and data folder. It rebuilds `bin/agenda` when a source file is newer (never the bridge), prints one line per check, and exits with the number of failures. Fixture runs never act: `agenda do` writes to `dry-run.log` and `agenda tick` prints what it would do.

When you change behaviour, add a check beside the others for that view:

- `expect "<what>" '<jq test>' <command…>` passes when the command's JSON satisfies the jq test.
- `says "<what>" "<exact output>" <command…>` and `has "<what>" "<text>" <command…>` are for text output.
- A command can set settings and hooks with `env`, for example `env slot="$gap" block_calendar="Calendar (Exchange)" $A block ""`.

Each event in `tests/fixture.py` is commented with what it exercises; extend that calendar rather than making another.

## Hooks

`bin/agenda` reads these, so any view runs outside Alfred.

| Variable | Effect |
|---|---|
| `AGENDA_FIXTURE=<file>` | Read events and calendars from a JSON file shaped like the bridge's replies instead of the calendar. Also makes `do` log and `tick` print rather than act. |
| `AGENDA_NOW=<ISO 8601>` | Pin "now", e.g. `2026-11-13T09:56:00+07:00`. |
| `AGENDA_THEME=light` or `dark` | Force the tile theme (otherwise taken from `alfred_theme_background`). |
| `AGENDA_DRY_RUN=1` | `tick` prints instead of alerting, against the real calendar. Its records still land in the data folder, so point `alfred_workflow_data` at a throwaway folder or the real alert is marked done. |
| `AGENDA_SCREEN=on`, `locked` or `asleep` | What `tick` takes the screen to be (fixture runs otherwise assume `on`). |
| `alfred_workflow_cache`, `alfred_workflow_data` | Redirect the cache and data folders. |
| any setting, e.g. `work_start=9`, `week_start=2`, `alert_style=auto` | Overrides that setting. |
| file `<data>/.dry-run` | `agenda do` logs to `<data>/dry-run.log` instead of acting. For live tests; see below. |

`<data>` is `~/Library/Application Support/Alfred/Workflow Data/com.situmorang.agenda`.

One view by hand:

```sh
offset=$(python3 tests/fixture.py "$TMPDIR/events.json")
AGENDA_FIXTURE="$TMPDIR/events.json" AGENDA_NOW="2026-11-13T09:56:00$offset" bin/agenda day tomorrow | jq '.items[].title'
```

Without `AGENDA_FIXTURE`, the read-only views (`list`, `day`, `join`, `month`, `week`) read the real calendar. Their output is personal: keep it on this Mac, out of files and messages.

## Previews

```sh
tests/preview.sh [folder]
tests/demo.sh [output.gif]
```

`preview.sh` draws the fixture's month and the week after "today" in light and dark, laid out like Alfred's 7-column grid, into `docs/images` or the folder given. After changing `Render.swift`, bump `Render.style`, then compare.

`demo.sh` redraws `docs/images/demo.gif`, the README's animation: the workflow's own rows and tiles for the fixture, in an Alfred-style window on a desktop. `tests/tools/demo.swift` holds the story and the drawing, and ffmpeg encodes it. Redraw it after a change people would see in a view.

## Live tests in Alfred

Live tests check what fixtures can't: Alfred's wiring (routing, modifier keys, keywords), the look inside Alfred's window, the alert job. They take over the user's screen and keyboard.

1. Ask the user for a few hands-off minutes. Check that no meeting is on (`pgrep -x CptHost` finds a Zoom meeting; also look at the top row of `bin/agenda list ""`), and keep to fixture tests while one is.
2. Run each test as one shell command that turns dry-run on and is sure to turn it off, so ↩ can't join a meeting, write an event or replace the clipboard:
   ```sh
   DATA="$HOME/Library/Application Support/Alfred/Workflow Data/com.situmorang.agenda"
   trap 'rm -f "$DATA/.dry-run"' EXIT; touch "$DATA/.dry-run"; rm -f "$DATA/dry-run.log"
   ```
3. Open a view with an external trigger (`agenda`, `day`, `week`, `month`, `join`), with text if needed:
   ```sh
   osascript -e 'tell application id "com.runningwithcrayons.Alfred" to run trigger "day" in workflow "com.situmorang.agenda" with argument "tomorrow"'
   ```
   or type a keyword the user's way: `… to search "cal"`.
4. Before any key, make sure the window is yours: `alfui shot <file.png>` and look at it, and check that `alfui field` prints your text. Build the helper with `swiftc -O tests/tools/alfui.swift -o "$TMPDIR/alfui"`.
5. Plain keys: `alfui key return`, `escape`, `down`, `up` or `tab`. A modifier with Return needs real key state, held across the press:
   ```sh
   osascript -e 'tell application "System Events"' -e 'key down option' -e 'try' -e 'delay 0.5' -e 'key code 36' -e 'end try' -e 'key up option' -e 'end tell'
   ```
   Use `command`, `option` or `control`. The key-up sits outside the `try`, so the modifier is always released.
6. Read `$DATA/dry-run.log` to see what each key would have done, close Alfred with `alfui key escape`, and check that `alfui window` prints `none`.

A real join, a real calendar write and the macOS permission prompt need the user: ask first, and let them watch. Around a real copy test, save and restore every clipboard item and type.
