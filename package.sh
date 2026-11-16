#!/bin/zsh --no-rcs
# Builds the release package, Agenda.alfredworkflow: the committed files (without the README's
# images) plus both programs built for Apple silicon and Intel, macOS 14 or later. It works in
# a throwaway folder, so your own bin/, and the calendar access macOS granted to it, stay as
# they are.
#
#   ./package.sh [output]      default: dist/Agenda.alfredworkflow
set -eu
cd "${0:A:h}"
out=${1:-dist/Agenda.alfredworkflow}
out=${out:A}
[[ -z "$(git status --porcelain)" ]] || { print "Commit first: the package is built from the last commit."; exit 1; }

stage=$(mktemp -d "${TMPDIR:-/tmp}/agenda-package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
git archive HEAD | tar -x -C "$stage"
rm -rf "$stage/docs/images" "$stage/.gitignore"

# The same flags as build.sh, once per architecture, then joined.
mkdir -p "$stage/bin"
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos14 src/agenda/*.swift -o "$stage/bin/agenda-$arch"
  swiftc -O -target $arch-apple-macos14 src/bridge/main.swift -o "$stage/bin/agenda-calendar-$arch" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker src/bridge/Info.plist
done
lipo -create "$stage"/bin/agenda-{arm64,x86_64} -output "$stage/bin/agenda"
lipo -create "$stage"/bin/agenda-calendar-{arm64,x86_64} -output "$stage/bin/agenda-calendar"
rm "$stage"/bin/*-{arm64,x86_64}
codesign --force -s - "$stage/bin/agenda"
codesign --force -s - -i com.situmorang.agenda.calendar "$stage/bin/agenda-calendar"

mkdir -p "${out:h}"
rm -f "$out"
(cd "$stage" && zip -r -X -q "$out" . -x '*.DS_Store')
print "wrote $out ($(( $(stat -f %z "$out") / 1024 )) KB): version $(plutil -extract version raw -o - info.plist), $(lipo -archs "$stage/bin/agenda")"
