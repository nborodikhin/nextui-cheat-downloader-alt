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
jimsh cheat-manager.tcl
