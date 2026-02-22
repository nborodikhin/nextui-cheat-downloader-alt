#!/bin/sh

JIM_VER=0.83
MINUI_LIST_VER=0.12.0
MINUI_PRESENTER_VER=0.10.0

export PLATFORM=tg5040

mkdir deps
mkdir workspace

MAKEFLAGS="-j8"

if [ ! -f deps/jimsh ]; then
  jimdir=jimtcl-${JIM_VER}
  jimdlflag=workspace/jimtcl.downloaded
  [ ! -f $jimdlflag ] && ( wget https://github.com/msteveb/jimtcl/archive/refs/tags/${JIM_VER}.tar.gz -O workspace/jimtcl-${JIM_VER}.tar.gz && touch $jimdlflag )
  [ ! -d workspace/$jimdir ] && ( cd workspace; tar -zxvf jimtcl-${JIM_VER}.tar.gz )

  echo "cd $jimdir; ./configure --disable-ssl --with-ext=sqlite3; make ${MAKEFLAGS}; \${CROSS_ROOT}/bin/\${CROSS_COMPILE}strip jimsh" > workspace/buildjim.sh

  docker run -it -v `pwd`/workspace/:/root/workspace --rm ghcr.io/loveretro/${PLATFORM}-toolchain /bin/sh buildjim.sh

  cp workspace/$jimdir/jimsh deps/jimsh
fi

if [ ! -s deps/minui-list ]; then
  wget https://github.com/josegonzalez/minui-list/releases/download/$MINUI_LIST_VER/minui-list-tg5040 -O deps/minui-list
fi

if [ ! -s deps/minui-prsenter ]; then
  wget https://github.com/josegonzalez/minui-presenter/releases/download/$MINUI_PRESENTER_VER/minui-presenter-tg5040 -O deps/minui-presenter
fi

