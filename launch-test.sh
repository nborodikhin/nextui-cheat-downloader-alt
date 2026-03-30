#!/bin/sh

# Setup
TEST_ROOT="/tmp/CheatDownloaderOffline"

export ROM_DIR="$TEST_ROOT/Roms"
export CHEAT_DIR="$TEST_ROOT/Cheats"
export CACHE_DIR="$TEST_ROOT/Cache"
mkdir -p "$CACHE_DIR"

./cheat_manager textui debug
