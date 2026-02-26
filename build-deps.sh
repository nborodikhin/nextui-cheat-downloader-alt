#!/bin/sh

JIM_VER=0.83
MINUI_LIST_VER=0.12.0
MINUI_PRESENTER_VER=0.10.0
MINIZ_VER=3.1.1

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

if [ ! -f deps/mz ]; then
  minizdir=miniz-${MINIZ_VER}
  minizdlflag=workspace/miniz.downloaded
  [ ! -f minizdlflag ] && ( wget https://github.com/richgel999/miniz/releases/download/${MINIZ_VER}/miniz-${MINIZ_VER}.zip -O workspace/miniz-${MINIZ_VER}.zip && touch $minizdlflag )
  [ ! -d workspace/$minizdir ] && ( cd workspace; mkdir $minizdir; cd $minizdir; unzip ../miniz-${MINIZ_VER}.zip )
  [ ! -f workspace/$minizdir/mz.c ] && ( cp mz.c workspace/$minizdir/ )

  echo "cd $minizdir; \${CROSS_ROOT}/bin/\${CROSS_COMPILE}gcc -Os mz.c miniz.c -o mz && \${CROSS_ROOT}/bin/\${CROSS_COMPILE}strip mz" > workspace/buildminizip.sh

  docker run -it -v `pwd`/workspace/:/root/workspace --rm ghcr.io/loveretro/${PLATFORM}-toolchain /bin/sh buildminizip.sh

  cp workspace/$minizdir/mz deps/mz
fi

if [ ! -s deps/minui-list ]; then
  wget https://github.com/josegonzalez/minui-list/releases/download/$MINUI_LIST_VER/minui-list-tg5040 -O deps/minui-list
fi

if [ ! -s deps/minui-prsenter ]; then
  wget https://github.com/josegonzalez/minui-presenter/releases/download/$MINUI_PRESENTER_VER/minui-presenter-tg5040 -O deps/minui-presenter
fi

