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

# Detect host OS and architecture to select the right Nim package
OS=$(uname -s)
ARCH=$(uname -m)
if [ "$OS" = "Darwin" ] && [ "$ARCH" = "arm64" ]; then
  NIM_PLATFORM_SUFFIX="macosx_arm64"
  NIM_PKG_EXT="tar.gz"
elif [ "$OS" = "Darwin" ]; then
  NIM_PLATFORM_SUFFIX="macosx_x64"
  NIM_PKG_EXT="tar.gz"
else
  NIM_PLATFORM_SUFFIX="linux_x64"
  NIM_PKG_EXT="tar.xz"
fi

for PLATFORM in tg5040 tg5050 my355; do
  mkdir -p deps
  mkdir -p workspace
  MINUI_LIST_BIN=deps/minui-list-$PLATFORM
  MINUI_PRESENTER_BIN=deps/minui-presenter-$PLATFORM
  NIMDIR=nim-$NIM_VER
  NIMBIN=workspace/$NIMDIR/bin/nim

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


# host
if [ ! -f $NIMBIN ]; then
  nimdlflag=workspace/nim.downloaded
  nimpkg=nim-${NIM_VER}-${NIM_PLATFORM_SUFFIX}.${NIM_PKG_EXT}

  [ ! -f $nimdlflag ] && ( download https://nim-lang.org/download/$nimpkg workspace/$nimpkg && touch $nimdlflag )
  if [ ! -f $NIMBIN ]; then
    if [ "$NIM_PKG_EXT" = "tar.xz" ]; then
      ( cd workspace && tar -xJf $nimpkg )
    else
      ( cd workspace && tar -xzf $nimpkg )
    fi
  fi
fi

if [ ! -f workspace/workspace ]; then
  cd workspace; ln -s . workspace
fi
