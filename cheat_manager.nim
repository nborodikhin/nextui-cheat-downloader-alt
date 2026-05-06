## Cheat file manager - faithful port from Tcl to Nim.
##
## Reads ROM_DIR, CACHE_DIR, CHEAT_DIR from environment.
## Persists state as JSON, indexes zip archives into SQLite,
## and provides dual-mode UI (text terminal or minui-presenter/minui-list).

import std/[json, osproc, os, posix, streams, strutils, strformat, algorithm]
import db_connector/db_sqlite
import miniz

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

type
  AppEnv = object
    romDir: string
    cacheDir: string
    cheatDir: string

  AppState = enum
    FIND_LOCAL_DB
    CHECK_UPDATE
    CONFIRM_DOWNLOAD
    CONFIRM_UPDATE
    DOWNLOAD
    INIT_DB
    SELECT_GAME_FOLDER
    SELECT_GAME
    MAP_SYSTEM
    FIND_CHEATS
    SELECT_CHEAT_FROM_MATCHED
    SELECT_CHEAT_FROM_ALL
    INSTALL_CHEAT
    EXIT

  StateStore* = object
    load*: proc()
    save*: proc()
    getCheatDbVersion*: proc(): string
    setCheatDbVersion*: proc(version: string, fileSize: int64 = 0)
    isDbFileMissing*: proc(path: string): bool
    getSystem*: proc(tag: string): string
    setSystem*: proc(tag, system: string)
    getLastFolder*: proc(): string
    setLastFolder*: proc(name: string)
    getLastGame*: proc(tag: string): string
    setLastGame*: proc(tag, game: string)

  CheatDb* = object
    getSystems*: proc(): seq[string]
    getAllCheats*: proc(system: string): seq[int]
    getCheatName*: proc(id: int): string
    extractCheat*: proc(id: int, target: string): bool

  UI = object
    killPresenter: proc(signal: cint = SIGKILL, cleanup: bool = true)
    message: proc(text: string, timeout: int = 0)
    messages: proc(lines: seq[string], timeout: int = 86400)
    nextMessage: proc()
    confirm: proc(text: string, confirmText: string = "Yes",
                  cancelText: string = "No"): bool
    list: proc(title: string, items: seq[string],
                selectedIndex: int = 0): int

  DirEntry* = object
    name*: string
    path*: string

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------

var
  env: AppEnv
  stateStore: StateStore
  cheatDb: CheatDb
  ui: UI
  debugMode: bool = false
  offlineMode: bool = false

const
  CMD_CURL = "curl"
  CMD_MINUI_PRESENTER = "minui-presenter"
  CMD_MINUI_LIST = "minui-list"

  EXCLUDED_EXTS = [".txt", ".md", ".xml", ".db", ".pdf", ".cht", ".png",
                   ".jpg", ".jpeg", ".srm", ".sav"]

# ---------------------------------------------------------------------------
# Debug
# ---------------------------------------------------------------------------

proc debug(args: varargs[string, `$`]) =
  if debugMode:
    var msg = "debug: "
    for a in args:
      msg.add(a)
    echo msg

# ---------------------------------------------------------------------------
# Exec wrapper (logs in debug mode)
# ---------------------------------------------------------------------------

proc execCmdRaw(command: string, args: openArray[string],
                options: set[ProcessOption] = {poUsePath}): tuple[
                    output: string, exitCode: int] =
  ## Like execCmd but returns raw output without stripping.
  debug command, " ", args.join(" ")
  let p = startProcess(command, args = args, options = options + {poUsePath})
  let output = p.outputStream.readAll()
  let exitCode = p.waitForExit()
  p.close()
  result = (output: output, exitCode: exitCode)

# ---------------------------------------------------------------------------
# StateStore
# ---------------------------------------------------------------------------

proc createStateStore*(filePath: string): StateStore =
  var data: JsonNode = %*{
    "dbVersion": "",
    "dbFileSize": 0,
    "lastFolder": "",
    "tags": {},
    "lastGame": {}
  }

  proc load() =
    if fileExists(filePath):
      try:
        let content = readFile(filePath)
        data = parseJson(content)
      except:
        echo "Error loading state: ", getCurrentExceptionMsg()

  proc save() =
    try:
      let jsonStr = $data
      debug "Saving ", jsonStr
      writeFile(filePath, jsonStr & "\n")
    except:
      echo "Error saving state: ", getCurrentExceptionMsg()

  proc getCheatDbVersion(): string =
    if data.hasKey("dbVersion"):
      return data["dbVersion"].getStr("")
    return ""

  proc setCheatDbVersion(version: string, fileSize: int64 = 0) =
    data["dbVersion"] = %version
    data["dbFileSize"] = %fileSize
    save()

  proc isDbFileMissing(path: string): bool =
    if not fileExists(path):
      return true
    var storedSize: int64 = 0
    if data.hasKey("dbFileSize"):
      storedSize = data["dbFileSize"].getBiggestInt(0)
    if getFileSize(path) != storedSize:
      return true
    return false

  proc getSystem(tag: string): string =
    if data.hasKey("tags") and data["tags"].hasKey(tag):
      return data["tags"][tag].getStr("")
    return ""

  proc setSystem(tag, system: string) =
    if not data.hasKey("tags"):
      data["tags"] = newJObject()
    data["tags"][tag] = %system
    save()

  proc getLastFolder(): string =
    if data.hasKey("lastFolder"):
      return data["lastFolder"].getStr("")
    return ""

  proc setLastFolder(name: string) =
    data["lastFolder"] = %name
    save()

  proc getLastGame(tag: string): string =
    if data.hasKey("lastGame") and data["lastGame"].hasKey(tag):
      return data["lastGame"][tag].getStr("")
    return ""

  proc setLastGame(tag, game: string) =
    if not data.hasKey("lastGame"):
      data["lastGame"] = newJObject()
    data["lastGame"][tag] = %game
    save()

  result = StateStore(
    load: load,
    save: save,
    getCheatDbVersion: getCheatDbVersion,
    setCheatDbVersion: setCheatDbVersion,
    isDbFileMissing: isDbFileMissing,
    getSystem: getSystem,
    setSystem: setSystem,
    getLastFolder: getLastFolder,
    setLastFolder: setLastFolder,
    getLastGame: getLastGame,
    setLastGame: setLastGame,
  )

