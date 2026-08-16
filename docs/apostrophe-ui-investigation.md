# Investigation: replacing `minui-list` / `minui-presenter` with Apostrophe

## TL;DR

Apostrophe ([Helaas/Apostrophe](https://github.com/Helaas/Apostrophe)) is a viable replacement for the
`minui-list` / `minui-presenter` subprocess pair, and would fix the structural problems those two
binaries have in this pak. It is **not** a drop-in swap, though: it's a C library (FFI, not a CLI
tool), it needs to be linked into `cheat_manager`'s cross-compiled binaries instead of shelled out
to, and it needs to be validated on real tg5040/tg5050/my355 hardware before it can replace the
current UI in production. This document lays out what changes, what it buys us, and a phased plan
so we don't ship a UI regression to users.

This is a **spike/investigation**, not a finished migration — see "What's in / out of scope" below.

## Current architecture

`UI` (`cheat_manager.nim:57-65`) is already an interface object with three implementations:

- `createMinuiUi()` — shells out to `minui-list` / `minui-presenter` binaries via `startProcess`/`execProcess`,
  round-tripping state through JSON files in `env.cacheDir` (`list.json` → `minui-list` → `list_result.json`,
  `messages.json` → `minui-presenter --file`).
- `createTextUi()` — terminal fallback, used for local dev.
- `createJsonUi()` — machine-readable fallback, used by the e2e test suite (`cheat_manager_e2e.nim`).

`minui-list` and `minui-presenter` are pulled as prebuilt per-platform binaries in `build-deps.sh`
(pinned versions `0.14.0` / `0.12.0`), stripped via the `ghcr.io/loveretro/${PLATFORM}-toolchain`
Docker images, and bundled alongside the pak (`build-release.sh`).

### Pain points with the current approach

Some of these are visible directly in the code, some in the pak's own changelog
(`pak.json`: *"fix overlapping in list selectors"*, *"restore last position in lists"*):

1. **Process-per-interaction overhead.** Every list/message/confirm is a fresh `fork`/`exec` of a
   separate binary, with JSON files as the IPC channel (`list.json`/`list_result.json`,
   `messages.json`). On the underpowered handheld CPUs this is a visible delay, especially for
   screens shown back-to-back (e.g. folder → game → system → cheat).
2. **Racy process lifecycle management.** `killPresenter()` is called defensively before almost every
   presenter invocation (including a double-call at `cheat_manager.nim:379-380`), and `nextMessage()`
   works by sending `SIGUSR1` to a tracked PID (`presenterPid`) — fragile if the process already exited
   or was never the one we think it is.
3. **No live filtering/search** in `minui-list` — with a cheat database that can have long lists per
   system, users can't type-to-filter; they scroll.
4. **Two independently-versioned upstream binaries** to track, pin, and re-vendor per platform
   (currently pinned to `minui-list 0.14.0` / `minui-presenter 0.12.0` in `build-deps.sh`), each with
   its own quirks/bugs, rather than one coherent toolkit.
5. **Only ever text lists** — no thumbnails/metadata columns, limited theming, no reusable
   confirmation/keyboard/file-picker widgets, so anything beyond "pick a line of text" has been
   hand-rolled (e.g. the download progress screen).

## What Apostrophe is

- Header-only **C** toolkit (`AP_IMPLEMENTATION` / `AP_WIDGETS_IMPLEMENTATION` in one `.c` translation
  unit), MIT-licensed, current release `v1.1.0`. Built on SDL2 + SDL2_ttf + SDL2_image.
- Targets the same device family this pak already ships for — TrimUI Smart Pro/Brick, Smart Pro S,
  Miyoo Flip — plus a desktop/native SDL preview build for macOS/Linux/Windows, useful for local dev
  without hardware.
- Cross-compiles via the same `ghcr.io/loveretro/${PLATFORM}-toolchain` Docker images this repo
  already uses in `build-deps.sh` for `minui-list`/`minui-presenter`, so no new toolchain dependency —
  just a new library to link (needs SDL2/SDL2_ttf/SDL2_image present in that toolchain image; needs
  verifying).
- Widget model is **blocking**, matching how this app already uses `minui-list`/`minui-presenter`:
  each widget call runs its own event loop internally (via `ap_poll_input`) and returns a result
  struct once the user picks something or backs out. Relevant surface for this pak:

  ```c
  int ap_init(ap_config *cfg);
  void ap_quit(void);

  int ap_list(ap_list_opts *opts, ap_list_result *result);
  int ap_options_list(ap_options_list_opts *opts, ap_options_list_result *result);
  int ap_confirmation(ap_message_opts *opts, ap_confirm_result *result);
  int ap_keyboard(const char *initial, const char *help, ap_keyboard_layout layout,
                  ap_keyboard_result *result);
  int ap_file_picker(ap_file_picker_opts *opts, ap_file_picker_result *result);
  ```

  This maps closely onto the existing `UI` interface (`list`, `confirm`, `message`/`messages`), minus
  the JSON-file IPC and subprocess bookkeeping — `ap_list`/`ap_confirmation` replace `list()`/`confirm()`
  directly, and `ap_message`-style calls replace the presenter `message`/`messages`/`nextMessage`/
  `killPresenter` group (which exists largely to work around presenter being a *separate process*
  Apostrophe wouldn't need that machinery at all, since it's in-process).
- It's already used in production by at least one other NextUI pak in this ecosystem
  ([`nextui-shortcuts-pak`](https://github.com/Helaas/nextui-shortcuts-pak)), so it's exercised on
  real devices, not purely theoretical.

## Integration path for this codebase

1. **Vendor Apostrophe** (git submodule or subtree under e.g. `third_party/apostrophe`) and add a
   small C shim translation unit that defines `AP_IMPLEMENTATION`/`AP_WIDGETS_IMPLEMENTATION` once.
2. **Nim FFI bindings** — a `apostrophe.nim` wrapper using `{.importc, header: "apostrophe.h".}` /
   `{.compile: "apshim.c".}` for `ap_init`/`ap_quit`/`ap_list`/`ap_confirmation`/message widgets and
   their struct types. Nim's C interop handles this well; no wrapper-generator needed given the
   small surface area actually used here.
3. **New `UI` implementation**, `createApostropheUi()`, alongside the existing three — `ap_init()`
   once at startup instead of per-call process spawn, `ap_quit()` at exit, widget calls mapped 1:1
   as above. Existing `createMinuiUi()` stays as-is so this is additive, not a rip-and-replace.
4. **Build system**: `build-deps.sh` gains an Apostrophe checkout/build step per platform (reusing
   the existing toolchain containers); `build-binary.sh`/`Makefile` need the extra `--passC`/`--passL`
   flags to compile+link the shim and Apostrophe's object code, and to pull in SDL2/SDL2_ttf/SDL2_image
   for the target platform.
5. **Cutover**: gate the new UI behind a build flag or runtime check initially (e.g. `-d:useApostrophe`,
   or a `pak.json`-controlled toggle), so it can be validated on hardware before it becomes the default,
   then delete `createMinuiUi()` and the `minui-list`/`minui-presenter` vendoring once confidence is high.

## Risks / open questions

- **No hardware access in this environment** — I can read the code and the Apostrophe API, but I
  can't verify rendering, input mapping, or performance on an actual tg5040/tg5050/my355/Miyoo Flip
  device. This has to be flashed and hand-tested before it ships.
- **SDL2 availability in the `loveretro/*-toolchain` cross images** is assumed, not confirmed here —
  needs a spike build to verify link succeeds for all three platforms this pak ships for.
- **Binary size / startup cost** — linking SDL2 + Apostrophe directly into `cheat_manager` changes the
  binary's footprint and startup profile versus shelling out to prebuilt binaries; worth measuring.
- **Feature gaps to check against current UX**: does `ap_list` support restoring a specific selected
  index on open (used today via `"selected": selectedIndex` in `list.json`, added in pak `v1.2.0`
  specifically to fix a regression)? Confirmed selection API is `ap_list_item.selected` per-item — need
  to verify it round-trips a starting index the same way.
- **Nim toolchain interaction**: this repo currently builds host binaries via `nim c` directly and
  device binaries via `build-binary.sh` inside the cross-compile containers — need to confirm Nim's
  C compiler passthrough plays nicely with Apostrophe's `make tg5040`-style build (or bypass
  Apostrophe's own Makefile and just compile its headers as part of the Nim build, which is probably
  simpler).

## What's in / out of scope for this PR

**In scope (this PR):** this write-up, so the maintainer can weigh in before any code changes are
made to the shipped UI path.

**Out of scope (needs follow-up, hardware-gated PRs):** vendoring Apostrophe, writing the FFI bindings,
implementing `createApostropheUi()`, build system changes, and the actual on-device validation. I
deliberately didn't write and ship untested FFI/UI code for a pak that runs on real handhelds without
a way to verify it doesn't brick the UX — that should land as its own reviewable, hardware-tested PR.

## Recommendation

Proceed, but incrementally:

1. Land a minimal spike: vendor Apostrophe, get a "hello world" `ap_list` call linked and running via
   `make native` (desktop SDL preview) so the FFI plumbing is proven out without touching device builds.
2. Cross-compile that spike for `tg5040` to confirm the Docker toolchain can actually link SDL2 +
   Apostrophe end to end.
3. Implement `createApostropheUi()` behind a flag, test on a real TrimUI Brick (or whichever device is
   on hand), specifically re-checking the two known-regression areas from the changelog: list overlap
   rendering and restoring last-selected position.
4. Once that's solid, flip the default and remove `createMinuiUi()` + the `minui-list`/`minui-presenter`
   vendoring from `build-deps.sh`/`build-release.sh`.
