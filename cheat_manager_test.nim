import unittest
import std/[os, strutils]
import cheat_manager

const FIXTURES = currentSourcePath().parentDir() / "test" / "fixtures"

# ---------------------------------------------------------------------------
# Temp dir helper
# ---------------------------------------------------------------------------

template withTempDir(tmp: untyped, body: untyped) =
  let tmp = getTempDir() / "cheat_test_" & $getCurrentProcessId()
  createDir(tmp)
  try:
    body
  finally:
    removeDir(tmp)

# ---------------------------------------------------------------------------

suite "extractTag":
  test "bare uppercase tag":
    check extractTag("GBA") == "GBA"
  test "bare multi-char tag":
    check extractTag("CPS1") == "CPS1"
  test "bare two-char tag":
    check extractTag("MS") == "MS"
  test "tag in parens at end":
    check extractTag("Game Boy Advance (GBA)") == "GBA"
  test "full name with tag":
    check extractTag("Sega Master System (SMS)") == "SMS"
  test "no tag — mixed case name":
    check extractTag("Some Folder") == ""
  test "empty string":
    check extractTag("") == ""

# ---------------------------------------------------------------------------

suite "normalizeTitle":
  test "strips extension and parens":
    check normalizeTitle("Metal Gear Solid (USA).cht") == "metalgearsolid"
  test "strips brackets and extension":
    check normalizeTitle("Metal Gear Solid [Disc1of2] [U].chd") == "metalgearsolid"
  test "compound region group":
    check normalizeTitle("Alex Kidd in Shinobi World (USA, Europe).zip") == "alexkiddinshinobiworld"
  test "unrecognized paren group":
    check normalizeTitle("Alex Kidd In Shinobi World (Rumbles).cht") == "alexkiddinshinobiworld"
  test "no extension no groups":
    check normalizeTitle("Castlevania") == "castlevania"

# ---------------------------------------------------------------------------

suite "formatCheatDisplay — tool badges":
  test "Action Replay + region":
    check formatCheatDisplay("Castlevania (Action Replay) (USA).cht") == "Castlevania [AR|US]"
  test "GameShark (one word)":
    check formatCheatDisplay("Castlevania (GameShark) (USA).cht") == "Castlevania [GS|US]"
  test "Game Shark (two words)":
    check formatCheatDisplay("Castlevania (Game Shark) (USA).cht") == "Castlevania [GS|US]"
  test "Game Genie":
    check formatCheatDisplay("Castlevania (Game Genie).cht") == "Castlevania [GG]"
  test "Game Buster":
    check formatCheatDisplay("Castlevania (Game Buster).cht") == "Castlevania [GB]"
  test "Code Breaker (two words)":
    check formatCheatDisplay("Castlevania (Code Breaker).cht") == "Castlevania [CB]"
  test "CodeBreaker (one word)":
    check formatCheatDisplay("Castlevania (CodeBreaker).cht") == "Castlevania [CB]"
  test "Xploder":
    check formatCheatDisplay("Castlevania (Xploder).cht") == "Castlevania [XP]"

suite "formatCheatDisplay — region badges":
  test "USA":
    check formatCheatDisplay("Zanac (USA).cht") == "Zanac [US]"
  test "Japan":
    check formatCheatDisplay("Zanac (Japan).cht") == "Zanac [JP]"
  test "Europe":
    check formatCheatDisplay("Zanac (Europe).cht") == "Zanac [EU]"
  test "World":
    check formatCheatDisplay("Zanac (World).cht") == "Zanac [WD]"
  test "Australia":
    check formatCheatDisplay("Zanac (Australia).cht") == "Zanac [AU]"
  test "Brazil":
    check formatCheatDisplay("Zanac (Brazil).cht") == "Zanac [BR]"
  test "Korea":
    check formatCheatDisplay("Zanac (Korea).cht") == "Zanac [KR]"
  test "Germany":
    check formatCheatDisplay("Zanac (Germany).cht") == "Zanac [DE]"
  test "France":
    check formatCheatDisplay("Zanac (France).cht") == "Zanac [FR]"
  test "Spain":
    check formatCheatDisplay("Zanac (Spain).cht") == "Zanac [ES]"
  test "Italy":
    check formatCheatDisplay("Zanac (Italy).cht") == "Zanac [IT]"