# ---------------------------------------------------------------------------
# CheatDb namespace
# ---------------------------------------------------------------------------

proc createCheatDb*(archiveFile: string): CheatDb =
  var db: DbConn
  var initialized = false

  proc normalizeSystemName(name: string): string =
    ## Strip trailing parenthesized suffix from an archive system name.
    let p = name.rfind('(')
    if p >= 0 and name.endsWith(')'):
      result = name[0 ..< p].strip(trailing = true)
    else:
      result = name

  proc init() =
    if not fileExists(archiveFile):
      ## TODO - throw exception
      return

    let dbFile = archiveFile.changeFileExt(".db")

    try:
      db = open(dbFile, "", "", "")
    except:
      ## TODO - throw exception
      echo "Error opening database: ", getCurrentExceptionMsg()
      return

    db.exec(sql"CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT)")
    db.exec(sql"CREATE TABLE IF NOT EXISTS systems (name TEXT PRIMARY KEY)")
    db.exec(sql"CREATE TABLE IF NOT EXISTS cheats (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, path TEXT, system TEXT)")

    # Check if cached DB matches the current archive (needed if file extension is changed, for example)
    var stored = ""
    let rows = db.getAllRows(sql"SELECT value FROM metadata WHERE key='archive_file'")
    if rows.len > 0:
      stored = rows[0][0]

    let cntRows = db.getAllRows(sql"SELECT count(*) as cnt FROM cheats")
    let cnt = parseInt(cntRows[0][0])
    if stored == archiveFile and cnt > 0:
      initialized = true
      return  # cache hit

    # Archive has changed (or DB is empty) - rebuild
    db.exec(sql"DELETE FROM metadata")
    db.exec(sql"DELETE FROM systems")
    db.exec(sql"DELETE FROM cheats")

    let entries = mzListArchive(archiveFile)

    db.exec(sql"BEGIN TRANSACTION")

    for path in entries:
      if path == "" or path[^1] == '/':
        continue

      # Pattern: .../cht/System Name/Cheat Name.cht
      let ci = path.find("cht/")
      if ci >= 0:
        let rest = path[ci + 4 .. ^1]
        let slash = rest.find('/')
        if slash < 0:
          continue
        let systemName = rest[0 ..< slash]
        let cheatFilename = rest[slash + 1 .. ^1]

        if cheatFilename.endsWith(".md"):
          continue

        let normSystem = normalizeSystemName(systemName)
        let cheatName = extractFilename(cheatFilename)

        db.exec(sql"INSERT OR IGNORE INTO systems(name) VALUES(?)", normSystem)
        db.exec(sql"INSERT INTO cheats(name, path, system) VALUES(?, ?, ?)",
                        cheatName, path, normSystem)

    db.exec(sql"INSERT INTO metadata(key,value) VALUES('archive_file', ?)", archiveFile)
    db.exec(sql"COMMIT")
    initialized = true

  proc getSystems(): seq[string] =
    if not initialized: return @[]
    let rows = db.getAllRows(sql"SELECT name FROM systems ORDER BY name COLLATE NOCASE")
    result = @[]
    for row in rows:
      result.add(row[0])

  proc getAllCheats(system: string): seq[int] =
    if not initialized: return @[]
    let rows = db.getAllRows(sql"SELECT id FROM cheats WHERE system=? ORDER BY name COLLATE NOCASE", system)
    result = @[]
    for row in rows:
      result.add(row[0].parseInt)

  proc getCheatName(id: int): string =
    if not initialized: return ""
    let rows = db.getAllRows(sql"SELECT name FROM cheats WHERE id=?", id)
    if rows.len == 0:
      return ""
    return rows[0][0]

  proc extractCheat(id: int, targetFile: string): bool =
    if not initialized: return false
    let rows = db.getAllRows(sql"SELECT path FROM cheats WHERE id=?", id)
    if rows.len == 0:
      return false
    let path = rows[0][0]

    debug "Extracting archive path: ", path, " -> ", targetFile
    if not mzExtractFile(archiveFile, path, targetFile):
      echo "Error extracting cheat"
      removeFile(targetFile)
      return false
    return true


  init()

  result = CheatDb(
    getSystems: getSystems,
    getAllCheats: getAllCheats,
    getCheatName: getCheatName,
    extractCheat: extractCheat,
  )

# ---------------------------------------------------------------------------
# UI namespace
# ---------------------------------------------------------------------------

