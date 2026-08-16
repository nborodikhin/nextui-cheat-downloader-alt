#!/bin/sh

MINIZ_VER=3.1.1
APOSTROPHE_VER=1.1.1
NIM_VER=2.2.8

# Use wget if available, otherwise fall back to curl (macOS ships curl, not wget)
download() {
  URL=$1
  OUTPUT=$2
  if command -v wget >/dev/null 2>&1; then
    wget -c "$URL" -O "$OUTPUT"
  else
    curl -L -C - "$URL" -o "$OUTPUT"
  fi
}

OS=$(uname -s)
ARCH=$(uname -m)

mkdir -p workspace

minizdir=miniz-${MINIZ_VER}
if [ ! -f $minizdir ]; then
  minizdlflag=workspace/miniz.downloaded
  [ ! -f minizdlflag ] && ( download https://github.com/richgel999/miniz/releases/download/${MINIZ_VER}/miniz-${MINIZ_VER}.zip workspace/miniz-${MINIZ_VER}.zip && touch $minizdlflag )
  [ ! -d workspace/$minizdir ] && ( cd workspace; mkdir $minizdir; cd $minizdir; unzip ../miniz-${MINIZ_VER}.zip )
fi

# Apostrophe (https://github.com/Helaas/Apostrophe) — a header-only C UI
# toolkit, compiled directly into cheat_manager via Nim FFI (see
# apostrophe.nim). Vendored from its GitHub release source archive, same as
# miniz/Nim above. Requires SDL2, SDL2_ttf and SDL2_image headers/libs to be
# available to whatever compiler builds cheat_manager (already true inside
# the tg5040/tg5050/my355 toolchain containers used below; for host builds
# install them yourself, e.g. `apt install libsdl2-dev libsdl2-ttf-dev
# libsdl2-image-dev` or `brew install sdl2 sdl2_ttf sdl2_image`).
apostrophedir=apostrophe-${APOSTROPHE_VER}
if [ ! -d workspace/$apostrophedir ]; then
  apostrophedlflag=workspace/apostrophe.downloaded
  [ ! -f $apostrophedlflag ] && ( download https://github.com/Helaas/Apostrophe/archive/refs/tags/v${APOSTROPHE_VER}.tar.gz workspace/apostrophe-${APOSTROPHE_VER}.tar.gz && touch $apostrophedlflag )
  [ ! -d workspace/$apostrophedir ] && ( cd workspace && tar -xzf apostrophe-${APOSTROPHE_VER}.tar.gz && mv Apostrophe-${APOSTROPHE_VER} $apostrophedir )
fi

# On macOS, download the host-native Nim to workspace/nim-${NIM_VER}-host/ for local builds.
# Do this before extracting the Linux Nim: both archives unpack as nim-${NIM_VER}/, so we
# extract and immediately rename to avoid a collision.
if [ "$OS" = "Darwin" ]; then
  if [ "$ARCH" = "arm64" ]; then
    HOST_NIM_SUFFIX="macosx_arm64"
  else
    HOST_NIM_SUFFIX="macosx_x64"
  fi
  HOST_NIMBIN=workspace/nim-${NIM_VER}-host/bin/nim
  if [ ! -f $HOST_NIMBIN ]; then
    host_nimdlflag=workspace/nim-host.downloaded
    host_nimpkg=nim-${NIM_VER}-${HOST_NIM_SUFFIX}.tar.gz
    [ ! -f $host_nimdlflag ] && ( download https://nim-lang.org/download/$host_nimpkg workspace/$host_nimpkg && touch $host_nimdlflag )
    [ ! -f $HOST_NIMBIN ] && ( cd workspace && tar -xzf $host_nimpkg && mv nim-${NIM_VER} nim-${NIM_VER}-host )
  fi
fi

# Always download the Linux x64 Nim — used inside Docker cross-compilation containers.
NIMBIN=workspace/nim-${NIM_VER}/bin/nim
if [ ! -f $NIMBIN ]; then
  nimdlflag=workspace/nim.downloaded
  nimpkg=nim-${NIM_VER}-linux_x64.tar.xz
  [ ! -f $nimdlflag ] && ( download https://nim-lang.org/download/$nimpkg workspace/$nimpkg && touch $nimdlflag )
  [ ! -f $NIMBIN ] && ( cd workspace && tar -xJf $nimpkg )
fi

if [ ! -f workspace/workspace ]; then
  cd workspace; ln -s . workspace
fi
