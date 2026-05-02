#!/bin/sh

# Setup
TEST_ROOT="/tmp/CheatDownloaderOffline"

export ROM_DIR="$TEST_ROOT/Roms"
export CHEAT_DIR="$TEST_ROOT/Cheats"
export CACHE_DIR="$TEST_ROOT/Cache"
mkdir -p "$CACHE_DIR" "$CHEAT_DIR"

# Populate ROM dirs
mkdir -p \
  "$ROM_DIR/MS" \
  "$ROM_DIR/Sega Master System (SMS)" \
  "$ROM_DIR/Microsoft MSX (MSX)" \
  "$ROM_DIR/Sony PlayStation (PS)/Metal Gear Solid"

touch \
  "$ROM_DIR/MS/Alex Kidd in Shinobi World (USA, Europe).zip" \
  "$ROM_DIR/Sega Master System (SMS)/Alex Kidd in Shinobi World (USA, Europe, Brazil).zip" \
  "$ROM_DIR/Microsoft MSX (MSX)/Metal Gear 2 - Solid Snake - Konami (1990) [English v1.4 Slot Patch] [RC-767] [7207].zip" \
  "$ROM_DIR/Microsoft MSX (MSX)/Metal Gear - Konami (1987) [Official English Translation] [RC-750] [Translated] [1474].zip" \
  "$ROM_DIR/Microsoft MSX (MSX)/Metal Gear - Konami (1987) [Official English Translation] [RC-750] [Translated] [1474].rom" \
  "$ROM_DIR/Sony PlayStation (PS)/Metal Gear Solid/Metal Gear Solid [Disc1of2] [U] [SLUS-00594].chd" \
  "$ROM_DIR/Sony PlayStation (PS)/Metal Gear Solid/Metal Gear Solid [Disc2of2] [U] [SLUS-00776].chd" \
  "$ROM_DIR/Sony PlayStation (PS)/Metal Gear Solid/Metal Gear Solid.m3u"

./cheat_manager textui debug