proc createMinuiUi(): UI =
  var presenterPid: int = 0

  proc killPresenter(signal: cint = SIGKILL, cleanup: bool = true) =
    if presenterPid != 0:
      debug "killing presenter ", $presenterPid, " with ", $signal
      discard posix.kill(Pid(presenterPid), signal)
      if cleanup:
        var status: cint
        discard posix.waitpid(Pid(presenterPid), status, 0)
        presenterPid = 0

  proc message(text: string, timeout: int) =
    killPresenter()
    debug "message: ", text, ", timeout ", $timeout
    if timeout <= 0:
      let p = startProcess(CMD_MINUI_PRESENTER,
                          args = ["--message", text, "--timeout", "-1"],
                          options = {poUsePath})
      presenterPid = p.processID
    else:
      presenterPid = 0
      try:
        discard execProcess(CMD_MINUI_PRESENTER,
                            args = ["--message", text, "--timeout", $timeout],
                            options = {poUsePath})
      except:
        discard

  proc messages(lines: seq[string], timeout: int) =
    killPresenter()
    killPresenter()
    debug "messages: ", $lines.len, " lines"
    let jsonFile = env.cacheDir / "messages.json"
    var items = newJArray()
    for line in lines:
      items.add(%*{"text": line})
    let data = %*{"items": items}
    writeFile(jsonFile, $data)
    let p = startProcess(CMD_MINUI_PRESENTER,
                        args = ["--file", jsonFile, "--disable-auto-sleep",
                                "--timeout", $timeout],
                        options = {poUsePath})
    presenterPid = p.processID

  proc nextMessage() =
    killPresenter(SIGUSR1, false)

  proc confirm(text: string, confirmText: string, cancelText: string): bool =
    killPresenter()
    let args = ["--message", text,
                "--confirm-button", "A",
                "--confirm-text", confirmText,
                "--confirm-show",
                "--cancel-button", "B",
                "--cancel-text", cancelText,
                "--cancel-show",
                "--timeout", "0"]
    let (_, exitCode) = execCmdRaw(CMD_MINUI_PRESENTER, args)
    return exitCode == 0

  proc list(title: string, items: seq[string], selectedIndex: int): int =
    let jsonFile = env.cacheDir / "list.json"
    var minuiItems = newJArray()
    for item in items:
      minuiItems.add(%*{"name": item})
    let data = %*{"items": minuiItems, "selected": selectedIndex}
    writeFile(jsonFile, $data)
    killPresenter()
    let outFile = env.cacheDir / "list_result.json"
    try:
      removeFile(outFile)
    except:
      discard
    let args = ["--file", jsonFile, "--item-key", "items",
                "--title", title, "--write-location", outFile,
                "--write-value", "state"]
    let (_, exitCode) = execCmdRaw(CMD_MINUI_LIST, args)
    if exitCode != 0:
      return -1
    if not fileExists(outFile):
      return -1
    let content = readFile(outFile)
    let resultJson = parseJson(content)
    let selIdx = resultJson["selected"].getInt(-1)
    if selIdx >= 0 and selIdx < items.len:
      return selIdx
    return -1

  result = UI(
    killPresenter: killPresenter,
    message: message,
    messages: messages,
    nextMessage: nextMessage,
    confirm: confirm,
    list: list,
  )

proc createTextUi(): UI =
  var msgLines: seq[string] = @[]
  var msgIdx: int = 0

  proc killPresenter(signal: cint = SIGKILL, cleanup: bool = true) = discard

  proc message(text: string, timeout: int) =
    echo ""
    echo "-".repeat(40)
    echo "MESSAGE: ", text
    echo "-".repeat(40)
    echo ""
    if timeout > 0:
      sleep(timeout * 1000)

  proc messages(lines: seq[string], timeout: int) =
    msgLines = lines
    msgIdx = 0
    message(lines[0], 0)

  proc nextMessage() =
    if msgLines.len > 0:
      msgIdx = (msgIdx + 1) mod msgLines.len
      message(msgLines[msgIdx], 0)

  proc confirm(text: string, confirmText: string, cancelText: string): bool =
    echo ""
    echo "CONFIRM: ", text, " (y/n)"
    stdout.flushFile()
    let input = stdin.readLine()
    return input.toLowerAscii() == "y"

  proc list(title: string, items: seq[string], selectedIndex: int): int =
    echo ""
    echo "=== ", title, " ==="
    let maxNum = items.len
    let numWidth = ($maxNum).len
    for i, item in items:
      let displayNum = i + 1
      let paddedNum = align($displayNum, numWidth)
      let prefix = if i == selectedIndex: "->" & paddedNum & "."
                  else: "  " & paddedNum & "."
      echo prefix, " ", item
    echo "Enter selection (Enter for current, 'q' to cancel):"
    stdout.flushFile()
    let input = stdin.readLine()
    if input == "":
      return selectedIndex
    try:
      let num = parseInt(input)
      if num < 1 or num > items.len:
        return -1
      return num - 1
    except:
      return -1

  result = UI(
    killPresenter: killPresenter,
    message: message,
    messages: messages,
    nextMessage: nextMessage,
    confirm: confirm,
    list: list,
  )

