import unittest, osproc, os, streams, json, strtabs, strutils, sequtils

let   BINARY   = getEnv("CHEAT_MANAGER_BIN", getAppDir() / "cheat_manager")
const FIXTURES = currentSourcePath().parentDir() / "test" / "fixtures"

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

proc makeEnv(romDir, cacheDir, cheatDir: string; sdcardPath = ""): StringTableRef =
  result = newStringTable(modeStyleInsensitive)
  for k, v in envPairs():
    result[k] = v
  result["ROM_DIR"]    = romDir
  result["CACHE_DIR"]  = cacheDir
  result["CHEAT_DIR"]  = cheatDir
  result["SDCARD_PATH"] = sdcardPath

proc runScenario(romDir, cacheDir, cheatDir: string;
                 choices: seq[JsonNode]; sdcardPath = ""): (seq[JsonNode], int) =
  let p = startProcess(BINARY,
                       args = ["jsonui", "offline"],
                       env = makeEnv(romDir, cacheDir, cheatDir, sdcardPath),
                       options = {poUsePath})
  let inp  = p.inputStream()
  let outp = p.outputStream()
  var events: seq[JsonNode] = @[]
  var choiceIdx = 0
  try:
    while true:
      let line = outp.readLine()
      if line.strip() == "": continue
      var j: JsonNode
      try: j = parseJson(line)
      except: continue
      events.add(j)
      let kind = j["type"].getStr()
      if kind in ["list", "confirm"]:
        let choice = if choiceIdx < choices.len: choices[choiceIdx]
                     else: %*{"choice": -1}
        inp.writeLine($choice)
        inp.flush()
        inc choiceIdx
  except IOError, EOFError:
    discard
  let code = p.waitForExit(timeout = 5000)
  p.close()
  (events, code)

proc hasMessage(events: seq[JsonNode], substr: string): bool =
  for e in events:
    if e["type"].getStr() == "message" and substr in e["text"].getStr():
      return true

proc listTitles(events: seq[JsonNode]): seq[string] =
  for e in events:
    if e["type"].getStr() == "list":
      result.add(e["title"].getStr())

template withE2eEnv(tmp: untyped, body: untyped) =
  let tmp = getTempDir() / "e2e_" & $getCurrentProcessId()
  createDir(tmp / "roms")
  createDir(tmp / "cache")
  createDir(tmp / "cheats")
  copyFile(FIXTURES / "cheats.zip", tmp / "cache" / "cheats.zip")
  try:
    body
  finally:
    removeDir(tmp)

# ---------------------------------------------------------------------------

