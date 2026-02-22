# Cheat Downloader

A MinUI pak for browsing, finding, and installing game cheat files from the Libretro database directly on your device.

## Requirements

This pak is tested on the following NextUI devices:

- `tg5040`: TrimUI Brick

## Installation

1. Simple
  a. Mount your NextUI SD card.
  b. Download .pakz from the latest release version from [GitHub releases](https://github.com/nborodikhin/nextui-cheat-downloader_alt/releases).
  c. Put it into the root of the SD card
  d. Unmount SD card
  e. Pak will be installed on the next NextUI boot
2. Manual
  a. Mount your NextUI SD card.
  b. Download .pak.tg5040.zip from the latest release version from [GitHub releases](https://github.com/nborodikhin/nextui-cheat-downloader_alt/releases).
  c. Unpack it into `/Tools/tg5040/`
  d. You should have files in the subfolder, e.g. `/Tools/tg5040/Cheat Downloader Alt/launch.sh`
  e. Unmount SD card
  f. Pak will be available on the next NextUI boot


## Usage

1. Browse to `Tools > Cheat Downloader Alt` and press `A` to launch.
2. On first launch, the app downloads the latest Libretro cheat database.
  a. Note that the download may take a few minutes - the archive is about 160MB
  b. On later launches it checks for updates and skips the download if your database is already current.
3. **Select a game folder** — the app lists ROM directories on the device. Press `A` to enter one.
4. **Select a game** — browse the games in that folder and press `A` to select one.
  a. Pak supports single-file games, as well as an `.m3u` file in the game directory
  b. Pak supports folders, provided that a folder has an `.m3u` file
5. **Map the system** (first time only per folder) — if the app doesn't yet know which cheat system matches this ROM folder, it asks you to pick one from the database. Your choice is saved and reused automatically from then on.
6. **Select a cheat** — the app searches the database for cheats that match your game using three-tier matching: exact filename first, then title-only, then fuzzy. Pick a cheat and press `A` to install it. If nothing is found, you can browse all cheats for the system or remap the system.
7. The cheat file is installed. The app returns to game selection so you can install more cheats.
8. Launch the game, then open `Menu > Options > Cheats` to enable the cheats you want.

## Technical Information

- Cheats are installed to your NextUI Cheats folder, organized in subfolders by system tag (e.g. `GBA/`, `PS/`).
- The cheat database is cached at `/mnt/SDCARD/.userdata/Cheat Downloader Alt/` as a local SQLite index, so searching is fast and works entirely offline after the initial download.
- Folder-to-system mappings and your last-used game per system are remembered across sessions.

## Acknowledgements

- [Cheat Downloader.pak](https://github.com/mikecosentino/nextui-cheat-downloader) by Mike Cosentino
  - online-only downloader where the database is managed by the backend
- [minui-list](https://github.com/josegonzalez/minui-list) by Jose Diaz-Gonzalez
- [minui-presenter](https://github.com/josegonzalez/minui-presenter) by Jose Diaz-Gonzalez
- [libretro-database](https://github.com/libretro/libretro-database) for the cheat files