proc createJsonUi(): UI =
  var msgLines: seq[string] = @[]
  var msgIdx: int = 0

  proc killPresenter(signal: cint = SIGKILL, cleanup: bool = true) = discard

  proc message(text: string, timeout: int) =
    echo $(%*{"type": "message", "text": text})
    stdout.flushFile()

  proc messages(lines: seq[string], timeout: int) =
    msgLines = lines
    msgIdx = 0
    if lines.len > 0:
      echo $(%*{"type": "message", "text": lines[0]})
      stdout.flushFile()

  proc nextMessage() =
    if msgLines.len > 0:
      msgIdx = (msgIdx + 1) mod msgLines.len
      echo $(%*{"type": "message", "text": msgLines[msgIdx]})
      stdout.flushFile()

  proc confirm(text: string, confirmText: string, cancelText: string): bool =
    echo $(%*{"type": "confirm", "text": text,
              "confirm": confirmText, "cancel": cancelText})
    stdout.flushFile()
    let line = stdin.readLine()
    return parseJson(line)["choice"].getBool(false)

  proc list(title: string, items: seq[string], selectedIndex: int): int =
    var jItems = newJArray()
    for item in items: jItems.add(%item)
    echo $(%*{"type": "list", "title": title, "items": jItems,
              "selected": selectedIndex})
    stdout.flushFile()
    let line = stdin.readLine()
    return parseJson(line)["choice"].getInt(-1)

  result = UI(
    killPresenter: killPresenter,
    message: message,
    messages: messages,
    nextMessage: nextMessage,
    confirm: confirm,
    list: list,
  )

proc createUi(textui, jsonui: bool): UI =
  if jsonui: createJsonUi()
  elif textui: createTextUi()
  else: createMinuiUi()

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------

proc stripBracketed*(s: string, open, close: char): string =
  ## Remove all instances of open..close (including preceding whitespace).
  result = ""
  var i = 0
  while i < s.len:
    if s[i] == open:
      # Trim trailing whitespace already added to result
      while result.len > 0 and result[^1] == ' ':
        result.setLen(result.len - 1)
      let j = s.find(close, i)
      if j >= 0:
        i = j
      else:
        result.add(s[i])
    else:
      result.add(s[i])
    inc i

proc normalizeTitle*(s: string): string =
  ## Strip file extension, parenthesized text, bracketed text,
  ## then keep only lowercase alphanumerics.
  var r = s
  # Strip extension
  let (dir, name, _) = splitFile(r)
  r = if dir == "": name else: dir / name
  # Remove parenthesized text
  r = r.stripBracketed('(', ')')
  # Remove bracketed text
  r = r.stripBracketed('[', ']')
  # Keep only alphanumerics
  var filtered = ""
  for c in r:
    if c.isAlphaNumeric: filtered.add(c)
  return filtered.toLowerAscii()

proc formatCheatDisplay*(filename: string): string =
  ## Format a cheat filename with [TOOL|REGION] badge prefix.
  ## Recognized tool/region groups are stripped; unrecognized groups stay in the title.
  ## "Castlevania (Action Replay) (USA).cht"  -> "[AR|US] Castlevania"
  ## "Zanac (V2).cht"                         -> "Zanac (V2)"
  ## "Some Game (V2) (USA).cht"               -> "[US] Some Game (V2)"
  let name = splitFile(filename).name

  var tools:   seq[string] = @[]
  var regions: seq[string] = @[]
  var titleBuf = ""

  var i = 0
  while i < name.len:
    let chr = name[i]

    if chr == '(':
      let j = name.find(')', i + 1)
      if j >= 0:
        let raw = name[i + 1 ..< j]
        let g   = raw.toLowerAscii()

        var tool = ""
        if "action replay" in g:   tool = "AR"
        elif "gameshark" in g or "game shark" in g: tool = "GS"
        elif "game genie" in g:    tool = "GG"
        elif "game buster" in g:   tool = "GB"
        elif "code breaker" in g or "codebreaker" in g: tool = "CB"
        elif "xploder" in g:       tool = "XP"

        var region = ""
        if "usa" in g:             region = "US"
        elif "japan" in g:         region = "JP"
        elif "europe" in g:        region = "EU"
        elif "world" in g:         region = "WD"
        elif "australia" in g:     region = "AU"
        elif "brazil" in g:        region = "BR"
        elif "korea" in g:         region = "KR"
        elif "germany" in g:       region = "DE"
        elif "france" in g:        region = "FR"
        elif "spain" in g:         region = "ES"
        elif "italy" in g:         region = "IT"
        elif "canada" in g:        region = "CA"
        elif "mexico" in g:        region = "MX"
        elif "china" in g:         region = "CN"
        elif "taiwan" in g:        region = "TW"
        elif "russia" in g:        region = "RU"
        elif "sweden" in g:        region = "SE"
        elif "denmark" in g:       region = "DK"
        elif "netherlands" in g:   region = "NL"
        elif "scandinavia" in g:   region = "SC"
        elif "uk" in g:            region = "UK"
        elif "norway" in g:        region = "NO"
        elif "portugal" in g:      region = "PT"
        elif "greece" in g:        region = "GR"
        elif "asia" in g:          region = "AS"

        if tool != "":
          tools.add(tool)
        elif region != "":
          regions.add(region)
        else:
          titleBuf = titleBuf.strip(leading = false)
          titleBuf.add(fmt" ({raw})")

        i = j + 1
      else:
        titleBuf.add(chr)
        inc i
    else:
      titleBuf.add(chr)
      inc i

  let title = titleBuf.strip()

  if tools.len > 0 and regions.len > 0:
    return fmt"{title} [{tools[0]}|{regions[0]}]"
  elif tools.len > 0:
    return fmt"{title} [{tools[0]}]"
  elif regions.len > 0:
    return fmt"{title} [{regions[0]}]"
  else:
    return title

