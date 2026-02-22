# **Cheat Manager \- Design Document**

## **1\. Project Overview**

**Goal:** Create a standalone application for an embedded Linux emulation device to manage game cheats. **Core Function:** Download a cheat database, browse local ROMs, match specific games to the cheat archive (interactively mapping systems if needed), and install cheats. **Target Environment:** Embedded Linux (Headless or Framebuffer). **Constraint:** Folder names can be either `TAG` (e.g., `GBA`) or `Name (TAG)` (e.g., `Nintendo (GBA)`).

## **2\. Terminology**

* **$ROM\_DIR:** The root directory containing game folders (e.g., `/mnt/SDCARD/Roms`).
* **$CACHE\_DIR:** The directory used for storing application state and cached downloads (e.g., `/mnt/SDCARD/App/CheatManager/cache`).
* **$CHEAT\_DIR:** The root directory where cheats should be installed.
  * *Configuration A (Side-by-side):* `$CHEAT_DIR` is set to the same path as `$ROM_DIR`. Cheats are placed next to the game files within the source folder structure.
  * *Configuration B (Centralized):* `$CHEAT_DIR` is set to a separate path (e.g., `/mnt/SDCARD/Cheats`). Cheats are organized in subfolders named **strictly after the system TAG** (e.g., `$CHEAT_DIR/PS/` for PlayStation games).
* **TAG:** The identifier for a specific emulator core (e.g., `GBA`, `FC`, `N64`, `3DO`).
  * *Format:* Uppercase alphanumeric (can start with a number).
* **Cheat Archive:** A remote `.tar.gz` file containing cheats, downloaded from GitHub to `$CACHE_DIR/cheats.tar.gz`.
  * *Source:* The Source Code archive (`archive/refs/tags/<TAG>.tar.gz`).
  * *Structure:* A versioned root folder (e.g., `libretro-database-1.22.1/`) containing a `cht/` folder, which contains system folders.
* **Mapping:** The persistent link between a short `TAG` (e.g., `N64`) and a **Normalized Archive System Name** stored in `state.json`.

## **3\. Architecture & Modules**

The application consists of four distinct modules to keep the UI decoupled from the logic.

### **A. Network Module (The Fetcher)**

* **Responsibility:** Handling the cheat database update via GitHub Releases.
* **Logic:**
  1. **Check Local:** Read `state.json` in `$CACHE_DIR` to get the current installed `dbVersion` (e.g., `v1.22.1`).
  2. **Resolve Latest:**
     * Perform an HTTP `HEAD` request (`curl -ksI`) to `https://github.com/libretro/libretro-database/releases/latest`.
     * Capture the redirect URL from the response (via `-w "%{redirect_url}"`).
     * Regex-extract the tag from the `Location` URL: match `tag/([^/]+)$`.
     * *Example:* `https://github.com/libretro/libretro-database/releases/tag/v1.22.1` \-\> Extract Tag `v1.22.1`.
  3. **Comparison:**
     * **If `state.json` or `dbVersion` missing:** Treat as "New Download".
     * **If exists:** Compare `local.dbVersion` vs `remote.tag`.
     * **Update Detected:** If tags differ, **do not auto-download**.
     * **Action:** Prompt the user via the UI Module to confirm the update (e.g., "Update available: v1.21.0 \-\> v1.22.1").
     * **On failed update check:** If no remote tag could be resolved, the app continues with the local DB if one is available.
  4. **Download:**
     * If confirmed, construct the download URL: `https://github.com/libretro/libretro-database/archive/refs/tags/<TAG>.tar.gz`.
     * **Atomic write:** Downloads to a `.tmp` file, then renames to the final path on success. No HTTP `Range` resume is implemented.
     * **Progress Display:** Pre-generates ~170 messages ("Downloading … N MB of about 170MB"). Reads the stream in 65 KB chunks; each time the MB count increments, calls `UI::next_message` to advance to the next pre-generated message.
     * **On Success:** Update `dbVersion` in `state.json`.

### **B. File Browser Module (The Navigator)**

