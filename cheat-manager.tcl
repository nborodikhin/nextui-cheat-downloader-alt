#!/usr/bin/env jimsh

package require json
package require sqlite3

# --- Configuration ---
set ENV(ROM_DIR) [env ROM_DIR]
set ENV(CACHE_DIR) [env CACHE_DIR]
set ENV(CHEAT_DIR) [env CHEAT_DIR]

set missing {}
if {$ENV(ROM_DIR) eq ""} { lappend missing ROM_DIR }
if {$ENV(CACHE_DIR) eq ""} { lappend missing CACHE_DIR }
if {$ENV(CHEAT_DIR) eq ""} { lappend missing CHEAT_DIR }

if {[llength $missing] > 0} {
    puts "Error: Missing required environment variables: [join $missing ", "]"
    exit 1
}

# --- External Commands ---
array set CMD {
    CURL            curl
    TAR             tar
    MINUI_PRESENTER minui-presenter
    MINUI_LIST      minui-list
}

namespace eval STATE {
    proc init {} {
        # Initialize state variables and paths.
        #
        # Sets up the STATE dict, file path, and JSON schema
        # using the global CACHE_DIR.
        global ENV
        variable STATE [dict create dbVersion "" lastFolder "" tags [dict create] lastGame [dict create]]
        variable STATE_FILE "$ENV(CACHE_DIR)/state.json"
        variable STATE_SCHEMA {obj dbVersion str lastFolder str tags {obj tag str} lastGame {obj tag str}}
    }

    proc load {} {
        # Load persisted state from disk.
        #
        # Reads and parses the JSON state file. Logs an error
        # on failure but does not abort.
        variable STATE
        variable STATE_FILE
        if {[file exists $STATE_FILE]} {
            if {[catch {
                set fh [open $STATE_FILE r]
                set content [read $fh]
                close $fh
                set STATE [json::decode $content]
            } err]} {
                puts "Error loading state: $err"
            }
        }
    }

    proc save {} {
        # Persist current state to disk as JSON.
        #
        # Writes the STATE dict to STATE_FILE using the defined
        # schema. Logs an error on failure.
        variable STATE
        variable STATE_SCHEMA
        variable STATE_FILE
        if {[catch {
            set fh [open $STATE_FILE w]
            set json [json::encode $STATE $STATE_SCHEMA]
            debug "Saving $json"
            puts $fh $json
            close $fh
        } err]} {
            puts "Error saving state: $err"
        }
    }

    proc getCheatDbVersion {} {
        # Get the stored cheat database version string.
        #
        # Returns the version string, or empty string if unset.
        variable STATE
        if {[dict exists $STATE dbVersion]} {
            return [dict get $STATE dbVersion]
        }
        return ""
    }

    proc setCheatDbVersion {version} {
        # Set and persist the cheat database version.
        #  version - Version string to store.
        variable STATE
        dict set STATE dbVersion $version
        save
    }

    proc getSystem {tag} {
        # Look up the system name mapped to a ROM directory tag.
        #  tag - ROM directory tag (e.g. "GBA").
        #
        # Returns the system name, or empty string if unmapped.
        variable STATE
        if {[dict exists $STATE tags $tag]} {
            return [dict get $STATE tags $tag]
        }
        return ""
    }

    proc setSystem {tag system} {
        # Map a ROM directory tag to a cheat-database system name and persist.
        #  tag    - ROM directory tag.
        #  system - Cheat-database system name.
        variable STATE
        dict set STATE tags $tag $system
        save
    }

    proc getLastFolder {} {
        variable STATE
        if {[dict exists $STATE lastFolder]} { return [dict get $STATE lastFolder] }
        return ""
    }
    proc setLastFolder {name} {
        variable STATE
        dict set STATE lastFolder $name
        save
    }
    proc getLastGame {tag} {
        variable STATE
        if {[dict exists $STATE lastGame $tag]} { return [dict get $STATE lastGame $tag] }
        return ""
    }
    proc setLastGame {tag game} {
        variable STATE
        dict set STATE lastGame $tag $game
        save
    }
}