proc checkUpdate(): string =
  ## Check GitHub for the latest libretro-database release tag.
  ## Returns the tag string, or "" on failure.
  let url = "https://github.com/libretro/libretro-database/releases/latest"

  let (redirectUrl, exitCode) = execCmdRaw(CMD_CURL,
    ["-ksI", "-w", "%{redirect_url}", "-o", "/dev/null", url])

  var finalUrl = redirectUrl.strip()

  if exitCode != 0:
    echo "Error checking update: ", redirectUrl, " error ", exitCode
    return ""

  if finalUrl == "":
    let (effectiveUrl, exitCode2) = execCmdRaw(CMD_CURL,
      ["-kLs", "-o", "/dev/null", "-w", "%{url_effective}", url])
    if exitCode2 != 0:
      return ""
    finalUrl = effectiveUrl.strip()

  let ti = finalUrl.rfind("tag/")
  if ti >= 0:
    let tag = finalUrl[ti + 4 .. ^1]
    if '/' notin tag and tag.len > 0:
      return tag
  return ""

proc downloadFile(url, outputPath: string): bool =
  ## Download a file from a URL to a local path. Returns true on success.
  debug "Downloading ", url, " to ", outputPath, "..."
  var messages: seq[string] = @[]
  let fileName = extractFilename(url)
  messages.add("Downloading cheat archive " & fileName)
  let maxMb = 170
  for i in 1 ..< maxMb:
    messages.add("Downloading cheat archive " & fileName &
                 ". Progress: " & $i & " MB of about 170 MB")
  ui.messages(messages, -1)

  let tmpPath = outputPath & ".tmp"
  try:
    removeFile(tmpPath)
  except:
    discard
  try:
    removeFile(outputPath)
  except:
    discard

  let curlProc = startProcess(CMD_CURL, args = ["-ksL", url],
                              options = {poUsePath})
  let pipe = curlProc.outputStream

  let fd = open(tmpPath, fmWrite)

  var bytes: int64 = 0
  var lastMb: int64 = 0
  var buf: array[65536, byte]

  while true:
    let n = pipe.readData(addr buf[0], buf.len)
    if n <= 0:
      break
    discard fd.writeBuffer(addr buf[0], n)
    bytes += n.int64
    let mb = bytes div 1048576
    if mb != lastMb:
      lastMb = mb
      debug "Downloaded ", $mb, " MB so far..."
      if mb < maxMb:
        ui.nextMessage()
      elif mb == maxMb:
        ui.message("Downloading cheat archive " & fileName &
                  ". Progress: " & $maxMb & "+ MB", -1)

  fd.close()

  let exitCode = curlProc.waitForExit()
  curlProc.close()

  if exitCode != 0:
    debug "Download failed"
    try:
      removeFile(tmpPath)
    except:
      discard
    ui.message("Download Failed!", 2)
    return false

  if not fileExists(tmpPath) or getFileSize(tmpPath) == 0:
    debug "Download failed"
    try:
      removeFile(tmpPath)
    except:
      discard
    ui.message("Download Failed!", 2)
    return false

  moveFile(tmpPath, outputPath)

  let size = getFileSize(outputPath)
  let mb = size div 1048576
  debug "Download complete. Final size: ", $mb, " MB"
  ui.message("Download Complete! " & $mb & " MB", 1)
  return true

# ---------------------------------------------------------------------------
# Browser Logic
# ---------------------------------------------------------------------------

proc extractTag*(dirName: string): string =
  ## Extract the system tag from a ROM directory name.
  if dirName.len > 0 and dirName.allCharsInSet({'A'..'Z', '0'..'9'}):
    return dirName
  if dirName.endsWith(')'):
    let p = dirName.rfind('(')
    if p >= 0:
      return dirName[p + 1 .. ^2]
  return ""

proc hasGameFiles*(dirPath: string): bool =
  for path in walkDirRec(dirPath):
    let rel = path[dirPath.len .. ^1]
    if "/." in rel or rel.startsWith("."):
      continue
    let ext = splitFile(path).ext.toLowerAscii()
    if ext notin EXCLUDED_EXTS:
      return true
  return false

proc browserListDirs*(rootDir: string): seq[DirEntry] =
  ## List ROM subdirectories that have a parseable tag and contain game files.
  result = @[]
  var entries: seq[string] = @[]
  for kind, path in walkDir(rootDir):
    if kind == pcDir:
      entries.add(path)
  entries.sort(proc(a, b: string): int = cmpIgnoreCase(extractFilename(a),
               extractFilename(b)))
  for d in entries:
    let name = extractFilename(d)
    if name.startsWith("."): continue
    if extractTag(name) == "": continue
    if not hasGameFiles(d): continue
    result.add(DirEntry(name: name, path: d))

proc browserListGames*(dirPath: string): seq[DirEntry] =
  ## List game files within a ROM directory.
  ## Handles plain files, .m3u playlists inside subdirectories,
  ## and subdirectories containing valid game files.
  result = @[]
  var entries: seq[string] = @[]
  for kind, path in walkDir(dirPath):
    entries.add(path)
  entries.sort(proc(a, b: string): int = cmpIgnoreCase(extractFilename(a),
               extractFilename(b)))

  for f in entries:
    let name = extractFilename(f)
    if name.startsWith("."):
      continue

    let info = getFileInfo(f)
    if info.kind == pcFile:
      let ext = splitFile(name).ext.toLowerAscii()
      if ext notin EXCLUDED_EXTS:
        result.add(DirEntry(name: name, path: f))
    elif info.kind == pcDir:
      # Check for .m3u inside subdir
      var m3uFiles: seq[string] = @[]
      for subKind, subPath in walkDir(f):
        if subKind == pcFile and subPath.toLowerAscii().endsWith(".m3u"):
          m3uFiles.add(subPath)

      if m3uFiles.len > 0:
        let m3uPath = m3uFiles[0]
        let m3uName = extractFilename(m3uPath)
        result.add(DirEntry(name: m3uName, path: m3uPath))
      else:
        # Check for other valid game files inside
        var validGameFound = false
        for subKind, subPath in walkDir(f):
          if subKind == pcFile:
            let sname = extractFilename(subPath)
            if sname.startsWith("."):
              continue
            let sext = splitFile(sname).ext.toLowerAscii()
            if sext notin EXCLUDED_EXTS:
              validGameFound = true
              break

        if validGameFound:
          result.add(DirEntry(name: name, path: f))

