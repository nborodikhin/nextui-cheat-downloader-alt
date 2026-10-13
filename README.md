# Cheat Downloader

A MinUI pak for browsing, finding, and installing game cheat files from the Libretro database directly on your device.

[![Latest Release](https://img.shields.io/github/v/release/nborodikhin/nextui-cheat-downloader-alt)](https://github.com/nborodikhin/nextui-cheat-downloader-alt/releases/latest)
[![Test Coverage](https://img.shields.io/badge/coverage-report-blue)](https://nborodikhin.github.io/nextui-cheat-downloader-alt/)

<img width="300" alt="Screenshots" src="/screenshots/screenshots.gif"/>

## Requirements

This pak runs on these NextUI devices:

- `tg5040`: TrimUI Brick
- `tg5050`: TrimUI Smart Pro
- `my355`: Miyoo Flip
- `h700`: Anbernic RG devices with the H700 chip

## Installation

- Mount your NextUI SD card.
- Download a `.pakz` file from the latest release on [GitHub releases](https://github.com/nborodikhin/nextui-cheat-downloader-alt/releases):
  - `CheatDownloaderOffline-<platform>.pakz` holds the pak for one platform, for example `CheatDownloaderOffline-tg5040.pakz`.
  - `CheatDownloaderOffline.pakz` holds the pak for all platforms.
- Put it into the root of the SD card.
- Unmount the SD card.
- NextUI installs the pak on the next boot.

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

## Development

`./dev` is the entry point for development. It needs Python 3, and Docker or Podman for device builds.

```sh
./dev deps fetch        # download the pinned dependencies from deps.json
./dev test              # build and run the unit and end-to-end tests on the host
./dev build all         # cross-compile for every device platform
./dev dist              # build the .pakz packages into dist/
./dev run brick         # install the pak on a connected device over ADB and launch it
./dev --help            # every command
```

## Acknowledgements

- [Cheat Downloader.pak](https://github.com/mikecosentino/nextui-cheat-downloader) by Mike Cosentino
  - online-only downloader where the database is managed by the backend
- [minui-list](https://github.com/josegonzalez/minui-list) by Jose Diaz-Gonzalez
- [minui-presenter](https://github.com/josegonzalez/minui-presenter) by Jose Diaz-Gonzalez
- [miniz](https://github.com/richgel999/miniz) — lightweight zip library
- [libretro-database](https://github.com/libretro/libretro-database) for the cheat files
