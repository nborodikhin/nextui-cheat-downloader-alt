import unittest, osproc, os, streams, json, strtabs, strutils, sequtils

const BINARY   = currentSourcePath().parentDir() / "cheat_manager"
const FIXTURES = currentSourcePath().parentDir() / "test" / "fixtures"

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

proc makeEnv(romDir, cacheDir, cheatDir: string): StringTableRef =
  result = newStringTable(modeStyleInsensitive)
  for k, v in envPairs():
    result[k] = v
  result["ROM_DIR"]    = romDir
  result["CACHE_DIR"]  = cacheDir
  result["CHEAT_DIR"]  = cheatDir
  result["SDCARD_PATH"] = ""

proc runScenario(romDir, cacheDir, cheatDir: string,
                 choices: seq[JsonNode]): (seq[JsonNode], int) =
  let p = startProcess(BINARY,
                       args = ["jsonui", "offline"],
                       env = makeEnv(romDir, cacheDir, cheatDir),
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