* **Responsibility:** Navigating the file system and selecting games (Replaces the full Indexer).
* **Logic:**
  1. **Start:** List contents of `$ROM_DIR`.
  2. **Navigation:** Allow user to enter directories.
     * *Optimization:* Cache directory contents in memory while navigating, but do not scan recursively.
  3. **Context Extraction (Tag Detection):**
     * **Format A (Pure TAG):** Directory name consists entirely of uppercase letters and digits (regex `^[A-Z0-9]+$`).
     * **Format B (Extracted):** Otherwise, extract the last parenthesized token: regex `\(([^)]+)\)$`.
     * *Example:* `/Roms/GBA` \-\> Tag `GBA`.
     * *Example:* `/Roms/Panasonic (3DO)` \-\> Tag `3DO`.
  4. **Game Entry Detection (Current Directory Only):**
     * **File Filter:** Ignore files starting with `.` and documentation/metadata/image extensions: `.txt`, `.md`, `.xml`, `.db`, `.pdf`, `.cht`, `.png`, `.jpg`, `.jpeg`.
     * **Grouping:** Apply the "Basename" grouping logic to the current view (e.g., group `.bin` and `.cue` as one entry).
     * **Subdirectory handling:** If a subdirectory is found, look inside it for `.m3u` playlist files. If one or more `.m3u` files exist, use the first `.m3u` file as the game entry (name and path). If no `.m3u` is found but other valid game files exist inside, the subdirectory itself is shown as the game entry.

### **C. Matcher Module (The Brains)**

* **Responsibility:** Finding the correct cheat file in the archive and managing Tag-to-System mappings.

#### **Database / Index**

After download, the archive is parsed with `tar tzf` and indexed into a SQLite database (`cheats.db`, stored alongside the archive). Tables:

| Table | Columns |
|---|---|
| `metadata` | `key TEXT PRIMARY KEY, value TEXT` |
| `systems` | `name TEXT PRIMARY KEY` |
| `cheats` | `id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, path TEXT, system TEXT` |

The index is rebuilt from scratch only when `metadata.archive_file` does not match the current archive path (or the cheats table is empty). This is the cache-invalidation strategy: the stored archive filename acts as a cache key.

* **Logic:**
  1. Receive selected ROM **Basename** and the current `TAG`.
  2. **Resolve System Mapping:**
     * Check the `tags` object in `state.json`.
     * **Case A (Known Tag):** Retrieve the mapped "Normalized System Name".
     * **Case B (Unknown Tag \- First Time Setup):**
       * Query `CheatDb::getSystems` for all systems in the index.
       * **System name normalization:** Strip trailing parenthesized text (e.g., `Sony - PlayStation (beetle core)` → `Sony - PlayStation`) before storing in the index.
       * **Prompt User:** "Select cheat folder for \<TAG\>" showing the system list. Add a **"Cancel"** option.
       * **Save:** Update the `tags` object in `state.json` ONLY if a valid system is selected. If Cancelled, leave undefined.
  3. **Search Archive:**
     * If System Name is undefined (cancelled mapping), return empty results.
     * Query all cheats where `system = <Normalized System Name>`.
  4. **Matching Strategy (Case-Insensitive):**
     * **Tier 1 (Exact Prefix):**
       * Match if the cheat filename starts with the full ROM basename (case-insensitive `string first` starting at position 0).
       * *Ex:* ROM basename `Fire Emblem (USA)` — cheat `Fire Emblem (USA) (CodeBreaker).cht` matches.
     * **Tier 2 (Normalized Prefix):**
       * Normalize both the ROM basename and the cheat name: strip file extension, strip `(...)` and `[...]`, remove all non-alphanumeric characters, lowercase.
       * Match if either normalized string is a prefix of the other (bidirectional `string first` check at position 0).
       * *Ex:* ROM `Mega Man Zero 2 (USA)` → normalized `megamanzero2`; cheat `Mega Man Zero 2 (USA, Europe) (Code Breaker)` → `megamanzero2usaeuropecodebreaker` — Tier 2 match.
     * **Tier 3 (All remaining):**
       * All cheats not in Tier 1 or Tier 2. Shown only when both Tier 1 and Tier 2 are empty.
     * **Show All Cheats:** A "Show All Cheats" option is offered when the displayed list is a filtered subset (i.e., Tier 3 cheats exist but are hidden). Selecting it shows every cheat for the system regardless of tier.

### **D. UI Module (The Interface)**

* **Responsibility:** Display data and capture input.
* **Abstracted Methods:**
  * `message(text, timeout)` — display a message.
    * `timeout = 0`: blocking (waits for user dismiss).
    * `timeout = -1`: async / non-blocking (presenter runs in background).
    * `timeout = N` (positive integer): auto-dismiss after N seconds.
  * `messages(lines)` — pre-load multiple sequential messages. Writes a `messages.json` file and launches the presenter with `--file`. Each call to `next_message` (via SIGUSR1) advances to the next message.
  * `list(title, items, selected_index)` — display a selectable list and return the chosen item's ID.
    * `items` are dicts of the form `{id "..." text "..."}`.
    * Returns the selected item's `id`, or empty string on cancel.
  * `confirm(text, confirm-text, cancel-text)` — prompt for confirmation. Returns `1` if confirmed, `0` otherwise.