namespace eval CheatDb {
    variable ARCHIVE_FILE ""
    variable DB           ""

    proc init {file} {
        variable ARCHIVE_FILE
        variable DB
        global CMD
        set ARCHIVE_FILE $file

        set db_file [regsub {\.tar\.gz$} $file .db]

        # Open (or create) the database
        if {[catch {set DB [sqlite3.open $db_file]} err]} {
            puts "Error opening database: $err"
            return
        }

        # Create schema
        $DB query {CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT)}
        $DB query {CREATE TABLE IF NOT EXISTS systems (name TEXT PRIMARY KEY)}
        $DB query {CREATE TABLE IF NOT EXISTS cheats (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, path TEXT, system TEXT)}

        # Check if cached DB matches the current archive
        set rows [$DB query {SELECT value FROM metadata WHERE key='archive_file'}]
        if {[llength $rows] > 0} {
            set stored [dict get [lindex $rows 0] value]
        } else {
            set stored ""
        }
        set cnt_rows [$DB query {SELECT count(*) as cnt FROM cheats}]
        set cnt [dict get [lindex $cnt_rows 0] cnt]
        if {$stored eq $file && $cnt > 0} {
            return   ;# cache hit — nothing to do
        }

        # Archive has changed (or DB is empty) — rebuild
        $DB query {DELETE FROM metadata}
        $DB query {DELETE FROM systems}
        $DB query {DELETE FROM cheats}

        if {![file exists $file]} { return }

        if {[catch {set pipe [open [list | $CMD(TAR) tzf $file] r]} err]} {
            puts "Error reading archive: $err"
            return
        }

        $DB query {BEGIN TRANSACTION}
        while {[gets $pipe line] >= 0} {
            set path [string trim $line]
            if {$path eq "" || [string index $path end] eq "/"} continue

            # Pattern: .../cht/System Name/Cheat Name.cht
            if {[regexp {cht/([^/]+)/(.*)$} $path -> system_name cheat_filename]} {
                if {[string match "*.md" $cheat_filename]} continue

                set norm_system [normalize_system_name $system_name]
                set cheat_name  [file tail $cheat_filename]

                $DB query "INSERT OR IGNORE INTO systems(name) VALUES('%s')" $norm_system
                $DB query "INSERT INTO cheats(name, path, system) VALUES('%s', '%s', '%s')" $cheat_name $path $norm_system
            }
        }
        $DB query "INSERT INTO metadata(key,value) VALUES('archive_file','%s')" $file
        $DB query {COMMIT}

        if {[catch {close $pipe} err]} {
            puts "Error reading archive: $err"
        }
    }

    proc getSystems {} {
        variable DB
        set rows [$DB query {SELECT name FROM systems ORDER BY name}]
        set result {}
        foreach row $rows {
            lappend result [dict get $row name]
        }
        return $result
    }

    proc getAllCheats {system} {
        variable DB
        set rows [$DB query "SELECT id FROM cheats WHERE system='%s' ORDER BY id" $system]
        set result {}
        foreach row $rows {
            lappend result [dict get $row id]
        }
        return $result
    }

    proc getCheatName {id} {
        variable DB
        set rows [$DB query "SELECT name FROM cheats WHERE id='%s'" $id]
        if {[llength $rows] == 0} { return "" }
        return [dict get [lindex $rows 0] name]
    }

    proc extractCheat {id target} {
        variable ARCHIVE_FILE
        variable DB
        global CMD ENV
        set rows [$DB query "SELECT path FROM cheats WHERE id='%s'" $id]
        if {[llength $rows] == 0} { return 0 }
        set path [dict get [lindex $rows 0] path]

        set tmp_path "$ENV(CACHE_DIR)/cheat_extract.tmp"
        debug "Extracting archive path: $path -> $tmp_path"
        if {[catch {exec $CMD(TAR) xzf $ARCHIVE_FILE -O $path > $tmp_path} err]} {
            puts "Error extracting cheat: $err"
            file delete -force $tmp_path
            return 0
        }
        file rename -force $tmp_path $target
        return 1
    }

    proc normalize_system_name {name} {
        # Strip trailing parenthesized suffix from an archive system name.
        #  name - Raw system name from the archive (e.g. "Sony - PlayStation (beetle core)").
        #
        # Returns the name with any trailing "(...)" removed.
        regsub {\s*\([^)]+\)$} $name "" new_name
        return $new_name
    }
}

