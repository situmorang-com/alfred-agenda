# Sourced before every run of bin/agenda: by the Script Filters and the Run Script in
# info.plist, and by scripts/month.sh and scripts/week.sh.
#
# A workflow downloaded from the internet and imported into Alfred keeps macOS's download
# flag (com.apple.quarantine) on its files, and macOS then refuses to run the two helpers in
# bin/, which Apple hasn't notarized. Clearing the flag from this workflow's own bin/ and
# scripts/ lets them run; nothing outside the workflow folder is touched. zsh does it itself
# (the zsh/attr module), so it costs no extra process, and nothing at all once the flag is gone.
zmodload zsh/attr 2>/dev/null || return 0
for file in ${0:A:h:h}/{bin,scripts}/*(N.); do
  zdelattr $file com.apple.quarantine 2>/dev/null
done
return 0
