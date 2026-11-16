# Agenda — guide for AI agents

Agenda is an Alfred workflow that shows the user's macOS calendar as an agenda, a day, a week and a month, opens video meetings, blocks free time and raises an alert when a meeting starts.

## Read first

- `docs/MEMORY.md` — what earlier sessions learned: verified Alfred and macOS behaviour, decisions and their reasons, known gaps. Read it at the start of every task.
- `docs/LOCAL.md`, on the owner's Mac only (git ignores it): before testing inside Alfred or touching anything outside this folder. Paths, accounts, apps, the owner's calendars, house rules.
- `docs/PRD.md` — what each feature must do, and how far it is verified. Read before changing behaviour.
- `docs/ARCHITECTURE.md` — the two binaries, the Alfred object graph, the `act` contract, rendering, alerts, settings. Read before changing code or `info.plist`.
- `docs/TESTING.md` — fixture tests, hooks, previews, live tests in Alfred, the release package. Read before testing.
- `docs/CHANGELOG.md` — release notes.

## Build and test

```sh
./build.sh       # rebuild what changed, redraw icons, reload the workflow in Alfred
tests/smoke.sh   # fixture tests: made-up calendar, throwaway folders, nothing real touched
./package.sh     # the release package, dist/Agenda.alfredworkflow, from the last commit
```

A change is done when `tests/smoke.sh` passes with a check for the new behaviour, any change to Alfred wiring has been tried live (`docs/TESTING.md`), and the docs match the code: PRD status, ARCHITECTURE for design, MEMORY for what you learned.

A release, when the owner asks: add the notes to `docs/CHANGELOG.md`, bump `version` in `info.plist`, commit, run `./package.sh`, test the package (`docs/TESTING.md`), push, then `gh release create v<version> dist/Agenda.alfredworkflow --target main --title "Agenda <version>" --notes-file <the version's notes>`.

## Guardrails

- **Calendar access belongs to `bin/agenda-calendar`.** macOS tied the user's Full Calendar Access grant to that exact binary, and rebuilding it asks the user again. Leave `src/bridge/` as it is unless a feature needs it, tell the user before you change it, and let `build.sh` rebuild it (it does so only when that source changed).
- **The bundle id stays `com.situmorang.agenda`.** The alert job's label, the `alfred://runtrigger/…` links and the cache and data folders are derived from it.
- **`info.plist` is Alfred's, `prefs.plist` the user's.** Change objects and settings in Alfred's editor, or edit `info.plist` by hand keeping object UIDs, check it with `plutil -lint`, and reload the workflow. `prefs.plist` holds the user's setting values; leave it as it is.
- **Everything tracked is public.** This folder is a public git repository: https://github.com/situmorang-com/alfred-agenda. Notes about the owner, their Mac or their schedule go in `docs/LOCAL.md`; git ignores it, `bin/`, `dist/` and `prefs.plist`.
- **Calendar data is personal.** Use the fixture for examples, screenshots and bug reports; real event titles, names, email addresses and meeting links stay out of files, commits and anything sent off this Mac.
- **Live tests take over the user's screen.** Ask first, check for a meeting, and turn dry-run on and off within one command (`docs/TESTING.md`).
- **The alert job outlives the folder.** Run `bin/agenda alerts off` before deleting, moving or renaming the workflow.

## Conventions

- Plain `swiftc`: one module in `src/agenda/`, one file in `src/bridge/`, no packages.
- Comments say why. UI text is short and sentence case, with ` · ` between parts, like the existing rows.
- After changing how tiles look, bump `Render.style` so cached tiles are redrawn.
- Anything that runs `bin/` sources `scripts/ready.zsh` first; that file says why.

## Shared memory

`docs/MEMORY.md` is the memory every agent and model shares; your private memory is invisible to the others. Record durable learnings there as you go (a verified behaviour, a decision and its reason, a gotcha), dated, under the matching heading, and correct entries that prove wrong. What only matters on the owner's Mac goes in `docs/LOCAL.md` instead.