# --- UI Abstraction ---

variable DEBUG 0

proc debug {args} {
    variable DEBUG
    if {$DEBUG} {
        puts "debug: [join $args]"
    }
}

rename exec exec_real
proc exec {args} {
    debug "$args"
    exec_real {*}$args
}

namespace eval UI {
    variable TEXTUI 0
    variable PRESENTER_PID 0

    proc init {textui} {
        # Initialize the UI subsystem.
        #  textui - Boolean; 1 for text/terminal mode, 0 for minui-presenter.
        variable TEXTUI $textui
    }

    proc kill_presenter {{signal KILL} {cleanup true}} {
        # Send a signal to the running presenter process.
        #  signal  - Signal name to send (default: KILL). Use USR1 to advance messages.
        #  cleanup - If true, wait for the process to exit and reset PRESENTER_PID to 0.
        variable PRESENTER_PID
        if {$PRESENTER_PID != 0} {
            debug "killing presenter $PRESENTER_PID with $signal"
            kill -$signal $PRESENTER_PID
            if {$cleanup} {
                catch {wait $PRESENTER_PID}
                set PRESENTER_PID 0
            }
        }
    }

    proc message {text {timeout 0}} {
        # Display a message to the user.
        #  text    - Message text to display
        #  timeout - Seconds to show (0 = blocking, -1 = async/non-blocking).
        #
        # In text mode, prints to stdout. In GUI mode, uses minui-presenter.
        variable TEXTUI
        variable PRESENTER_PID
        global CMD

        kill_presenter
        debug "message: $text, timeout $timeout"
        if {$TEXTUI} {
            puts "\n[string repeat - 40]"
            puts "MESSAGE: $text"
            puts "[string repeat - 40]\n"
            if {$timeout > 0} {
                after [expr {$timeout * 1000}]
            }
        } else {
            if {$timeout <= 0} {
                set PRESENTER_PID [exec $CMD(MINUI_PRESENTER) --message "$text" --timeout -1 &]
            } else {
                set PRESENTER_PID 0
                catch {exec $CMD(MINUI_PRESENTER) --message "$text" --timeout $timeout}
            }
        }
    }

    proc messages {lines} {
        # Display multiple messages to the user, see also [next_message].
        #  lines   - List of message strings to display.
        #
        # In text mode, prints first line with a count of remaining lines.
        # In GUI mode, writes messages.json and uses minui-presenter --file.
        variable TEXTUI
        variable PRESENTER_PID
        global ENV CMD

        kill_presenter
        debug "messages: [llength $lines] lines"
        if {$TEXTUI} {
            set first [lindex $lines 0]
            set rest [expr {[llength $lines] - 1}]
            if {$rest > 0} {
                puts "MESSAGE: $first, $rest more lines"
            } else {
                puts "MESSAGE: $first"
            }
        } else {
            set json_file "$ENV(CACHE_DIR)/messages.json"
            set items [::list]
            foreach line $lines {
                lappend items [dict create text $line]
            }
            set data [dict create items $items]
            set fh [open $json_file w]
            puts $fh [json::encode $data {obj items {list obj}}]
            close $fh

            set PRESENTER_PID [exec $CMD(MINUI_PRESENTER) --file $json_file --disable-auto-sleep &]
        }
    }

    proc next_message {} {
        # Advance the presenter to the next message from the list set by [messages].
        #
        # Sends SIGUSR1 to the presenter process without waiting for it to exit.
        kill_presenter USR1 false
    }