## **4\. Configuration & Data Structures**

### **A. State File (`state.json`)**

Located in `$CACHE_DIR`. Stores both the version tracking and the dynamic system mappings.

*Structure:*

```json
{
  "dbVersion": "v1.22.1",
  "lastFolder": "GBA",
  "tags": {
    "FC": "Nintendo - Nintendo Entertainment System",
    "PS": "Sony - PlayStation"
  },
  "lastGame": {
    "GBA": "Fire Emblem (USA).gba"
  }
}
```

Fields:

| Field | Type | Description |
|---|---|---|
| `dbVersion` | string | Tag of the installed cheat archive (e.g. `v1.22.1`). Empty if none. |
| `lastFolder` | string | Name of the last ROM folder the user navigated to. |
| `tags` | object | Maps each TAG (e.g. `GBA`) to a normalized system name from the cheat DB. |
| `lastGame` | object | Maps each TAG to the last game name selected in that folder. |

### **B. Directory Structure**

```
/mnt/SDCARD/App/CheatManager/
    ├── executable
    └── cache/               # $CACHE_DIR
        ├── state.json       # configuration and state
        ├── cheats.tar.gz    # cached cheat archive
        └── cheats.db        # SQLite index of the archive
```

## **5\. Detailed Workflow**

### **Phase 1: Initialization & Update**

1. **Start:** App launches.
2. **Network Check:**
   * Perform `curl -ksI` HEAD request to `https://github.com/libretro/libretro-database/releases/latest`.
   * Extract tag from the redirect URL (e.g., `.../tag/v1.23.0`).
   * On failure, continue with local DB if available.
3. **Compare Versions:**
   * Read `dbVersion` from `state.json`.
   * **If Different (or no local version):**
     * Action: `confirm("Update available: v1.22.1 -> v1.23.0. Download?", "Download", "Use current")`
     * **If Yes:** Download `.../archive/refs/tags/v1.23.0.tar.gz`. Update `dbVersion` in `state.json` on success.
     * **If No:** Skip download, proceed with existing local DB.

### **Phase 2: Game Navigation (Browser)**

1. **Start:** Display contents of `$ROM_DIR`. Restore last selected folder via `lastFolder` state.
2. **Interact:** User selects a folder (e.g., `GBA` or `Sony PlayStation (PS)`).
3. **Context:**
   * App checks if folder name matches `^[A-Z0-9]+$` \-\> Tag \= folder name (e.g., `GBA`).
   * Otherwise extracts last `(TAG)` \-\> e.g., `Sony PlayStation (PS)` \-\> Tag \= `PS`.
4. **List:** App lists games in the folder. Restore last selected game via `lastGame[TAG]` state.
   * Subdirectories are checked for `.m3u` playlists. If found, the `.m3u` is shown as the game entry.
5. **Select:** User selects a game (e.g., `Gran Turismo (USA).bin`).

### **Phase 3: System Mapping (Just-in-Time)**

1. **Lookup & Validate:**
   * Look for `TAG` (e.g., `PS`) in `state.json` \-\> `tags`.
2. **If Mapping Missing:**
   * **Query Index:** Get all system names from `cheats.db`. Names have already had trailing `(...)` stripped during indexing.
   * **UI Prompt:**
     * **Title:** "Select cheat folder for \<PS\>" (uses TAG).
     * **Items:**
       * `[ ] Sega - Saturn`
       * `[ ] Sony - PlayStation`
       * `[ ] Cancel`
   * **User Action:**
     * **Selects System:** Write/Update `tags` in `state.json`.
     * **Selects Cancel:** Do not update `state.json`. Mapping remains undefined.
3. **Proceed:** Use the confirmed "Normalized Name" for searching. If undefined (Cancelled), go back to game selection.

### **Phase 4: Cheat Finding**

1. **Search:**
   * If Normalized Name is undefined (Mapping Cancelled): Return to game selection.
   * Else: Query `cheats.db` for all cheats with `system = <Normalized Name>`.
