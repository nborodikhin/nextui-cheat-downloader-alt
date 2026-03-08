#!/bin/sh

JIM_VER=0.83
MINUI_LIST_VER=0.13.0
MINUI_PRESENTER_VER=0.12.0
MINIZ_VER=3.1.1

for PLATFORM in tg5040 tg5050 my355; do
  mkdir deps
  mkdir workspace
  JIMBIN=deps/jimsh-$PLATFORM
  MZBIN=deps/mz-$PLATFORM
  MINUI_LIST_BIN=deps/minui-list-$PLATFORM
  MINUI_PRESENTER_BIN=deps/minui-presenter-$PLATFORM

  MAKEFLAGS="-j8"

  if [ ! -f $JIMBIN ]; then
    jimdir=jimtcl-${JIM_VER}
    jimdlflag=workspace/jimtcl.downloaded
    [ ! -f $jimdlflag ] && ( wget https://github.com/msteveb/jimtcl/archive/refs/tags/${JIM_VER}.tar.gz -O workspace/jimtcl-${JIM_VER}.tar.gz && touch $jimdlflag )
    [ ! -d workspace/$jimdir ] && ( cd workspace; tar -zxvf jimtcl-${JIM_VER}.tar.gz )

    echo "cd $jimdir; ./configure --disable-ssl --with-ext=sqlite3; make clean; make ${MAKEFLAGS}; \${CROSS_ROOT}/bin/\${CROSS_COMPILE}strip jimsh" > workspace/buildjim.sh
    docker run -it -v `pwd`/workspace/:/root/workspace --rm ghcr.io/loveretro/${PLATFORM}-toolchain /bin/sh buildjim.sh

    cp workspace/$jimdir/jimsh $JIMBIN
  fi

  if [ ! -f $MZBIN ]; then
    minizdir=miniz-${MINIZ_VER}
    minizdlflag=workspace/miniz.downloaded
    [ ! -f minizdlflag ] && ( wget https://github.com/richgel999/miniz/releases/download/${MINIZ_VER}/miniz-${MINIZ_VER}.zip -O workspace/miniz-${MINIZ_VER}.zip && touch $minizdlflag )
    [ ! -d workspace/$minizdir ] && ( cd workspace; mkdir $minizdir; cd $minizdir; unzip ../miniz-${MINIZ_VER}.zip )
    [ ! -f workspace/$minizdir/mz.c ] && ( cp mz.c workspace/$minizdir/ )

    echo "cd $minizdir; \${CROSS_ROOT}/bin/\${CROSS_COMPILE}gcc -Os mz.c miniz.c -o mz && \${CROSS_ROOT}/bin/\${CROSS_COMPILE}strip mz" > workspace/buildminizip.sh
    docker run -it -v `pwd`/workspace/:/root/workspace --rm ghcr.io/loveretro/${PLATFORM}-toolchain /bin/sh buildminizip.sh

    cp workspace/$minizdir/mz $MZBIN
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