    proc confirm {text {confirm-text Yes} {cancel-text No}} {
        # Prompt the user for a yes/no confirmation.
        #  text         - Question text to display.
        #  confirm-text - Label for the confirm button (default: Yes).
        #  cancel-text  - Label for the cancel button (default: No).
        #
        # Returns 1 if confirmed, 0 otherwise.
        variable TEXTUI
        global ENV CMD
        kill_presenter
        if {$TEXTUI} {
            puts "\nCONFIRM: $text (y/n)"
            flush stdout
            set input [gets stdin]
            if {[string tolower $input] eq "y"} { return 1 }
            return 0
        } else {
            set cmd [::list $CMD(MINUI_PRESENTER) --message $text \
                --confirm-button A --confirm-text ${confirm-text} --confirm-show \
                --cancel-button B --cancel-text ${cancel-text} --cancel-show \
                --timeout 0]
            if {[catch {exec {*}$cmd}]} {
                return 0 ;# B pressed or error
            }
            return 1 ;# A pressed
        }
    }

    proc list {title items {selected_index 0}} {
        # Display a selectable list and return the chosen item's ID.
        #  title          - List heading.
        #  items          - List of dicts with id/text keys (or legacy name/string items).
        #  selected_index - Initially highlighted index (GUI mode only).
        #
        # Returns the selected item's id, or empty string on cancel.
        variable TEXTUI
        global ENV CMD

        # Normalize items to list of dicts {id "..." text "..."}
        set norm_items [::list]
        set idx 0
        foreach item $items {
            if {[dict exists $item id] && [dict exists $item text]} {
                lappend norm_items $item
            } else {
                # Legacy/String case: use index as ID, item string as text
                if {[dict exists $item name]} {
                    lappend norm_items [dict create id $idx text [dict get $item name]]
                } else {
                     lappend norm_items [dict create id $idx text $item]
                }
            }
            incr idx
        }

        if {$TEXTUI} {
            puts "\n=== $title ==="

            # Calculate number width for alignment (1-based display)
            set max_num [llength $norm_items]
            set num_width [string length $max_num]

            set i 0
            foreach item $norm_items {
                set display_num [expr {$i + 1}]
                set padded_num [format "%${num_width}d" $display_num]

                if {$i == $selected_index} {
                    set prefix "->$padded_num."
                } else {
                    set prefix "  $padded_num."
                }

                puts "$prefix [dict get $item text]"
                incr i
            }

            puts "Enter selection (Enter for current, 'q' to cancel):"
            flush stdout
            set input [gets stdin]

            if {$input eq ""} {
                return [dict get [lindex $norm_items $selected_index] id]
            }
            if {![string is integer $input] || $input < 1 || $input > [llength $norm_items]} {
                return ""
            }
            # Convert from 1-based user input to 0-based index
            return [dict get [lindex $norm_items [expr {$input - 1}]] id]
        } else {
            set json_file "$ENV(CACHE_DIR)/list.json"

            # Convert to minui-list format: list of objects with "name" and "selected" properties
            set minui_items [::list]
            set item_idx 0
            foreach item $norm_items {
                set name [dict get $item text]
                set item [dict create name $name]
                if {$item_idx == $selected_index} {
                    dict set item selected -1
                    dict set item unselecteable true
                    #$item_idx
                }
                debug "Item: $item"
                lappend minui_items $item
                incr item_idx
            }

            set data [dict create items $minui_items]

            set fh [open $json_file w]
            puts $fh [json::encode $data {obj items {list obj name str * num}}]
            close $fh

            # We use --write-value state to get the selected index, then map back to ID
            kill_presenter
            set out_file "$ENV(CACHE_DIR)/list_result.json"
            catch {file delete $out_file}
            set cmd [::list $CMD(MINUI_LIST) --file $json_file --item-key "items" --title "$title" --write-location $out_file --write-value state]

            if {[catch {exec {*}$cmd}]} {
                return "" ;# Cancel
            }

            if {![file exists $out_file]} { return "" }
            set fh [open $out_file r]
            set content [read $fh]
            close $fh
            set sel_idx [dict get [json::decode $content] selected]
            if {![string is integer $sel_idx]} { return "" }

            if {$sel_idx >= 0 && $sel_idx < [llength $norm_items]} {
                return [dict get [lindex $norm_items $sel_idx] id]
            }
            return ""
        }
    }
}

