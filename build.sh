#!/bin/zsh --no-rcs
# Rebuild the Agenda helpers after editing anything under src/, then make Alfred
# re-read the workflow from disk.
#
# Two programs are built:
#   bin/agenda-calendar  reads and writes the calendar. macOS ties your "Full Calendar
#                        Access" approval to this exact binary, so it is only rebuilt
#                        when its own source changes. Rebuilding it means macOS asks
#                        for calendar access again.
#   bin/agenda           everything else (views, tiles, meeting links, alerts). Safe to
#                        rebuild as often as you like.
set -e
cd "$(dirname "$0")"
mkdir -p bin

bridge_hash=$(cat src/bridge/main.swift src/bridge/Info.plist | shasum -a 256 | cut -d' ' -f1)
if [[ ! -x bin/agenda-calendar || "$(cat bin/.bridge-source-hash 2>/dev/null)" != "$bridge_hash" ]]; then
  swiftc -O src/bridge/main.swift -o bin/agenda-calendar \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker src/bridge/Info.plist
  codesign --force -s - -i com.situmorang.agenda.calendar bin/agenda-calendar
  print -r -- "$bridge_hash" > bin/.bridge-source-hash
  echo "built bin/agenda-calendar (macOS will ask for calendar access again)"
else
  echo "bin/agenda-calendar unchanged, calendar permission kept"
fi

swiftc -O src/agenda/*.swift -o bin/agenda
echo "built bin/agenda"

./bin/agenda icons >/dev/null
echo "icons redrawn"

if osascript -e 'tell application id "com.runningwithcrayons.Alfred" to reload workflow "com.situmorang.agenda"' 2>/dev/null; then
  echo "Alfred reloaded"
fi
