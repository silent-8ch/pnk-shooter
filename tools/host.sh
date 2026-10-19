#!/bin/sh
# Launches the game and hosts at once (main.gd's --host), with your saved ship.
# Extra arguments go to Godot, e.g. tools/host.sh --windowed
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.." && exec "$GODOT" --path . "$@" -- --host