# --- Helper Functions ---

proc normalize_title {s} {
    # Strip file extension, parenthesized text, bracketed text, then keep only lowercase alphanumerics.
    set s [file rootname $s]
    regsub -all {\s*\([^)]*\)} $s "" s
    regsub -all {\s*\[[^\]]*\]} $s "" s
    regsub -all {[^a-zA-Z0-9]} $s "" s
    return [string tolower $s]
}

proc check_update {} {
    # Check GitHub for the latest libretro-database release tag.
    #
    # Returns the tag string (e.g. "v1.0"), or empty string on failure.
    global ENV CMD
    set url "https://github.com/libretro/libretro-database/releases/latest"

    if {[catch {exec $CMD(CURL) -ksI -w "%{redirect_url}" -o /dev/null $url} redirect_url]} {
        puts "Error checking update: $redirect_url"
        return ""
    }

    if {$redirect_url eq ""} {
        if {[catch {exec $CMD(CURL) -kLs -o /dev/null -w "%{url_effective}" $url} effective_url]} {
            return ""
        }
        set redirect_url $effective_url
    }

    if {[regexp {tag/([^/]+)$} $redirect_url -> tag]} {
        return $tag
    }
    return ""
}

proc download_file {url output_path} {
    # Download a file from a URL to a local path.
    #  url         - Remote URL to fetch.
    #  output_path - Local file path to write.
    #
    # Returns 1 on success, 0 on failure.
    global ENV CMD
    debug "Downloading $url to $output_path..."
    set messages [list]
    lappend messages "Downloading cheat archive [file tail $url]"
    set max_mb 170
    for {set i 1} {$i < $max_mb} {incr i} {
       lappend messages "Downloading cheat archive [file tail $url]. Progress: ${i} MB of about 170 MB"
    }
    UI::messages $messages

    set tmp_path "${output_path}.tmp"
    file delete -force $tmp_path
    file delete -force $output_path

    set pipe [open [list | $CMD(CURL) -ksL $url] r]
    fconfigure $pipe -translation binary

    set fd [open $tmp_path w]
    fconfigure $fd -translation binary

    set bytes 0
    set last_mb 0
    set more_than_200 false
    while {![eof $pipe]} {
        set chunk [read $pipe 65536]
        if {[string length $chunk] > 0} {
            puts -nonewline $fd $chunk
            incr bytes [string length $chunk]
            set mb [expr {$bytes / 1048576}]
            if {$mb != $last_mb} {
                set last_mb $mb
                debug "Downloaded ${mb} MB so far..."
                if {$mb < $max_mb} {
                    UI::next_message
                } elseif {$mb == $max_mb} {
                    UI::message "Downloading cheat archive [file tail $url]. Progress: $max_mb+ MB" -1
                }
            }
        }
    }
    close $fd

    if {[catch {close $pipe} err]} {
        debug "Download failed: $err"
        file delete -force $tmp_path
        UI::message "Download Failed!" 2
        return 0
    }

    if {![file exists $tmp_path] || [file size $tmp_path] == 0} {
        debug "Download failed"
        file delete -force $tmp_path
        UI::message "Download Failed!" 2
        return 0
    }

    file rename -force $tmp_path $output_path

    set size [file size $output_path]
    set mb [expr {$size / 1048576}]
    debug "Download complete. Final size: ${mb} MB"
    UI::message "Download Complete! ${mb} MB" 1
    return 1
}

# --- Browser Logic ---

proc browser_list_dirs {} {
    # List ROM subdirectories sorted alphabetically.
    #
    # Returns a list of dicts with "name" and "path" keys.
    global ENV
    set all [glob -nocomplain "$ENV(ROM_DIR)/*"]
    set all [lsort -dictionary $all]
    set result {}
    foreach d $all {
        if {[file isdirectory $d]} {
            set name [file tail $d]
            lappend result [dict create name $name path $d]
        }
    }
    return $result
}