suite "formatCheatDisplay — compound region group":
  test "USA, Europe — USA wins":
    check formatCheatDisplay("Alex Kidd (USA, Europe).cht") == "Alex Kidd [US]"
  test "Europe, Brazil — Europe wins":
    check formatCheatDisplay("Alex Kidd (Europe, Brazil).cht") == "Alex Kidd [EU]"
  test "USA, Europe, Brazil — USA wins":
    check formatCheatDisplay("Alex Kidd (USA, Europe, Brazil).cht") == "Alex Kidd [US]"

suite "formatCheatDisplay — unrecognized groups kept in title":
  test "Rumbles (no region/tool)":
    check formatCheatDisplay("Alex Kidd In Shinobi World (Rumbles).cht") == "Alex Kidd In Shinobi World (Rumbles)"
  test "version tag V2":
    check formatCheatDisplay("Zanac (V2).cht") == "Zanac (V2)"
  test "Rev 1 then region":
    check formatCheatDisplay("Game (Rev 1) (USA).cht") == "Game (Rev 1) [US]"
  test "region then Rev 1":
    check formatCheatDisplay("Game (USA) (Rev 1).cht") == "Game (Rev 1) [US]"
  test "no groups":
    check formatCheatDisplay("Castlevania.cht") == "Castlevania"

suite "formatCheatDisplay — false positive prevention":
  test "Centy contains 'us' but not inside parens":
    check formatCheatDisplay("Crusade of Centy (GameShark) (Japan).cht") == "Crusade of Centy [GS|JP]"
  test "bouken contains 'uk' but not inside parens":
    check formatCheatDisplay("Bouken (Japan).cht") == "Bouken [JP]"

# ---------------------------------------------------------------------------

suite "hasGameFiles":
  test "zip file present":
    withTempDir(tmp):
      writeFile(tmp / "game.zip", "")
      check hasGameFiles(tmp) == true

  test "rom file present":
    withTempDir(tmp):
      writeFile(tmp / "game.rom", "")
      check hasGameFiles(tmp) == true

  test "chd in subdirectory (recursive)":
    withTempDir(tmp):
      createDir(tmp / "subgame")
      writeFile(tmp / "subgame" / "game.chd", "")
      check hasGameFiles(tmp) == true

  test "only srm — excluded":
    withTempDir(tmp):
      writeFile(tmp / "save.srm", "")
      check hasGameFiles(tmp) == false

  test "only sav — excluded":
    withTempDir(tmp):
      writeFile(tmp / "save.sav", "")
      check hasGameFiles(tmp) == false

  test "only cht — excluded":
    withTempDir(tmp):
      writeFile(tmp / "cheat.cht", "")
      check hasGameFiles(tmp) == false

  test "hidden file only — excluded":
    withTempDir(tmp):
      writeFile(tmp / ".game.zip", "")
      check hasGameFiles(tmp) == false

  test "game file inside hidden subdir — excluded":
    withTempDir(tmp):
      createDir(tmp / ".hidden")
      writeFile(tmp / ".hidden" / "game.gb", "")
      check hasGameFiles(tmp) == false

  test "empty directory":
    withTempDir(tmp):
      check hasGameFiles(tmp) == false

# ---------------------------------------------------------------------------

