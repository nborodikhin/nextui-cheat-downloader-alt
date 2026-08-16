## FFI bindings for Apostrophe (https://github.com/Helaas/Apostrophe), a
## header-only C UI toolkit for NextUI paks. Replaces the old subprocess-based
## minui-list/minui-presenter UI backend: instead of shelling out to separate
## binaries and round-tripping state through JSON files, this links
## Apostrophe directly into the `cheat_manager` binary and drives it in
## process.
##
## Override the vendored source path at compile time with:
##   nim c -d:apostropheDir=/path/to/apostrophe ...
##
## Requires SDL2, SDL2_ttf and SDL2_image headers/libs to be available to the
## C compiler (see build-deps.sh / README.md for how these are provided for
## both host and cross-compiled device builds).

import std/[os, strutils, times]

const apostropheDir {.strdefine.} = "workspace/apostrophe-1.1.1"
const apostropheInclude = apostropheDir & "/include"
const thisDir = currentSourcePath().parentDir()

{.passC: "-I" & apostropheInclude.}
{.passC: "-I" & thisDir.}
{.compile: "apostrophe_impl.c".}

const apH = "apostrophe_all.h"
  ## apostrophe_widgets.h requires apostrophe.h to already be #included in
  ## the same translation unit (it #errors otherwise), but Nim's `header`
  ## pragma emits one #include per header into whatever C file first needs a
  ## symbol from it, independently per file — so a generated file that only
  ## ever touches an apostrophe_widgets.h-declared symbol could otherwise end
  ## up #including it without apostrophe.h. Every FFI declaration below
  ## references this repo-local wrapper header (apostrophe_all.h) instead of
  ## apostrophe.h/apostrophe_widgets.h directly, to make that ordering
  ## unconditional rather than relying on incidental codegen layout.

# ---------------------------------------------------------------------------
# Constants (imported directly from the C headers rather than hardcoded, so
# this stays correct even if upstream renumbers anything other than AP_OK/
# AP_ERROR/AP_CANCELLED, which are documented as a stable part of the ABI).
# ---------------------------------------------------------------------------

var
  AP_OK {.importc, header: apH, nodecl.}: cint
  AP_CANCELLED {.importc, header: apH, nodecl.}: cint
  AP_PLATFORM_IS_DEVICE {.importc, header: apH, nodecl.}: cint

  AP_BTN_A {.importc, header: apH, nodecl.}: cint
  AP_BTN_B {.importc, header: apH, nodecl.}: cint

  AP_FONT_MEDIUM {.importc, header: apH, nodecl.}: cint
  AP_ALIGN_CENTER {.importc, header: apH, nodecl.}: cint

# ---------------------------------------------------------------------------
# Types
#
# These mirror only the fields this pak actually reads/writes. Apostrophe's
# real C structs (from the header, already #included via the `header`
# pragma) may have more fields than declared here — that's fine and
# intentional (same convention as miniz.nim's MzZipArchive): Nim defers
# `sizeof`/copy semantics to the C compiler for `importc` types, so undeclared
# fields are simply left untouched at their C-side default (usually
# zero-initialized via `newSeq`/`zeroMem` below).
# ---------------------------------------------------------------------------

type
  ApColor {.importc: "ap_color", header: apH, bycopy.} = object
    r {.importc.}: uint8
    g {.importc.}: uint8
    b {.importc.}: uint8
    a {.importc.}: uint8

  ApTheme {.importc: "ap_theme", header: apH, bycopy.} = object
    text {.importc.}: ApColor

  ApInputEvent {.importc: "ap_input_event", header: apH, bycopy.} = object
    button {.importc.}: cint
    pressed {.importc.}: bool
    repeated {.importc.}: bool

  ApConfig {.importc: "ap_config", header: apH, bycopy.} = object
    window_title {.importc.}: cstring
    font_path {.importc.}: cstring
    log_path {.importc.}: cstring
    is_nextui {.importc.}: bool

  ApFooterItem {.importc: "ap_footer_item", header: apH, bycopy.} = object
    button {.importc.}: cint
    label {.importc.}: cstring
    is_confirm {.importc.}: bool

  ApListItem {.importc: "ap_list_item", header: apH, bycopy.} = object
    label {.importc.}: cstring

  ApListOpts {.importc: "ap_list_opts", header: apH, bycopy.} = object
    title {.importc.}: cstring
    items {.importc.}: ptr ApListItem
    item_count {.importc.}: cint
    footer {.importc.}: ptr ApFooterItem
    footer_count {.importc.}: cint
    initial_index {.importc.}: cint

  ApListResult {.importc: "ap_list_result", header: apH, bycopy.} = object
    selected_index {.importc.}: cint
    action {.importc.}: cint

  ApMessageOpts {.importc: "ap_message_opts", header: apH, bycopy.} = object
    message {.importc.}: cstring
    footer {.importc.}: ptr ApFooterItem
    footer_count {.importc.}: cint

  ApConfirmResult {.importc: "ap_confirm_result", header: apH, bycopy.} = object
    confirmed {.importc.}: bool

# ---------------------------------------------------------------------------
# Raw C functions
# ---------------------------------------------------------------------------

## Note: raw imports below are all named with a `cAp` prefix rather than
## reusing the C names directly (e.g. `ap_init`) — Nim's identifier equality
## ignores underscores and case after the first letter, so `ap_init` and a
## public wrapper named `apInit` would otherwise collide as "the same name".

proc cApInit(cfg: ptr ApConfig): cint {.importc: "ap_init", header: apH.}
proc cApQuit() {.importc: "ap_quit", header: apH.}
proc cApResolveLogPath(appName: cstring): cstring {.importc: "ap_resolve_log_path", header: apH.}