proc isCheatZip*(path: string): bool =
  try:
    let entries = mzListArchive(path)
    for e in entries:
      let ci = e.find("cht/")
      if ci >= 0 and e.find('/', ci + 4) >= 0:
        return true
  except:
    discard
  return false

proc findLocalCheatZip*(sdcardPath: string): string =
  if sdcardPath == "":
    return ""
  try:
    for kind, path in walkDir(sdcardPath):
      if kind == pcFile and path.toLowerAscii().endsWith(".zip"):
        if isCheatZip(path):
          return path
  except:
    discard
  return ""

proc cheatSortKey(display: string): string =
  let i = display.rfind(" [")
  if i >= 0: display[0 ..< i] else: display

proc ensureDirs() =
  createDir(env.cacheDir)
  createDir(env.cheatDir)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() =
  ensureDirs()
  stateStore = createStateStore(env.cacheDir / "state.json")
  stateStore.load()

  # Pre-populate known tag→system mappings (INSERT OR IGNORE semantics)
  let knownMappings = [
    (@["GBA", "MGBA"],           "Nintendo - Game Boy Advance"),
    (@["GBC"],                   "Nintendo - Game Boy Color"),
    (@["GB", "GB0", "SGB"],      "Nintendo - Game Boy"),
    (@["FC", "NES"],             "Nintendo - Nintendo Entertainment System"),
    (@["SFC", "SNES", "SUPA"],   "Nintendo - Super Nintendo Entertainment System"),
    (@["N64"],                   "Nintendo - Nintendo 64"),
    (@["NDS", "NDS2"],           "Nintendo - Nintendo DS"),
    (@["FDS"],                   "Nintendo - Family Computer Disk System"),
    (@["BSX"],                   "Nintendo - Satellaview"),
    (@["MD", "GEN", "GENESIS"],  "Sega - Mega Drive - Genesis"),
    (@["GG"],                    "Sega - Game Gear"),
    (@["MS", "SMS", "SMSGG"],    "Sega - Master System - Mark III"),
    (@["32X"],                   "Sega - 32X"),
    (@["SS", "SAT"],             "Sega - Saturn"),
    (@["DC"],                    "Sega - Dreamcast"),
    (@["MCD", "SCD", "SEGACD"],  "Sega - Mega-CD - Sega CD"),
    (@["PS", "PSX", "PS1"],      "Sony - PlayStation"),
    (@["PSP"],                   "Sony - PlayStation Portable"),
    (@["PCE", "TG16"],           "NEC - PC Engine - TurboGrafx 16"),
    (@["PCECD"],                 "NEC - PC Engine CD - TurboGrafx-CD"),
    (@["SGFX"],                  "NEC - PC Engine SuperGrafx"),
    (@["ATARI", "A26", "A2600", "ATARI2600"], "Atari - 2600"),
    (@["LYNX"],                  "Atari - Lynx"),
    (@["A7800", "ATARI7800"],    "Atari - 7800"),
    (@["A5200"],                 "Atari - 5200"),
    (@["A800"],                  "Atari - 8-bit Family"),
    (@["JAGUAR"],                "Atari - Jaguar"),
    (@["ARCADE", "FBN", "FBNEO", "MAME", "MAME2003PLUS", "CPS1", "CPS2", "CPS3", "NEOGEO", "PGM"], "FBNeo - Arcade Games"),
    (@["GX4000"],                "Amstrad - GX4000"),
    (@["MSX", "MSX2"],           "Microsoft - MSX - MSX2 - MSX2P - MSX Turbo R"),
    (@["CV", "COLECO"],          "Coleco - ColecoVision"),
    (@["INTV"],                  "Mattel - Intellivision"),
    (@["DOS"],                   "DOS"),
    (@["PRBOOM"],                "PrBoom"),
    (@["ZX"],                    "Sinclair - ZX Spectrum +3"),
    (@["TIC80"],                 "TIC-80"),
  ]
  for (tags, s) in knownMappings:
    for t in tags:
      if stateStore.getSystem(t) == "":
        stateStore.setSystem(t, s)

  # Shared context
  var
    latestVersion = ""
    currentVersion = ""
    isFirstInstall = false
    dirPath = ""
    dirName = ""
    tag = ""
    gameName = ""
    gameBase = ""
    mappedSystem = ""
    allIds: seq[int] = @[]
    allMatches: seq[int] = @[]
    tier3: seq[int] = @[]
    selectedCheatId = 0

  var exitCode = 0
  var state = FIND_LOCAL_DB

  while state != EXIT:
    case state

    of FIND_LOCAL_DB:
      let localZip = findLocalCheatZip(getEnv("SDCARD_PATH"))
      if localZip != "":
        let dbFile = env.cacheDir / "cheats.zip"
        copyFile(localZip, dbFile)
        stateStore.setCheatDbVersion("local", getFileSize(dbFile))
        state = INIT_DB
      else:
        state = CHECK_UPDATE

    of CHECK_UPDATE:
      if not offlineMode:
        ui.message("Checking for updates...")
        latestVersion = checkUpdate()
      currentVersion = stateStore.getCheatDbVersion()
      let dbFile = env.cacheDir / "cheats.zip"
      if currentVersion != "" and stateStore.isDbFileMissing(dbFile):
        currentVersion = ""
        stateStore.setCheatDbVersion("")
      if currentVersion == "" and latestVersion == "":
        state = INIT_DB
      elif currentVersion == "":
        state = CONFIRM_DOWNLOAD
      elif latestVersion != "" and latestVersion != currentVersion:
        state = CONFIRM_UPDATE
      else:
        state = INIT_DB

    of CONFIRM_DOWNLOAD:
      if ui.confirm("No downloaded database. Download " & latestVersion &
                    " now?", "Download", "Exit"):
        isFirstInstall = true
        state = DOWNLOAD
      else:
        state = EXIT

    of CONFIRM_UPDATE:
      currentVersion = stateStore.getCheatDbVersion()
      if ui.confirm("Database update available: " & latestVersion &
                    ". Download?", "Download",
                    "Use current " & currentVersion):
        state = DOWNLOAD
      else:
        state = INIT_DB

    of DOWNLOAD:
      let url = "https://github.com/libretro/libretro-database/archive/refs/tags/" &
                latestVersion & ".zip"
      let dbFile = env.cacheDir / "cheats.zip"
      if downloadFile(url, dbFile):
        stateStore.setCheatDbVersion(latestVersion, getFileSize(dbFile))
        if not isFirstInstall:
          ui.message("Update Complete!", 2)
        state = INIT_DB
      elif isFirstInstall:
        ui.message("Download Failed! Exiting.", 4)
        exitCode = 1
        state = EXIT
      else:
        state = INIT_DB

    of INIT_DB:
      let dbFile = env.cacheDir / "cheats.zip"
      if not fileExists(dbFile):
        ui.message("No cheat database available. Exiting.", 3)
        exitCode = 1
        state = EXIT
        continue
      ui.message("Checking cheat archive...")
      cheatDb = createCheatDb(dbFile)
      state = SELECT_GAME_FOLDER

    of SELECT_GAME_FOLDER:
      let dirs = browserListDirs(env.romDir)
      if dirs.len == 0:
        ui.message("No supported ROM folders found. Check that your ROM folders use the 'System (TAG)' naming convention.", 5)
        state = EXIT
        continue
      var dirItems: seq[string] = @[]
      let lastFolder = stateStore.getLastFolder()
      var selectedIdx = 0
      for i, d in dirs:
        if d.name == lastFolder:
          selectedIdx = i
        dirItems.add(d.name)

      let idx = ui.list("Select Game Folder", dirItems, selectedIdx)
      if idx < 0:
        state = EXIT
        continue

      let selectedDir = dirs[idx]
      dirPath = selectedDir.path
      dirName = selectedDir.name
      stateStore.setLastFolder(dirName)
      tag = extractTag(dirName)
      if tag == "":
        ui.message("Could not detect tag for '" & dirName & "'", 2)
        state = SELECT_GAME_FOLDER
      else:
        mappedSystem = stateStore.getSystem(tag)
        state = SELECT_GAME

    of SELECT_GAME:
      let games = browserListGames(dirPath)
      if games.len == 0:
        ui.message("No games found in " & dirName, 2)
        state = SELECT_GAME_FOLDER
        continue

      var gameItems: seq[string] = @[]
      for g in games:
        gameItems.add(g.name)

      # Find index of last selected game for this tag
      var initialIdx = 0
      let lastGame = stateStore.getLastGame(tag)
      if lastGame != "":
        for i, g in games:
          if g.name == lastGame:
            initialIdx = i
            break

      let idx = ui.list("Select Game (" & tag & ")", gameItems, initialIdx)
      if idx < 0:
        state = SELECT_GAME_FOLDER
        continue

      let selectedGame = games[idx]
      gameName = selectedGame.name
      gameBase = splitFile(gameName).name

      # Remember this selection
      stateStore.setLastGame(tag, gameName)

      mappedSystem = stateStore.getSystem(tag)
      if mappedSystem == "":
        state = MAP_SYSTEM
      else:
        state = FIND_CHEATS

    of MAP_SYSTEM:
      let systems = cheatDb.getSystems()
      if systems.len == 0:
        ui.message("No systems found in database!", 2)
        state = SELECT_GAME_FOLDER
        continue

      var selectedIdx = 0
      var sysItems: seq[string] = @[]
      for i, s in systems:
        if s == mappedSystem:
          selectedIdx = i
        sysItems.add(s)

      let idx = ui.list(tag & ": Select Cheat Folder", sysItems,
                               selectedIdx)
      if idx < 0:
        state = SELECT_GAME
        continue

      mappedSystem = systems[idx]
      stateStore.setSystem(tag, mappedSystem)
      state = FIND_CHEATS

    of FIND_CHEATS:
      ui.message("Searching cheats for " & mappedSystem & "...")
      allIds = cheatDb.getAllCheats(mappedSystem)
      var tier1: seq[int] = @[]
      var tier2: seq[int] = @[]
      tier3 = @[]

      var gameTitle = gameBase
      let pi = gameBase.find('(')
      if pi >= 0:
        gameTitle = gameBase[0 ..< pi].strip()
      else:
        gameTitle = gameBase

      let lowGbase = gameBase.toLowerAscii()
      let normGbase = normalizeTitle(gameBase)

      for cid in allIds:
        let cname = cheatDb.getCheatName(cid)
        let lowCname = cname.toLowerAscii()
        let normCname = normalizeTitle(cname)

        if lowCname.startsWith(lowGbase):
          tier1.add(cid)
        elif normGbase.startsWith(normCname) or normCname.startsWith(normGbase):
          tier2.add(cid)
        else:
          tier3.add(cid)

      debug "Tier 1: ", tier1.join(", ")
      debug "Tier 2: ", tier2.join(", ")
      allMatches = tier1 & tier2
      if allMatches.len == 0:
        allMatches = tier3
      if allMatches.len == 0:
        ui.message("No cheats found for this system.", 2)
        state = SELECT_GAME
      else:
        state = SELECT_CHEAT_FROM_MATCHED

    of SELECT_CHEAT_FROM_MATCHED:
      var pairs: seq[(string, int)] = @[]
      for cid in allMatches:
        pairs.add((formatCheatDisplay(cheatDb.getCheatName(cid)), cid))
      pairs.sort(proc(a, b: (string, int)): int =
        let c = cmpIgnoreCase(cheatSortKey(a[0]), cheatSortKey(b[0]))
        if c != 0: c else: cmpIgnoreCase(a[0], b[0]))
      var cheatItems: seq[string] = @[]
      var sortedMatchIds: seq[int] = @[]
      for (name, cid) in pairs:
        cheatItems.add(name)
        sortedMatchIds.add(cid)

      var showAllIdx = -1
      if tier3.len > 0 and allMatches.len != allIds.len:
        showAllIdx = cheatItems.len()
        cheatItems.add("Show All Cheats")

      let changeFolderIdx = cheatItems.len()
      cheatItems.add("Change cheat folder")

      let idx = ui.list("Select Cheat for " & gameBase, cheatItems)

      if idx == showAllIdx and showAllIdx >= 0:
        state = SELECT_CHEAT_FROM_ALL
      elif idx == changeFolderIdx:
        state = MAP_SYSTEM
      elif idx < 0:
        state = SELECT_GAME
      else:
        selectedCheatId = sortedMatchIds[idx]
        state = INSTALL_CHEAT

    of SELECT_CHEAT_FROM_ALL:
      var pairs: seq[(string, int)] = @[]
      for cid in allIds:
        pairs.add((formatCheatDisplay(cheatDb.getCheatName(cid)), cid))
      pairs.sort(proc(a, b: (string, int)): int =
        let c = cmpIgnoreCase(cheatSortKey(a[0]), cheatSortKey(b[0]))
        if c != 0: c else: cmpIgnoreCase(a[0], b[0]))
      var cheatItems: seq[string] = @[]
      var sortedAllIds: seq[int] = @[]
      for (name, cid) in pairs:
        cheatItems.add(name)
        sortedAllIds.add(cid)

      let changeFolderIdx = cheatItems.len()
      cheatItems.add("Change cheat folder")

      # Start cursor at the first matched item in sorted order
      var initialIdx = 0
      for i, cid in sortedAllIds:
        if cid in allMatches:
          initialIdx = i
          break

      let idx = ui.list("Select Cheat for " & gameBase, cheatItems, initialIdx)

      if idx == changeFolderIdx:
        state = MAP_SYSTEM
      elif idx < 0:
        if allMatches.len > 0:
          state = SELECT_CHEAT_FROM_MATCHED
        else:
          state = SELECT_GAME
      else:
        selectedCheatId = sortedAllIds[idx]
        state = INSTALL_CHEAT

    of INSTALL_CHEAT:
      var targetDir: string
      if env.cheatDir == env.romDir:
        targetDir = dirPath
      else:
        targetDir = env.cheatDir / tag
        createDir(targetDir)

      let targetFile = targetDir / (gameName & ".cht")
      ui.message("Extracting cheat for " & gameBase &
                ", may take a minute...", -1)
      if cheatDb.extractCheat(selectedCheatId, targetFile):
        ui.message("Installed to " & targetFile, 2)
      else:
        ui.message("Installation Failed!", 2)
      state = SELECT_GAME

    of EXIT:
      ui.killPresenter()
      quit(exitCode)

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

when isMainModule:
  # Check arguments
  var textui = false
  var jsonuiMode = false
  for arg in commandLineParams():
    if arg == "textui":
      textui = true
    elif arg == "jsonui":
      jsonuiMode = true
    elif arg == "debug":
      debugMode = true
    elif arg == "offline":
      offlineMode = true

  # Check for required environment variables
  env.romDir = getEnv("ROM_DIR")
  env.cacheDir = getEnv("CACHE_DIR")
  env.cheatDir = getEnv("CHEAT_DIR")

  var missing: seq[string] = @[]
  if env.romDir == "":
    missing.add("ROM_DIR")
  if env.cacheDir == "":
    missing.add("CACHE_DIR")
  if env.cheatDir == "":
    missing.add("CHEAT_DIR")

  if missing.len > 0:
    echo "Error: Missing required environment variables: ", missing.join(", ")
    quit(1)

  debug "ROM_DIR: ", env.romDir
  debug "CACHE_DIR: ", env.cacheDir
  debug "CHEAT_DIR: ", env.cheatDir

  ui = createUi(textui, jsonuiMode)

  main()
