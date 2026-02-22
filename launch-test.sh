#!/bin/sh

# Setup
TEST_ROOT="/tmp/CheatDownloader"

export ROM_DIR="$TEST_ROOT/Roms"
export CHEAT_DIR="$TEST_ROOT/Cheats"
export CACHE_DIR="$TEST_ROOT/Cache"
mkdir -p "$CACHE_DIR"

cd "$PAK_DIR"
jimsh cheat-manager.tcl textui debug