suite "browserListDirs":
  test "tagged folder with game file included":
    withTempDir(tmp):
      let d = tmp / "Game Boy Advance (GBA)"
      createDir(d)
      writeFile(d / "game.gba", "")
      let dirs = browserListDirs(tmp)
      check dirs.len == 1
      check dirs[0].name == "Game Boy Advance (GBA)"

  test "bare uppercase tag folder included":
    withTempDir(tmp):
      let d = tmp / "GBA"
      createDir(d)
      writeFile(d / "game.gba", "")
      let dirs = browserListDirs(tmp)
      check dirs.len == 1
      check dirs[0].name == "GBA"

  test "PS folder with chd in subdir included":
    withTempDir(tmp):
      let d = tmp / "Sony PlayStation (PS)"
      createDir(d / "MGS")
      writeFile(d / "MGS" / "game.chd", "")
      let dirs = browserListDirs(tmp)
      check dirs.len == 1
      check dirs[0].name == "Sony PlayStation (PS)"

  test "untagged folder excluded":
    withTempDir(tmp):
      let d = tmp / "Some Folder"
      createDir(d)
      writeFile(d / "game.zip", "")
      check browserListDirs(tmp).len == 0

  test "tagged folder with only srm excluded":
    withTempDir(tmp):
      let d = tmp / "GBA"
      createDir(d)
      writeFile(d / "save.srm", "")
      check browserListDirs(tmp).len == 0

  test "hidden folder excluded":
    withTempDir(tmp):
      let d = tmp / ".hidden (GBA)"
      createDir(d)
      writeFile(d / "game.gba", "")
      check browserListDirs(tmp).len == 0

  test "empty ROM dir returns empty":
    withTempDir(tmp):
      check browserListDirs(tmp).len == 0

  test "result is sorted alphabetically":
    withTempDir(tmp):
      for name in ["SNES", "GBA", "NDS"]:
        let d = tmp / name
        createDir(d)
        writeFile(d / "game.zip", "")
      let dirs = browserListDirs(tmp)
      check dirs.len == 3
      check dirs[0].name == "GBA"
      check dirs[1].name == "NDS"
      check dirs[2].name == "SNES"

# ---------------------------------------------------------------------------

suite "browserListGames":
  test "sfc file included":
    withTempDir(tmp):
      writeFile(tmp / "game.sfc", "")
      let games = browserListGames(tmp)
      check games.len == 1
      check games[0].name == "game.sfc"

  test "cht file excluded":
    withTempDir(tmp):
      writeFile(tmp / "cheat.cht", "")
      check browserListGames(tmp).len == 0

  test "srm file excluded":
    withTempDir(tmp):
      writeFile(tmp / "save.srm", "")
      check browserListGames(tmp).len == 0

  test "hidden file excluded":
    withTempDir(tmp):
      writeFile(tmp / ".DS_Store", "")
      check browserListGames(tmp).len == 0

  test "subdir with m3u — m3u file listed":
    withTempDir(tmp):
      let sub = tmp / "Metal Gear Solid"
      createDir(sub)
      writeFile(sub / "Metal Gear Solid.m3u", "")
      writeFile(sub / "disc1.chd", "")
      writeFile(sub / "disc2.chd", "")
      let games = browserListGames(tmp)
      check games.len == 1
      check games[0].name == "Metal Gear Solid.m3u"

  test "subdir without m3u but with chd — dir listed":
    withTempDir(tmp):
      let sub = tmp / "Game"
      createDir(sub)
      writeFile(sub / "game.chd", "")
      let games = browserListGames(tmp)
      check games.len == 1
      check games[0].name == "Game"

  test "subdir with only txt files — excluded":
    withTempDir(tmp):
      let sub = tmp / "Extras"
      createDir(sub)
      writeFile(sub / "readme.txt", "")
      check browserListGames(tmp).len == 0

  test "result is sorted alphabetically":
    withTempDir(tmp):
      writeFile(tmp / "Sonic the Hedgehog (USA).zip", "")
      writeFile(tmp / "Alex Kidd in Miracle World (USA).zip", "")
      writeFile(tmp / "Alex Kidd in Shinobi World (USA, Europe).zip", "")
      let games = browserListGames(tmp)
      check games.len == 3
      check games[0].name == "Alex Kidd in Miracle World (USA).zip"
      check games[1].name == "Alex Kidd in Shinobi World (USA, Europe).zip"
      check games[2].name == "Sonic the Hedgehog (USA).zip"

# ---------------------------------------------------------------------------

