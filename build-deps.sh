#!/bin/sh

MINUI_LIST_VER=0.14.0
MINUI_PRESENTER_VER=0.12.0
MINIZ_VER=3.1.1
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

mkdir -p deps workspace

for PLATFORM in tg5040 tg5050 my355; do
  MINUI_LIST_BIN=deps/minui-list-$PLATFORM
  MINUI_PRESENTER_BIN=deps/minui-presenter-$PLATFORM

  MAKEFLAGS="-j8"

  minizdir=miniz-${MINIZ_VER}
  if [ ! -f $minizdir ]; then
    minizdlflag=workspace/miniz.downloaded
    [ ! -f minizdlflag ] && ( download https://github.com/richgel999/miniz/releases/download/${MINIZ_VER}/miniz-${MINIZ_VER}.zip workspace/miniz-${MINIZ_VER}.zip && touch $minizdlflag )
    [ ! -d workspace/$minizdir ] && ( cd workspace; mkdir $minizdir; cd $minizdir; unzip ../miniz-${MINIZ_VER}.zip )
  fi

  if [ ! -s $MINUI_LIST_BIN ]; then
    download https://github.com/josegonzalez/minui-list/releases/download/$MINUI_LIST_VER/minui-list-$PLATFORM workspace/minui-list-$PLATFORM

    echo "\${CROSS_ROOT}/bin/\${CROSS_COMPILE}strip minui-list-$PLATFORM" > workspace/buildminuilist.sh
    docker run -v `pwd`/workspace/:/root/workspace --rm ghcr.io/loveretro/${PLATFORM}-toolchain /bin/sh buildminuilist.sh

    cp workspace/minui-list-$PLATFORM $MINUI_LIST_BIN
  fi

  if [ ! -s $MINUI_PRESENTER_BIN ]; then
    download https://github.com/josegonzalez/minui-presenter/releases/download/$MINUI_PRESENTER_VER/minui-presenter-$PLATFORM workspace/minui-presenter-$PLATFORM

    echo "\${CROSS_ROOT}/bin/\${CROSS_COMPILE}strip minui-presenter-$PLATFORM" > workspace/buildminuipresenter.sh
    docker run -v `pwd`/workspace/:/root/workspace --rm ghcr.io/loveretro/${PLATFORM}-toolchain /bin/sh buildminuipresenter.sh

    cp workspace/minui-presenter-$PLATFORM $MINUI_PRESENTER_BIN
  fi

done


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
