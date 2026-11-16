#!/bin/zsh --no-rcs
# Source for the Week grid view: prints Grid View JSON, one tile per day.
exec "${0:A:h:h}/bin/agenda" week "$1"