suite "cheat display sort order":
  test "plain title sorts before Rev-1 suffixed title":
    # '(' ASCII 40 < '[' ASCII 91, so naive cmpIgnoreCase puts "(Rev 1) [US]"
    # before "[US]" — wrong. Sort by title-before-badge as primary key.
    let plain = formatCheatDisplay("Alex Kidd in Miracle World (USA).cht")
    let rev1  = formatCheatDisplay("Alex Kidd in Miracle World (Rev 1) (USA).cht")
    check plain == "Alex Kidd in Miracle World [US]"
    check rev1  == "Alex Kidd in Miracle World (Rev 1) [US]"
    # naive sort is wrong: '[' > '(' so plain sorts after rev1
    check cmpIgnoreCase(plain, rev1) > 0
    # sort by title part (before trailing ' [') is correct
    proc titleKey(s: string): string =
      let i = s.rfind(" ["); if i >= 0: s[0 ..< i] else: s
    check cmpIgnoreCase(titleKey(plain), titleKey(rev1)) < 0

  test "same title: tool badges sort among themselves by badge text":
    let ar = formatCheatDisplay("Castlevania (Action Replay) (USA).cht")
    let gs = formatCheatDisplay("Castlevania (GameShark) (USA).cht")
    let us = formatCheatDisplay("Castlevania (USA).cht")
    check ar == "Castlevania [AR|US]"
    check gs == "Castlevania [GS|US]"
    check us == "Castlevania [US]"
    proc titleKey(s: string): string =
      let i = s.rfind(" ["); if i >= 0: s[0 ..< i] else: s
    check titleKey(ar) == titleKey(gs)
    check titleKey(gs) == titleKey(us)
    check cmpIgnoreCase(ar, gs) < 0
    check cmpIgnoreCase(gs, us) < 0

# ---------------------------------------------------------------------------

suite "stripBracketed":
  test "removes parenthesized group":
    check stripBracketed("Foo (Bar)", '(', ')') == "Foo"
  test "removes multiple groups":
    check stripBracketed("Foo (A) (B)", '(', ')') == "Foo"
  test "removes bracketed group":
    check stripBracketed("Foo [Bar]", '[', ']') == "Foo"
  test "unclosed bracket: space trimmed, open char kept":
    check stripBracketed("Foo (Bar", '(', ')') == "Foo(Bar"
  test "empty string":
    check stripBracketed("", '(', ')') == ""

# ---------------------------------------------------------------------------

suite "createStateStore":
  test "defaults when file missing":
    withTempDir(tmp):
      let s = createStateStore(tmp / "state.json")
      s.load()
      check s.getCheatDbVersion() == ""
      check s.getLastFolder() == ""
      check s.getSystem("GBA") == ""
      check s.getLastGame("GBA") == ""

  test "corrupt JSON does not crash":
    withTempDir(tmp):
      let f = tmp / "state.json"
      writeFile(f, "not json {{{{")
      let s = createStateStore(f)
      s.load()
      check s.getCheatDbVersion() == ""

  test "setCheatDbVersion / getCheatDbVersion round-trip":
    withTempDir(tmp):
      let s = createStateStore(tmp / "state.json")
      s.load()
      s.setCheatDbVersion("v1.2.3", 1024)
      check s.getCheatDbVersion() == "v1.2.3"

  test "isDbFileMissing: file absent":
    withTempDir(tmp):
      let s = createStateStore(tmp / "state.json")
      s.load()
      check s.isDbFileMissing(tmp / "nonexistent.zip") == true

  test "isDbFileMissing: size mismatch":
    withTempDir(tmp):
      let zf = tmp / "cheats.zip"
      writeFile(zf, "dummy")
      let s = createStateStore(tmp / "state.json")
      s.load()
      s.setCheatDbVersion("v1", 99999)
      check s.isDbFileMissing(zf) == true

  test "isDbFileMissing: correct size":
    withTempDir(tmp):
      let zf = tmp / "cheats.zip"
      writeFile(zf, "dummy")
      let s = createStateStore(tmp / "state.json")
      s.load()
      s.setCheatDbVersion("v1", getFileSize(zf))
      check s.isDbFileMissing(zf) == false

  test "setSystem / getSystem round-trip, multiple tags":
    withTempDir(tmp):
      let s = createStateStore(tmp / "state.json")
      s.load()
      s.setSystem("GBA", "Nintendo - Game Boy Advance")
      s.setSystem("SNES", "Nintendo - Super Nintendo")
      check s.getSystem("GBA") == "Nintendo - Game Boy Advance"
      check s.getSystem("SNES") == "Nintendo - Super Nintendo"
      check s.getSystem("NDS") == ""

  test "setLastFolder / getLastFolder persisted across reload":
    withTempDir(tmp):
      let f = tmp / "state.json"
      block:
        let s = createStateStore(f)
        s.load()
        s.setLastFolder("Game Boy Advance (GBA)")
      let s2 = createStateStore(f)
      s2.load()
      check s2.getLastFolder() == "Game Boy Advance (GBA)"

  test "setLastGame / getLastGame round-trip, multiple tags":
    withTempDir(tmp):
      let s = createStateStore(tmp / "state.json")
      s.load()
      s.setLastGame("GBA", "Zelda.gba")
      s.setLastGame("SNES", "Metroid.smc")
      check s.getLastGame("GBA") == "Zelda.gba"
      check s.getLastGame("SNES") == "Metroid.smc"
      check s.getLastGame("NDS") == ""

