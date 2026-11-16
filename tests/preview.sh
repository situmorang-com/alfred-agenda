#!/bin/zsh --no-rcs
# Draws the fixture's month and week grids in light and dark, laid out like Alfred's
# 7-column Grid View. Use it to check tile changes without opening Alfred (bump Render.style
# in src/agenda/Render.swift first) and to refresh the pictures in docs/images.
#
#   tests/preview.sh [output folder]      default: docs/images
set -eu
cd "${0:A:h:h}"
out=${1:-docs/images}
[[ -x bin/agenda ]] || { print "bin/agenda is missing: run ./build.sh first"; exit 1; }
mkdir -p "$out"

work=$(mktemp -d "${TMPDIR:-/tmp}/agenda-preview.XXXXXX")
trap 'rm -rf "$work"' EXIT
swiftc -O tests/tools/sheet.swift -o "$work/sheet"
offset=$(python3 tests/fixture.py "$work/events.json")

export AGENDA_FIXTURE="$work/events.json" AGENDA_NOW="2026-11-13T09:56:00$offset"
export alfred_workflow_cache="$work/cache" alfred_workflow_data="$work/data" week_start=1
unset alfred_workflow_bundleid alfred_theme_background

for theme in light dark; do
  export AGENDA_THEME=$theme
  "$work/sheet" "$out/month-$theme.png" 7 112 $theme ${(f)"$(./bin/agenda month "" | jq -r '.items[].icon.path')"}
  "$work/sheet" "$out/week-$theme.png" 7 112 $theme ${(f)"$(./bin/agenda week +1 | jq -r '.items[].icon.path')"}
done
print "wrote $out/month-light.png, month-dark.png, week-light.png, week-dark.png"