2. **Rank & Display:**
   * **Tier 1:** Cheat name starts with the ROM basename (case-insensitive prefix match).
   * **Tier 2:** Normalized ROM basename and normalized cheat name are bidirectional prefix matches.
   * **Tier 3 (fallback):** All remaining cheats — shown only when both Tier 1 and Tier 2 are empty.
   * **Show All Cheats:** Offered as a menu option when Tier 3 cheats exist but are currently hidden. Selecting it shows all cheats for the system.
   * **Title:** "Select Cheat for \[game\_base\]"
   * **Items:**
     * `[ ] Gran Turismo (USA).cht` (Tier 1\)
     * `[ ] Gran Turismo (USA, Europe).cht` (Tier 2\)
     * `[ ] Show All Cheats`  (if Tier 3 exists)
     * `[ ] Change cheat folder`
     * `[ ] Cancel`
   * **User Action:**
     * **Selects Cheat:** Go to Phase 5\.
     * **Selects Show All Cheats:** Re-display list with all cheats for the system.
     * **Selects Change cheat folder:** Go to Phase 3 (System Mapping / MAP\_SYSTEM state).
     * **Selects Cancel:** **Return to Phase 2 (File Browser).**

### **Phase 5: Extraction & Installation**

1. **Target Path:** Construct as `<target_dir>/<game_name>.cht`.
   * *Side-by-side:* `target_dir = dir_path` (same folder as the ROM).
   * *Centralized:* `target_dir = $CHEAT_DIR/<TAG>`.
   * *Note:* Output always ends in `.cht` regardless of the source file's extension.
2. **Extract & Write:** Run `tar xzf <archive> -O <path_in_archive> > <target_file>`.
3. **Confirmation:** UI: "Installed to \<target\_file\>"
4. **Loop:** Return to Phase 2 (Game Selection within the same folder).

## **6\. State Machine**

The application is driven by an explicit state machine. Transitions:

| From state | Event / condition | Next state |
|---|---|---|
| `CHECK_UPDATE` | No local version AND no remote version | `EXIT` |
| `CHECK_UPDATE` | No local version (remote available) | `CONFIRM_DOWNLOAD` |
| `CHECK_UPDATE` | Local version differs from remote | `CONFIRM_UPDATE` |
| `CHECK_UPDATE` | Versions match (or remote unavailable, local present) | `INIT_DB` |
| `CONFIRM_DOWNLOAD` | User confirms | `DOWNLOAD` |
| `CONFIRM_DOWNLOAD` | User cancels | `EXIT` |
| `CONFIRM_UPDATE` | User confirms | `DOWNLOAD` |
| `CONFIRM_UPDATE` | User cancels | `INIT_DB` |
| `DOWNLOAD` | Success | `INIT_DB` |
| `DOWNLOAD` | Failure (first install) | `EXIT` |
| `DOWNLOAD` | Failure (update) | `INIT_DB` (use existing DB) |
| `INIT_DB` | Always | `SELECT_GAME_FOLDER` |
| `SELECT_GAME_FOLDER` | User selects folder | `SELECT_GAME` |
| `SELECT_GAME_FOLDER` | User cancels | `EXIT` |
| `SELECT_GAME` | User selects game, system already mapped | `FIND_CHEATS` |
| `SELECT_GAME` | User selects game, system not mapped | `MAP_SYSTEM` |
| `SELECT_GAME` | User cancels | `SELECT_GAME_FOLDER` |
| `MAP_SYSTEM` | User selects system | `FIND_CHEATS` |
| `MAP_SYSTEM` | User cancels | `SELECT_GAME` |
| `FIND_CHEATS` | Cheats found | `SELECT_CHEAT` |
| `FIND_CHEATS` | No cheats found | `SELECT_GAME` |
| `SELECT_CHEAT` | User selects a cheat | `INSTALL` |
| `SELECT_CHEAT` | User selects "Change cheat folder" | `MAP_SYSTEM` |
| `SELECT_CHEAT` | User cancels | `SELECT_GAME` |
| `INSTALL` | Always (success or failure) | `SELECT_GAME` |

## **7\. Implementation Considerations**

* **SQLite Cache Invalidation:** The `metadata` table stores the archive file path under key `archive_file`. On startup, if this value matches the current archive path and the `cheats` table is non-empty, the index is reused as-is. Otherwise the tables are cleared and the archive is re-indexed via `tar tzf`.
* **No Resume Support:** Downloads use an atomic write pattern: data is streamed to `<output>.tmp`, then renamed to the final path on success. If the download fails, the `.tmp` file is deleted. There is no HTTP Range-based resume.
* **UI State:** The app remembers the last selected ROM folder (`lastFolder`) and the last selected game per TAG (`lastGame`), restoring the cursor position when returning from cheat installation.