proc cApGetTheme(): ptr ApTheme {.importc: "ap_get_theme", header: apH.}
proc cApGetFont(tier: cint): pointer {.importc: "ap_get_font", header: apH.}
proc cApGetScreenWidth(): cint {.importc: "ap_get_screen_width", header: apH.}
proc cApGetScreenHeight(): cint {.importc: "ap_get_screen_height", header: apH.}
proc cApGetScaleFactor(): cfloat {.importc: "ap_get_scale_factor", header: apH.}
proc cApPollInput(event: ptr ApInputEvent): bool {.importc: "ap_poll_input", header: apH.}
proc cApDrawBackground() {.importc: "ap_draw_background", header: apH.}
proc cApDrawTextWrapped(font: pointer, text: cstring, x, y, maxW: cint,
                        color: ApColor, align: cint): cint {.importc: "ap_draw_text_wrapped", header: apH.}
proc cApPresent() {.importc: "ap_present", header: apH.}

proc cApListDefaultOpts(title: cstring, items: ptr ApListItem,
                        count: cint): ApListOpts {.importc: "ap_list_default_opts", header: apH.}
proc cApList(opts: ptr ApListOpts, res: ptr ApListResult): cint {.importc: "ap_list", header: apH.}
proc cApConfirmation(opts: ptr ApMessageOpts,
                     res: ptr ApConfirmResult): cint {.importc: "ap_confirmation", header: apH.}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc drainInput() =
  ## Discard any input events queued up before/after a screen change, so a
  ## button mashed during a long synchronous operation doesn't leak into
  ## whatever widget is shown next.
  var ev: ApInputEvent
  while cApPollInput(addr ev):
    discard

proc drawStatusFrame(text: string) =
  ## Draws one frame with `text` centered on screen and presents it. Used for
  ## "please wait" style screens shown around synchronous work (see
  ## `runTask`/`showMessage` below) — Apostrophe's widgets are all blocking,
  ## so rather than juggling a background thread (and the Nim GC/threading
  ## implications of calling back into Nim from a C-spawned pthread, which
  ## can't be validated without real hardware — see
  ## docs/apostrophe-ui-investigation.md), a long-running operation gets one
  ## static status frame instead of a live spinner/progress bar. Reusing
  ## Apostrophe's own threaded ap_process_message() for a real progress bar
  ## is a natural hardware-validated follow-up.
  let theme = cApGetTheme()
  let font = cApGetFont(AP_FONT_MEDIUM)
  let screenW = cApGetScreenWidth()
  let screenH = cApGetScreenHeight()
  let margin = cint(40.0 * cApGetScaleFactor())
  cApDrawBackground()
  discard cApDrawTextWrapped(font, text.cstring, margin, screenH div 2 - margin,
                             screenW - margin * 2, theme.text, AP_ALIGN_CENTER)
  cApPresent()

proc buildFooter(confirmText, cancelText: string): seq[ApFooterItem] =
  @[
    ApFooterItem(button: AP_BTN_B, label: cancelText.cstring, is_confirm: false),
    ApFooterItem(button: AP_BTN_A, label: confirmText.cstring, is_confirm: true),
  ]

# ---------------------------------------------------------------------------
# Public UI operations — see createApostropheUi() in cheat_manager.nim for
# how these back the shared `UI` interface.
# ---------------------------------------------------------------------------

proc apInit*(appName: string): bool =
  var cfg = ApConfig(
    window_title: appName.cstring,
    log_path: cApResolveLogPath(appName.cstring),
    is_nextui: AP_PLATFORM_IS_DEVICE != 0,
  )
  cApInit(addr cfg) == AP_OK

proc apQuit*() =
  cApQuit()

proc apShowMessage*(text: string, timeoutSec: int) =
  ## Blocks until `timeoutSec` seconds have elapsed (default ~2s if <= 0),
  ## animating a small dot spinner so the screen doesn't look frozen.
  let seconds = if timeoutSec <= 0: 2 else: timeoutSec
  let deadline = epochTime() + seconds.float
  drainInput()
  while epochTime() < deadline:
    drainInput()
    let dots = ".".repeat((int(epochTime() * 3) mod 4))
    drawStatusFrame(text & dots)
    sleep(66)
  drainInput()

proc apRunTask*(text: string, work: proc(): bool): bool =
  drainInput()
  drawStatusFrame(text)
  drainInput()
  result = work()
  drainInput()

proc apConfirm*(text: string, confirmText, cancelText: string): bool =
  var footer = buildFooter(confirmText, cancelText)
  var opts = ApMessageOpts(message: text.cstring, footer: addr footer[0],
                           footer_count: cint(footer.len))
  var res: ApConfirmResult
  discard cApConfirmation(addr opts, addr res)
  drainInput()
  result = res.confirmed

proc apList*(title: string, items: seq[string], selectedIndex: int): int =
  if items.len == 0:
    return -1
  var cItems = newSeq[ApListItem](items.len)
  for i, it in items:
    cItems[i] = ApListItem(label: it.cstring)

  var footer = buildFooter("SELECT", "BACK")

  var idx = selectedIndex
  if idx < 0: idx = 0
  elif idx >= items.len: idx = items.len - 1

  var opts = cApListDefaultOpts(title.cstring, addr cItems[0], cint(items.len))
  opts.footer = addr footer[0]
  opts.footer_count = cint(footer.len)
  opts.initial_index = cint(idx)

  var res: ApListResult
  let rc = cApList(addr opts, addr res)
  drainInput()
  if rc != AP_OK:
    return -1
  if res.selected_index < 0 or res.selected_index >= items.len:
    return -1
  result = res.selected_index.int
