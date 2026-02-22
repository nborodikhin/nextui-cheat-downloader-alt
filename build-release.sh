#!/bin/sh

TOOLS_DIR=Tools/tg5040
PAK_NAME="Cheat Downloader Alt.pak"
PAK_DIR="$PAK_NAME"

PAK_FILE="CheatDownloaderAlt.pak.tg5040.zip"
PAKZ_FILE="CheatDownloaderAlt.pakz"

rm -rf release
mkdir -p release/"$PAK_DIR"
mkdir -p release/"$PAK_DIR"/bin/arm
cp launch.sh cheat-manager.tcl README.md pak.json release/"$PAK_DIR"
cp deps/jimsh deps/minui-list deps/minui-presenter release/"$PAK_DIR/bin/arm/"

( cd release; zip -r "$PAK_FILE" "$PAK_DIR" )

mkdir -p release/"$TOOLS_DIR"
mv release/"$PAK_DIR" release/"$TOOLS_DIR"/
( cd release; zip -r "$PAKZ_FILE" "Tools" )

