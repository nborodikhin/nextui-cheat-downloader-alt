#!/bin/sh

# Setup
TEST_ROOT="/tmp/CheatDownloaderOffline"

export ROM_DIR="$TEST_ROOT/Roms"
export CHEAT_DIR="$TEST_ROOT/Cheats"
export CACHE_DIR="$TEST_ROOT/Cache"
export PATH=hostbin
mkdir -p "$CACHE_DIR"

jimsh cheat-manager.tcl textui debug
