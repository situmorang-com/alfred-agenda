#!/bin/zsh --no-rcs
# Draws docs/images/demo.gif, the animation at the top of the README: the agenda, a new event
# typed in plain words, the month, the week, a day's free time and the join alert, all from
# the made-up calendar in tests/fixture.py (never the real one) and the workflow's own rows
# and tiles. Needs ffmpeg (brew install ffmpeg).
#
#   tests/demo.sh [output.gif]      default: docs/images/demo.gif
set -eu
cd "${0:A:h:h}"
out=${1:-docs/images/demo.gif}
[[ -x bin/agenda ]] || { print "bin/agenda is missing: run ./build.sh first"; exit 1; }
command -v ffmpeg >/dev/null || { print "ffmpeg is missing: brew install ffmpeg"; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/agenda-demo.XXXXXX")
trap 'rm -rf "$work"' EXIT
swiftc -O tests/tools/demo.swift -o "$work/demo"
offset=$(python3 tests/fixture.py "$work/events.json")

export AGENDA_FIXTURE="$work/events.json" AGENDA_NOW="2026-11-13T09:56:00$offset"
export alfred_workflow_cache="$work/cache" alfred_workflow_data="$work/data" week_start=1 AGENDA_THEME=light
unset alfred_workflow_bundleid alfred_theme_background

"$work/demo" "$work/frames"
# One palette for the whole animation (no flicker between frames), ordered dithering for the
# wallpaper's gradient, and only the changed part of each frame stored.
ffmpeg -v error -y -f concat -safe 0 -i "$work/frames/frames.txt" \
  -vf "split[a][b];[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  -fps_mode vfr -loop 0 "$out"
print "wrote $out ($(( $(stat -f %z "$out") / 1024 )) KB)"
