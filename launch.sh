#!/bin/sh

# Setup
PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"
set -x
LOG_FILE="$LOGS_PATH/$PAK_NAME.txt"
rm -f "$LOG_FILE"
exec >>"$LOG_FILE"
exec 2>&1
export PATH="$PAK_DIR/bin/arm:$PATH"

# Constants
export ROM_DIR="$ROMS_PATH"
export CHEAT_DIR="$CHEATS_PATH"
export CACHE_DIR="$HOME/$PAK_NAME"
mkdir -p "$CACHE_DIR"

cd "$PAK_DIR"

# Development hook:
# - if the restart flag file is present when the app exits, run it again.
# `./dev run` uses this to swap in a freshly built binary without dropping
# back to the menu: it pushes the binary, touches the flag, and kills the app.
RESTART_FLAG_FILE=/tmp/nextui-cheat-downloader.restart

# The app runs minui-list and minui-presenter as child processes and kills
# them itself on the way out. A SIGKILL skips that cleanup, so they outlive
# the app and keep holding the screen and the buttons - clear any strays
# here, between runs, where there is no chance of hitting a fresh instance.
cleanup_helpers() {
  for helper in minui-list minui-presenter; do
    helper_pids=$(pidof "$helper") || continue
    kill -9 $helper_pids
  done
}

while :; do
  rm -f "$RESTART_FLAG_FILE"
  cheat_manager
  cleanup_helpers

  [ -e "$RESTART_FLAG_FILE" ] || break
done
