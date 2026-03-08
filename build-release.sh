#!/bin/sh

PAK_DIR_NAME="Cheat Downloader Offline.pak"
PAKZ_FILE_NAME="CheatDownloaderOffline.pakz"

rm -rf release

for PLATFORM in tg5040 tg5050 my355; do
  PAK_FILE_NAME="CheatDownloaderOffline-$PLATFORM.pak.zip"

  TOOLS_DIR="release/Tools/$PLATFORM"
  PAK_DIR="$TOOLS_DIR/$PAK_DIR_NAME"
  BIN_DIR="$PAK_DIR/bin/arm"

  mkdir -p "$PAK_DIR"
  for file in launch.sh cheat-manager.tcl README.md pak.json; do
    cp $file "$PAK_DIR/"
  done

  mkdir -p "$BIN_DIR"
  for binary in jimsh minui-list minui-presenter mz; do
    cp deps/$binary-$PLATFORM "$BIN_DIR/$binary"
  done

  ( cd "$TOOLS_DIR"; zip -r "$PAK_FILE_NAME" "$PAK_DIR_NAME" )
  mv "$TOOLS_DIR/$PAK_FILE_NAME" release/
done

( cd release; zip -r "$PAKZ_FILE_NAME" "Tools" )

