/* apostrophe_widgets.h requires apostrophe.h to already be #included in the
 * same translation unit (it #errors otherwise). Nim's `header` pragma emits
 * one #include per header name into whatever C file first needs a symbol
 * from it, independently per file — so a generated file that only ever
 * touches an apostrophe_widgets.h-declared symbol can end up #including it
 * without apostrophe.h. Nim FFI declarations in apostrophe.nim reference
 * this single combined header instead, to make the ordering unconditional. */
#ifndef APOSTROPHE_ALL_H
#define APOSTROPHE_ALL_H
#include "apostrophe.h"
#include "apostrophe_widgets.h"
#endif
