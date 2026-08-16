/* Apostrophe (https://github.com/Helaas/Apostrophe) is a header-only C UI
 * toolkit: exactly one translation unit must define AP_IMPLEMENTATION /
 * AP_WIDGETS_IMPLEMENTATION before including it, to generate the actual
 * implementation. This is that unit — see apostrophe.nim, which compiles
 * this file in via {.compile.} and declares the Nim-side FFI bindings for
 * the handful of functions/types this pak actually uses.
 */
#define AP_IMPLEMENTATION
#include "apostrophe.h"
#define AP_WIDGETS_IMPLEMENTATION
#include "apostrophe_widgets.h"