# ---------------------------------------------------------------------------

suite "isCheatZip":
  test "valid cheat zip":
    check isCheatZip(FIXTURES / "cheats.zip") == true
  test "zip without cht/ entries":
    check isCheatZip(FIXTURES / "not-a-cheat.zip") == false
  test "missing file":
    check isCheatZip(FIXTURES / "nonexistent.zip") == false
  test "non-zip file":
    withTempDir(tmp):
      let f = tmp / "fake.zip"
      writeFile(f, "this is not a zip")
      check isCheatZip(f) == false

suite "findLocalCheatZip":
  test "finds first valid zip":
    withTempDir(tmp):
      copyFile(FIXTURES / "cheats.zip", tmp / "cheats.zip")
      check findLocalCheatZip(tmp) == tmp / "cheats.zip"
  test "ignores invalid zips":
    withTempDir(tmp):
      copyFile(FIXTURES / "not-a-cheat.zip", tmp / "other.zip")
      check findLocalCheatZip(tmp) == ""
  test "empty directory":
    withTempDir(tmp):
      check findLocalCheatZip(tmp) == ""
  test "empty path":
    check findLocalCheatZip("") == ""

# ---------------------------------------------------------------------------

suite "createCheatDb":
  test "getSystems returns expected systems":
    withTempDir(tmp):
      let arch = tmp / "cheats.zip"
      copyFile(FIXTURES / "cheats.zip", arch)
      let db = createCheatDb(arch)
      let systems = db.getSystems()
      check "Nintendo - Game Boy" in systems
      check "Sega - Mega Drive - Genesis" in systems

  test "getAllCheats returns IDs for known system":
    withTempDir(tmp):
      let arch = tmp / "cheats.zip"
      copyFile(FIXTURES / "cheats.zip", arch)
      let db = createCheatDb(arch)
      let ids = db.getAllCheats("Nintendo - Game Boy")
      check ids.len == 2

  test "getCheatName returns correct name":
    withTempDir(tmp):
      let arch = tmp / "cheats.zip"
      copyFile(FIXTURES / "cheats.zip", arch)
      let db = createCheatDb(arch)
      # getAllCheats returns ORDER BY name NOCASE: Kirby first, then Tetris
      let ids = db.getAllCheats("Nintendo - Game Boy")
      check db.getCheatName(ids[0]) == "Kirby's Dream Land (USA, Europe).cht"
      check db.getCheatName(ids[1]) == "Tetris (World).cht"

  test "cache hit: second init skips rebuild":
    withTempDir(tmp):
      let arch = tmp / "cheats.zip"
      copyFile(FIXTURES / "cheats.zip", arch)
      discard createCheatDb(arch)
      let db2 = createCheatDb(arch)
      check db2.getSystems().len == 2

  test "missing archive: no crash, empty systems":
    withTempDir(tmp):
      let db = createCheatDb(tmp / "missing.zip")
      check db.getSystems().len == 0
