# Cheat Downloader

A MinUI pak for browsing, finding, and installing game cheat files from the Libretro database directly on your device.

[![Latest Release](https://img.shields.io/github/v/release/nborodikhin/nextui-cheat-downloader-alt)](https://github.com/nborodikhin/nextui-cheat-downloader-alt/releases/latest)
[![Test Coverage](https://img.shields.io/badge/coverage-report-blue)](https://nborodikhin.github.io/nextui-cheat-downloader-alt/)

<img width="300" alt="Screenshots" src="/screenshots/screenshots.gif"/>

## Requirements

This pak is tested on the following NextUI devices:

- `tg5040`: TrimUI Brick

## Installation

1. Simple

    - Mount your NextUI SD card.
    - Download .pakz from the latest release version from [GitHub releases](https://github.com/nborodikhin/nextui-cheat-downloader-alt/releases).
    - Put it into the root of the SD card
    - Unmount SD card
    - Pak will be installed on the next NextUI boot

2. Manual (here for tg5040, replace with your device identifier is needed)

    - Mount your NextUI SD card.
    - Download CheatDownloader.pak.tg5040.zip from the latest release version from [GitHub releases](https://github.com/nborodikhin/nextui-cheat-downloader-alt/releases).
    - Unpack it into `/Tools/tg5040/`
    - You should have files in the subfolder, e.g. `/Tools/tg5040/Cheat Downloader Offline/launch.sh`
    - Unmount SD card
    - Pak will be available on the next NextUI boot


## Usage

1. Browse to `Tools > Cheat Downloader Offline` and press `A` to launch.
2. On first launch, the app downloads the latest Libretro cheat database.
  
    - Note that the download may take a few minutes - the archive is about 160MB
    - You can also download the latest zip file from
          the [Libretro database releases](https://github.com/libretro/libretro-database/releases/latest)
          and put it to the root of your SD card.  The app will use that zip file instead of downloading it again.
    - On later launches it checks for updates and skips the download if your database is already current.
  
3. **Select a game folder** — the app lists ROM directories on the device. Press `A` to enter one.
4. **Select a game** — browse the games in that folder and press `A` to select one.

    - Pak supports single-file games, as well as an `.m3u` file in the game directory
    - Pak supports folders, provided that a folder has an `.m3u` file
  
5. **Map the system** (first time only per folder) — if the app doesn't yet know which cheat system matches this ROM folder, it asks you to pick one from the database. Your choice is saved and reused automatically from then on.
6. **Select a cheat** — the app searches the database for cheats that match your game using three-tier matching: exact filename first, then title-only, then fuzzy. Pick a cheat and press `A` to install it. If nothing is found, you can browse all cheats for the system or remap the system.
7. The cheat file is installed. The app returns to game selection so you can install more cheats.
8. Launch the game, then open `Menu > Options > Cheats` to enable the cheats you want.

## Technical Information

- Cheats are installed to your NextUI Cheats folder, organized in subfolders by system tag (e.g. `GBA/`, `PS/`).
- The cheat database is cached at `/mnt/SDCARD/.userdata/Cheat Downloader Offline/` as a local SQLite index, so searching is fast and works entirely offline after the initial download.
- Folder-to-system mappings and your last-used game per system are remembered across sessions.

## Building from Source

`./dev` is the single entry point for development: it fetches prerequisites,
builds, tests, packages, and manages versions. It needs Python 3 and, for
device builds, Docker (or Podman via `--podman`).

```bash
# One-time (and after a dependency version bump): download the Nim compiler,
# the miniz sources, and the minui-list/minui-presenter helper binaries
./dev setup

# Build
./dev build                            # host build, for local testing
./dev build tg5040 tg5050              # cross-compile for devices
./dev build all --release              # every platform, optimised and stripped

# Test
./dev test                             # unit tests
./dev test --e2e                       # unit + end-to-end tests
./dev test --coverage                  # both suites, writes coverage/index.html

# Deploy to a device over ADB
./dev devices                          # what is connected, and what it is
./dev install device                   # push the binary to every device
./dev install brick --full             # push the complete pak
./dev run device                       # install and launch on the device
./dev run device --delete              # replace the installed pak, then launch

# Run the app locally against a sandbox SD card layout in /tmp
./dev run
./dev run --reset                      # start from an empty sandbox
./dev run -- textui jsonui             # pass arguments to the app

# Package the release artifacts into release/
./dev dist --strict

# Remove generated files (add --deps to also drop workspace/ and deps/)
./dev clean

# Inspect or edit the version and changelog in pak.json
./dev version latest
./dev version create 1.7.0 "What changed"

# Enter a toolchain, or run one command in it
./dev docker tg5040
./dev docker tg5040 -- ls
```

Platform aliases include `brick`, `brickpro`, `tsp`, `smartpro`, `5040`,
`tsps`, `smartpros`, `5050`, `flip`, and `355`. Aliases ignore case, spaces,
hyphens, and underscores. `all` expands to every platform, and `host` (also
`native`, `local`) means this machine.

`install` and `run` additionally accept `device`, meaning every connected
device, or a raw ADB serial. By default they push only the app binary, which
is the quick path while iterating; `--full` installs the complete pak and
`--delete` removes the installed pak first, clearing files left over from an
older version (userdata is kept). `run` on a device stops the app if it is
running and relaunches it through NextUI.

`./dev dist` produces `release/CheatDownloaderOffline-<platform>.pak.zip` for
manual installs and the combined `release/CheatDownloaderOffline.pakz` used by
the SD card auto-installer. `--strict` requires every platform to build and
verifies that each staged pak contains exactly the expected files — the release
workflow uses it.

## Acknowledgements

- [Cheat Downloader.pak](https://github.com/mikecosentino/nextui-cheat-downloader) by Mike Cosentino
  - online-only downloader where the database is managed by the backend
- [minui-list](https://github.com/josegonzalez/minui-list) by Jose Diaz-Gonzalez
- [minui-presenter](https://github.com/josegonzalez/minui-presenter) by Jose Diaz-Gonzalez
- [miniz](https://github.com/richgel999/miniz) — lightweight zip library
- [libretro-database](https://github.com/libretro/libretro-database) for the cheat files