proc browser_list_games {dir_path} {
    # List game files within a ROM directory.
    #  dir_path - Absolute path to the ROM directory.
    #
    # Handles plain files, .m3u playlists inside subdirectories,
    # and subdirectories containing valid game files.
    # Returns a list of dicts with "name" and "path" keys.
    global ENV
    set all [glob -nocomplain "$dir_path/*"]
    set all [lsort -dictionary $all]
    set result {}

    foreach f $all {
        set name [file tail $f]
        if {[string match ".*" $name]} { continue }

        if {[file isfile $f]} {
            set ext [string tolower [file extension $name]]
            if {$ext ni {.txt .md .xml .db .pdf .cht .png .jpg .jpeg}} {
                lappend result [dict create name $name path $f]
            }
        } elseif {[file isdirectory $f]} {
            # Check for .m3u inside subdir
            set m3u_files [glob -nocomplain "$f/*.m3u"]
            if {[llength $m3u_files] > 0} {
                # Use the first m3u file found
                set m3u_path [lindex $m3u_files 0]
                set m3u_name [file tail $m3u_path]
                lappend result [dict create name $m3u_name path $m3u_path]
            } else {
                # Check for other valid game files inside to confirm it's a game dir
                set subfiles [glob -nocomplain "$f/*"]
                set valid_game_found 0
                foreach sf $subfiles {
                    if {[file isfile $sf]} {
                        set sname [file tail $sf]
                        if {[string match ".*" $sname]} { continue }
                        set sext [string tolower [file extension $sname]]
                        if {$sext ni {.txt .md .xml .db .pdf .cht .png .jpg .jpeg}} {
                            set valid_game_found 1
                            break
                        }
                    }
                }

                if {$valid_game_found} {
                    lappend result [dict create name $name path $f]
                }
            }
        }
    }
    return $result
}

proc extract_tag {dir_name} {
    # Extract the system tag from a ROM directory name.
    #  dir_name - Directory name (e.g. "GBA" or "Game Boy Advance (GBA)").
    #
    # Returns the tag string, or empty string if none found.
    if {[regexp {^[A-Z0-9]+$} $dir_name]} {
        return $dir_name
    }
    if {[regexp {\(([^)]+)\)$} $dir_name -> tag]} {
        return $tag
    }
    return ""
}

proc ensure_dirs {} {
    # Create cache and cheat directories if they do not exist.
    global ENV
    file mkdir $ENV(CACHE_DIR)
    file mkdir $ENV(CHEAT_DIR)
}