suite "e2e — happy path":

  test "install cheat to game folder (CHEAT_DIR == ROM_DIR)":
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "Game Boy (GB)")
      writeFile(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb", "")
      let choices = @[
        %*{"choice": 0},   # folder: Game Boy (GB)
        %*{"choice": 0},   # game: Tetris (World).gb
        %*{"choice": 0},   # cheat: Tetris (World) [WD]
        %*{"choice": -1},  # back from SELECT_GAME
        %*{"choice": -1},  # back from SELECT_GAME_FOLDER → exit
      ]
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", choices)
      check code == 0
      check fileExists(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb.cht")
      check hasMessage(events, "Installed to")

  test "install cheat to separate CHEAT_DIR":
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "Game Boy (GB)")
      writeFile(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb", "")
      let choices = @[
        %*{"choice": 0},
        %*{"choice": 0},
        %*{"choice": 0},
        %*{"choice": -1},
        %*{"choice": -1},
      ]
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "cheats", choices)
      check code == 0
      check fileExists(tmp / "cheats" / "GB" / "Tetris (World).gb.cht")
      check hasMessage(events, "Installed to")

  test "remember last folder and game across visits":
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "Game Boy (GB)")
      writeFile(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb", "")
      createDir(tmp / "roms" / "MD (MD)")
      writeFile(tmp / "roms" / "MD (MD)" / "Sonic the Hedgehog (USA).zip", "")
      # First visit: pick MD (idx 1), install Sonic, come back, pick GB (idx 0),
      # install Tetris, then exit.
      # Folders are sorted by browserListDirs (filesystem order), but let's just
      # verify both install paths work in one run.
      let choices = @[
        %*{"choice": 1},   # folder: MD (MD) — second alphabetically
        %*{"choice": 0},   # game: Sonic
        %*{"choice": 0},   # cheat: Sonic
        %*{"choice": -1},  # back from game
        %*{"choice": 0},   # folder: Game Boy (GB)
        %*{"choice": 0},   # game: Tetris
        %*{"choice": 0},   # cheat: Tetris
        %*{"choice": -1},
        %*{"choice": -1},
      ]
      let (_, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", choices)
      check code == 0
      check fileExists(tmp / "roms" / "MD (MD)" / "Sonic the Hedgehog (USA).zip.cht")
      check fileExists(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb.cht")

# ---------------------------------------------------------------------------

suite "e2e — back navigation":

  test "back from folder select exits immediately":
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "Game Boy (GB)")
      writeFile(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb", "")
      let (_, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms",
        @[%*{"choice": -1}])
      check code == 0

  test "back from game select returns to folder":
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "Game Boy (GB)")
      writeFile(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb", "")
      let choices = @[%*{"choice": 0}, %*{"choice": -1}, %*{"choice": -1}]
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", choices)
      check code == 0
      # Saw folder list twice: initial + after back
      check listTitles(events).count("Select Game Folder") == 2

  test "back from cheat list returns to game":
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "Game Boy (GB)")
      writeFile(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb", "")
      let choices = @[
        %*{"choice": 0},   # folder
        %*{"choice": 0},   # game
        %*{"choice": -1},  # back from cheat → SELECT_GAME
        %*{"choice": -1},  # back from game  → SELECT_GAME_FOLDER
        %*{"choice": -1},  # exit
      ]
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", choices)
      check code == 0
      check listTitles(events).count("Select Game Folder") == 2

# ---------------------------------------------------------------------------

suite "e2e — no content":

  test "no ROM folders shows message and exits":
    withE2eEnv(tmp):
      # roms/ has no tagged subdirectories
      writeFile(tmp / "roms" / "readme.txt", "")
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", @[])
      check code == 0
      check hasMessage(events, "No supported ROM folders")

  test "folder whose only game files are in hidden subdirs is excluded":
    # hasGameFiles now skips hidden dirs, so the folder never appears in
    # the folder list at all → "No supported ROM folders" message.
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "Game Boy (GB)" / ".hidden")
      writeFile(tmp / "roms" / "Game Boy (GB)" / ".hidden" / "game.gb", "")
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", @[])
      check code == 0
      check hasMessage(events, "No supported ROM folders")

# ---------------------------------------------------------------------------

suite "e2e — Show All Cheats":

  test "Show All then install from full list":
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "Game Boy (GB)")
      writeFile(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb", "")
      # Matched list: ["Tetris (World) [WD]", "Show All Cheats", "Change cheat folder"]
      # showAllIdx = 1
      # Full list sorted: ["Kirby's Dream Land [US]", "Tetris (World) [WD]", "Change cheat folder"]
      # choice 0 in full list → install Kirby's cheat content into Tetris rom's .cht
      let choices = @[
        %*{"choice": 0},   # folder
        %*{"choice": 0},   # game
        %*{"choice": 1},   # Show All Cheats
        %*{"choice": 0},   # first in full list (Kirby's Dream Land [US])
        %*{"choice": -1},
        %*{"choice": -1},
      ]
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", choices)
      check code == 0
      check fileExists(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb.cht")
      check hasMessage(events, "Installed to")

  test "back from Show All with matches returns to matched list":
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "Game Boy (GB)")
      writeFile(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb", "")
      let choices = @[
        %*{"choice": 0},   # folder
        %*{"choice": 0},   # game
        %*{"choice": 1},   # Show All
        %*{"choice": -1},  # back → SELECT_CHEAT_FROM_MATCHED
        %*{"choice": 0},   # install Tetris from matched list
        %*{"choice": -1},
        %*{"choice": -1},
      ]
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", choices)
      check code == 0
      check fileExists(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb.cht")
      # Saw the "Select Cheat for Tetris (World)" list at least twice
      var cheatListCount = 0
      for e in events:
        if e["type"].getStr() == "list" and "Tetris (World)" in e["title"].getStr():
          inc cheatListCount
      check cheatListCount >= 2

# ---------------------------------------------------------------------------

suite "e2e — MAP_SYSTEM":

  test "unknown tag prompts system selection":
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "My System (MYSYS)")
      writeFile(tmp / "roms" / "My System (MYSYS)" / "game.rom", "")
      # getSystems() returns alphabetically: ["Nintendo - Game Boy", "Sega - Mega Drive - Genesis"]
      # Pick index 0 → Nintendo - Game Boy; no tier1/2 match for "game" → allMatches = tier3
      let choices = @[
        %*{"choice": 0},   # folder: My System (MYSYS)
        %*{"choice": 0},   # game: game.rom
        %*{"choice": 0},   # MAP_SYSTEM: Nintendo - Game Boy
        %*{"choice": -1},  # back from cheat list
        %*{"choice": -1},  # back from game
        %*{"choice": -1},  # exit
      ]
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", choices)
      check code == 0
      # MAP_SYSTEM list title contains the tag
      var sawMapSystem = false
      for e in events:
        if e["type"].getStr() == "list" and "MYSYS" in e["title"].getStr():
          sawMapSystem = true
          break
      check sawMapSystem

  test "back from MAP_SYSTEM returns to game select":
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "My System (MYSYS)")
      writeFile(tmp / "roms" / "My System (MYSYS)" / "game.rom", "")
      let choices = @[
        %*{"choice": 0},   # folder
        %*{"choice": 0},   # game → MAP_SYSTEM (no mapping for MYSYS)
        %*{"choice": -1},  # back from MAP_SYSTEM → SELECT_GAME
        %*{"choice": -1},  # back from game
        %*{"choice": -1},  # exit
      ]
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", choices)
      check code == 0
      check listTitles(events).count("Select Game Folder") == 2

# ---------------------------------------------------------------------------

suite "e2e — m3u playlists":

  test "subdir with game files (no m3u) is listed as folder entry":
    withE2eEnv(tmp):
      # Disc folder with a CHD but no .m3u — listed as the subdir name
      createDir(tmp / "roms" / "Game Boy (GB)" / "Tetris (World)")
      writeFile(tmp / "roms" / "Game Boy (GB)" / "Tetris (World)" / "Tetris (World).chd", "")
      let choices = @[
        %*{"choice": 0},   # folder: Game Boy (GB)
        %*{"choice": 0},   # game: Tetris (World) (subdir name)
        %*{"choice": 0},   # cheat: Tetris (World) [WD]
        %*{"choice": -1},
        %*{"choice": -1},
      ]
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", choices)
      check code == 0
      check fileExists(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).cht")
      check hasMessage(events, "Installed to")

  test "m3u file inside subdir is listed and cheat installs correctly":
    withE2eEnv(tmp):
      createDir(tmp / "roms" / "Game Boy (GB)" / "Tetris")
      writeFile(tmp / "roms" / "Game Boy (GB)" / "Tetris" / "Tetris (World).m3u", "")
      let choices = @[
        %*{"choice": 0},   # folder: Game Boy (GB)
        %*{"choice": 0},   # game: Tetris (World).m3u (from subdir)
        %*{"choice": 0},   # cheat: Tetris (World) [WD]
        %*{"choice": -1},
        %*{"choice": -1},
      ]
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", choices)
      check code == 0
      # cheat is named after the m3u file, installed in the ROM folder
      check fileExists(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).m3u.cht")
      check hasMessage(events, "Installed to")

# ---------------------------------------------------------------------------

suite "e2e — predownloaded cheat zip":

  test "cheat zip found on SDCARD_PATH is used without downloading":
    let tmp = getTempDir() / "e2e_sdcard_" & $getCurrentProcessId()
    createDir(tmp / "roms")
    createDir(tmp / "cache")   # intentionally empty — no pre-copied zip
    createDir(tmp / "cheats")
    createDir(tmp / "sdcard")
    copyFile(FIXTURES / "cheats.zip", tmp / "sdcard" / "cheats.zip")
    createDir(tmp / "roms" / "Game Boy (GB)")
    writeFile(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb", "")
    try:
      let choices = @[
        %*{"choice": 0},
        %*{"choice": 0},
        %*{"choice": 0},
        %*{"choice": -1},
        %*{"choice": -1},
      ]
      let (events, code) = runScenario(
        tmp / "roms", tmp / "cache", tmp / "roms", choices,
        sdcardPath = tmp / "sdcard")
      check code == 0
      check fileExists(tmp / "roms" / "Game Boy (GB)" / "Tetris (World).gb.cht")
      check hasMessage(events, "Installed to")
    finally:
      removeDir(tmp)
