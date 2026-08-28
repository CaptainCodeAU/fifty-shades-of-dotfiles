#!/bin/sh
# Flips whether update-title.sh prefixes the title with the hostname. Run
# this by hand right after `herdr --remote` (and again when you're back
# local) -- herdr has no way to tell a plugin whether the current viewer
# is local or remote, so this can't be automatic.
set -eu

state_file="$HERDR_PLUGIN_STATE_DIR/show_host"
if [ -f "$state_file" ]; then
  rm -f "$state_file"
  echo "Window title: hostname hidden."
else
  touch "$state_file"
  echo "Window title: hostname shown."
fi