proc main {} {
    global ENV
    ensure_dirs
    STATE::init
    STATE::load

    # --- shared context ---
    set latestVersion ""
    set currentVersion ""
    set is_first_install 0
    set dir_path ""; set dir_name ""; set tag ""
    set game_name ""; set game_base ""
    set mapped_system ""
    set all_ids {}; set all_matches {}; set tier3 {}
    set selected_cheat_id ""

    set exit_code 0
    set state CHECK_UPDATE
    while {$state ne "EXIT"} {
        switch $state {

            CHECK_UPDATE {
                UI::message "Checking for updates..."
                set latestVersion [check_update]
                set currentVersion [STATE::getCheatDbVersion]
                set db_file "$ENV(CACHE_DIR)/cheats.tar.gz"
                if {$currentVersion ne "" && ![file exists $db_file]} {
                    set currentVersion ""
                    STATE::setCheatDbVersion ""
                }
                if {$currentVersion eq "" && $latestVersion eq ""} {
                    UI::message "Can't download database from GitHub. Exiting." 3
                    set exit_code 1; set state EXIT
                } elseif {$currentVersion eq ""} {
                    set state CONFIRM_DOWNLOAD
                } elseif {$latestVersion ne "" && $latestVersion ne $currentVersion} {
                    set state CONFIRM_UPDATE
                } else {
                    set state INIT_DB
                }
            }

            CONFIRM_DOWNLOAD {
                if {[UI::confirm "No downloaded database. Download $latestVersion now?" "Download" "Exit"]} {
                    set is_first_install 1
                    set state DOWNLOAD
                } else {
                    set state EXIT
                }
            }

            CONFIRM_UPDATE {
                set currentVersion [STATE::getCheatDbVersion]
                if {[UI::confirm "Database update available: $latestVersion. Download?" "Download" "Use current $currentVersion"]} {
                    set state DOWNLOAD
                } else {
                    set state INIT_DB
                }
            }

            DOWNLOAD {
                set url "https://github.com/libretro/libretro-database/archive/refs/tags/${latestVersion}.tar.gz"
                if {[download_file $url "$ENV(CACHE_DIR)/cheats.tar.gz"]} {
                    STATE::setCheatDbVersion $latestVersion
                    if {!$is_first_install} { UI::message "Update Complete!" 2 }
                    set state INIT_DB
                } elseif {$is_first_install} {
                    UI::message "Download Failed! Exiting." 4
                    set exit_code 1; set state EXIT
                } else {
                    set state INIT_DB
                }
            }

            INIT_DB {
                UI::message "Checking cheat archive..."
                CheatDb::init "$ENV(CACHE_DIR)/cheats.tar.gz"
                set state SELECT_GAME_FOLDER
            }

            SELECT_GAME_FOLDER {
                set dirs [browser_list_dirs]
                set dir_items [list]
                set last_folder [STATE::getLastFolder]
                set selected_idx 0
                set i 0
                foreach d $dirs {
                    set dir_name [dict get $d name]
                    if {$dir_name eq $last_folder} {
                        set selected_idx $i
                    }
                    lappend dir_items [dict create id $i text [dict get $d name]]
                    incr i
                }
                set dir_idx [UI::list "Select Game Folder" $dir_items $selected_idx]
                if {$dir_idx eq ""} {
                    set state EXIT
                    continue
                }
                set selected_dir [lindex $dirs $dir_idx]
                set dir_path [dict get $selected_dir path]
                set dir_name [dict get $selected_dir name]
                STATE::setLastFolder $dir_name
                set tag [extract_tag $dir_name]
                if {$tag eq ""} {
                    UI::message "Could not detect tag for '$dir_name'" 2
                    set state SELECT_GAME_FOLDER
                } else {
                    set mapped_system [STATE::getSystem $tag]
                    set state SELECT_GAME
                }
            }

            SELECT_GAME {
                set games [browser_list_games $dir_path]
                if {[llength $games] == 0} {
                    UI::message "No games found in $dir_name" 2
                    set state SELECT_GAME_FOLDER
                    continue
                }
                set game_items [list]
                set i 0
                foreach g $games {
                    lappend game_items [dict create id $i text [dict get $g name]]
                    incr i
                }

                # Find index of last selected game for this tag
                set initial_idx 0
                set last_game [STATE::getLastGame $tag]
                if {$last_game ne ""} {
                    set idx 0
                    foreach g $games {
                        if {[dict get $g name] eq $last_game} {
                            set initial_idx $idx
                            break
                        }
                        incr idx
                    }
                }

                set game_idx [UI::list "Select Game ($tag)" $game_items $initial_idx]
                if {$game_idx eq ""} {
                    set state SELECT_GAME_FOLDER
                    continue
                }
                set selected_game [lindex $games $game_idx]
                set game_name [dict get $selected_game name]
                set game_base [file rootname $game_name]

                # Remember this selection
                STATE::setLastGame $tag $game_name

                set mapped_system [STATE::getSystem $tag]
                if {$mapped_system eq ""} {
                    set state MAP_SYSTEM
                } else {
                    set state FIND_CHEATS
                }
            }

            MAP_SYSTEM {
                set systems [CheatDb::getSystems]
                if {[llength $systems] == 0} {
                    UI::message "No systems found in database!" 2
                    set state SELECT_GAME_FOLDER
                    continue
                }
                set selected_idx 0
                set sys_items [list]
                foreach s $systems {
                    if {$s eq $mapped_system} {
                        set selected_idx [llength $sys_items]
                    }
                    lappend sys_items [dict create id $s text $s]
                }
                set selected_sys [UI::list "$tag: Select Cheat Folder" $sys_items $selected_idx]
                if {$selected_sys eq ""} {
                    set state SELECT_GAME
                    continue
                }
                set mapped_system $selected_sys
                STATE::setSystem $tag $mapped_system
                set state FIND_CHEATS
            }

            FIND_CHEATS {
                UI::message "Searching cheats for $mapped_system..."
                set all_ids [CheatDb::getAllCheats $mapped_system]
                set tier1 {}; set tier2 {}; set tier3 {}
                set game_title $game_base
                regexp {^([^(]+)} $game_base -> game_title
                set game_title [string trim $game_title]
                set low_gbase  [string tolower $game_base]
                set norm_gbase [normalize_title $game_base]
                foreach cid $all_ids {
                    set cname     [CheatDb::getCheatName $cid]
                    set low_cname [string tolower $cname]
                    set norm_cname [normalize_title $cname]
                    if {[string first $low_gbase $low_cname] == 0} {
                        lappend tier1 $cid
                    } elseif {[string first $norm_cname $norm_gbase] == 0 ||
                              [string first $norm_gbase $norm_cname] == 0} {
                        lappend tier2 $cid
                    } else {
                        lappend tier3 $cid
                    }
                }
                debug "Tier 1: $tier1"
                debug "Tier 2: $tier2"
                set all_matches [concat $tier1 $tier2]
                if {[llength $all_matches] == 0} { set all_matches $tier3 }
                if {[llength $all_matches] == 0} {
                    UI::message "No cheats found for this system." 2
                    set state SELECT_GAME
                } else {
                    set state SELECT_CHEAT
                }
            }

            SELECT_CHEAT {
                set show_all_id "__show_all__"
                set remap_id    "__remap__"
                set cheat_items [list]
                foreach cid $all_matches {
                    lappend cheat_items [dict create id $cid text [CheatDb::getCheatName $cid]]
                }
                if {[llength $tier3] > 0 && [llength $all_matches] != [llength $all_ids]} {
                    lappend cheat_items [dict create id $show_all_id text "Show All Cheats"]
                }
                lappend cheat_items [dict create id $remap_id text "Change cheat folder"]

                set selected_cheat_id [UI::list "Select Cheat for $game_base" $cheat_items]

                if {$selected_cheat_id eq $show_all_id} {
                    set cheat_items [list]
                    foreach cid $all_ids {
                        lappend cheat_items [dict create id $cid text [CheatDb::getCheatName $cid]]
                    }
                    lappend cheat_items [dict create id $remap_id text "Change cheat folder"]
                    set selected_cheat_id [UI::list "Select Cheat for $game_base" $cheat_items]
                }

                if {$selected_cheat_id eq $remap_id} {
                    set state MAP_SYSTEM
                } elseif {$selected_cheat_id eq ""} {
                    set state SELECT_GAME
                } else {
                    set state INSTALL
                }
            }

            INSTALL {
                if {$ENV(CHEAT_DIR) eq $ENV(ROM_DIR)} {
                    set target_dir $dir_path
                } else {
                    set target_dir "$ENV(CHEAT_DIR)/$tag"
                    file mkdir $target_dir
                }
                set target_file "$target_dir/${game_name}.cht"
                UI::message "Extracting cheat for $game_base, may take a minute..." -1
                if {[CheatDb::extractCheat $selected_cheat_id $target_file]} {
                    UI::message "Installed to $target_file" 2
                } else {
                    UI::message "Installation Failed!" 2
                }
                set state SELECT_GAME
            }

            EXIT {
                UI::kill_presenter
                exit $exit_code
            }
        }
    }
}

# Check arguments
set _textui 0
foreach arg $argv {
    if {$arg eq "textui"} {
        set _textui 1
    } elseif {$arg eq "debug"} {
        set ::DEBUG 1
    }
}

UI::init $_textui

debug "ROM_DIR: $ENV(ROM_DIR)"
debug "CACHE_DIR: $ENV(CACHE_DIR)"
debug "CHEAT_DIR: $ENV(CHEAT_DIR)"

main
