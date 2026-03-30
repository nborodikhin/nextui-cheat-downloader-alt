#!/bin/sh

MINUI_LIST_VER=0.14.0
MINUI_PRESENTER_VER=0.12.0
MINIZ_VER=3.1.1
NIM_VER=2.2.8

for PLATFORM in tg5040 tg5050 my355; do
  mkdir deps
  mkdir workspace
  MINUI_LIST_BIN=deps/minui-list-$PLATFORM
  MINUI_PRESENTER_BIN=deps/minui-presenter-$PLATFORM
  NIMDIR=nim-$NIM_VER
  NIMBIN=workspace/$NIMDIR/bin/nim

  MAKEFLAGS="-j8"

  minizdir=miniz-${MINIZ_VER}
  if [ ! -f $minizdir ]; then
    minizdlflag=workspace/miniz.downloaded
    [ ! -f minizdlflag ] && ( wget https://github.com/richgel999/miniz/releases/download/${MINIZ_VER}/miniz-${MINIZ_VER}.zip -O workspace/miniz-${MINIZ_VER}.zip && touch $minizdlflag )
    [ ! -d workspace/$minizdir ] && ( cd workspace; mkdir $minizdir; cd $minizdir; unzip ../miniz-${MINIZ_VER}.zip )
  fi

  if [ ! -s $MINUI_LIST_BIN ]; then
    wget https://github.com/josegonzalez/minui-list/releases/download/$MINUI_LIST_VER/minui-list-$PLATFORM -O workspace/minui-list-$PLATFORM

    echo "\${CROSS_ROOT}/bin/\${CROSS_COMPILE}strip minui-list-$PLATFORM" > workspace/buildminuilist.sh
    docker run -it -v `pwd`/workspace/:/root/workspace --rm ghcr.io/loveretro/${PLATFORM}-toolchain /bin/sh buildminuilist.sh

    cp workspace/minui-list-$PLATFORM $MINUI_LIST_BIN
  fi

  if [ ! -s $MINUI_PRESENTER_BIN ]; then
    wget https://github.com/josegonzalez/minui-presenter/releases/download/$MINUI_PRESENTER_VER/minui-presenter-$PLATFORM -O workspace/minui-presenter-$PLATFORM

    echo "\${CROSS_ROOT}/bin/\${CROSS_COMPILE}strip minui-presenter-$PLATFORM" > workspace/buildminuipresenter.sh
    docker run -it -v `pwd`/workspace/:/root/workspace --rm ghcr.io/loveretro/${PLATFORM}-toolchain /bin/sh buildminuipresenter.sh

    cp workspace/minui-presenter-$PLATFORM $MINUI_PRESENTER_BIN
  fi

done


# host
if [ ! -f $NIMBIN ]; then
  nimdlflag=worspace/nim.downloaded
  nimpkg=nim-$NIM_VER.tar.xz

  [ ! -f $nimdlflag ] && ( wget -c https://nim-lang.org/download/nim-2.2.8-linux_x64.tar.xz -O workspace/$nimpkg && touch $nimdlflag )
  [ ! -f $NIMBIN ] && ( cd workspace && tar -xJvf $nimpkg )
fi

if [ ! -f workspace/workspace ]; then
  cd workspace; ln -s . workspace
fi
