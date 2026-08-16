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
- The UI is built on [Apostrophe](https://github.com/Helaas/Apostrophe), a C toolkit compiled directly into the app (previously it shelled out to the separate `minui-list`/`minui-presenter` binaries).

## Development

Building `cheat_manager` (for any platform, including `host`) requires SDL2, SDL2_ttf and SDL2_image headers/libs, since the UI toolkit (Apostrophe) links directly against them:

- Debian/Ubuntu: `apt install libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev`
- macOS: `brew install sdl2 sdl2_ttf sdl2_image`

`./build-deps.sh` fetches everything else needed to build (Nim, miniz, Apostrophe's source, and the cross-compilation toolchains' Nim binaries). See `Makefile` and `build-binary.sh` for the actual build targets (`make build`, `make test`, `make test-e2e`).

## Acknowledgements

- [Cheat Downloader.pak](https://github.com/mikecosentino/nextui-cheat-downloader) by Mike Cosentino
  - online-only downloader where the database is managed by the backend
- [Apostrophe](https://github.com/Helaas/Apostrophe) by Helaas — the UI toolkit this pak's interface is built with
- [miniz](https://github.com/richgel999/miniz) — lightweight zip library
- [libretro-database](https://github.com/libretro/libretro-database) for the cheat files
