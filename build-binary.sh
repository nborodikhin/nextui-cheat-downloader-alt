#!/bin/sh
# Usage: ./build-binary.sh [platforms...] [debug|release]
#   platforms:  host (default), tg5040, tg5050, my355, or "all" for all hardware platforms
#   build type: debug (default) or release
# Examples:
#   ./build-binary.sh                      # host debug
#   ./build-binary.sh tg5040 tg5050 release
#   ./build-binary.sh all host debug

set -e

MINIZ_VER=3.1.1
NIM_VER=2.2.8
ALL_PLATFORMS="tg5040 tg5050 my355"

# Last arg is build type if it's debug/release, otherwise default to debug
BUILD_TYPE=debug
PLATFORMS=""
for arg in "$@"; do
  case "$arg" in
    debug|release) BUILD_TYPE=$arg ;;
    *) PLATFORMS="$PLATFORMS $arg" ;;
  esac
done
PLATFORMS=$(echo $PLATFORMS)
if [ -z "$PLATFORMS" ]; then
  PLATFORMS="host"
fi

SOURCE=${SOURCE:-cheat_manager.nim}
OUTPUT=$(basename "$SOURCE" .nim)

NIM_FLAGS="--threads:off -d:minizDir=workspace/miniz-${MINIZ_VER} --passC:-Iworkspace/miniz-${MINIZ_VER} -p:workspace/nim-${NIM_VER}/pkgs/db_connector/src"
if [ "$BUILD_TYPE" = "release" ]; then
  NIM_FLAGS="$NIM_FLAGS -d:release -d:strip --opt:size -d:lto --passC:-fno-strict-aliasing --passL:-fno-strict-aliasing --passL:-Wno-lto-type-mismatch"
fi
NIM_FLAGS="$NIM_FLAGS ${EXTRA_NIM_FLAGS:-}"

# Use the host-native Nim on macOS; fall back to the Linux x64 one on Linux.
HOST_NIM="workspace/nim-${NIM_VER}/bin/nim"
if [ "$(uname -s)" = "Darwin" ] && [ -f "workspace/nim-${NIM_VER}-host/bin/nim" ]; then
  HOST_NIM="workspace/nim-${NIM_VER}-host/bin/nim"
fi

echorun () {
  echo "$@"
  "$@"
}

# Resolve platforms
TARGETS=""
NEED_DOCKER=false
for P in $PLATFORMS; do
  case "$P" in
    host) TARGETS="$TARGETS host" ;;
    all) TARGETS="$TARGETS $ALL_PLATFORMS"; NEED_DOCKER=true ;;
    *) TARGETS="$TARGETS $P"; NEED_DOCKER=true ;;
  esac
done
TARGETS=$(echo $TARGETS)

if $NEED_DOCKER; then
  cp *.nim *.c workspace/
fi

for platform in $TARGETS; do
  echo "Building $platform $BUILD_TYPE"

  if [ "$platform" = "host" ]; then
    HOST_NIM_FLAGS="$NIM_FLAGS"
    # Apostrophe (see apostrophe.nim) requires SDL2/SDL2_ttf/SDL2_image on
    # whatever machine builds cheat_manager, including host dev builds —
    # see README.md for how to install them locally.
    for flag in $(pkg-config --cflags sdl2 SDL2_ttf SDL2_image 2>/dev/null); do
      HOST_NIM_FLAGS="$HOST_NIM_FLAGS --passC:$flag"
    done
    for flag in $(pkg-config --libs sdl2 SDL2_ttf SDL2_image 2>/dev/null); do
      HOST_NIM_FLAGS="$HOST_NIM_FLAGS --passL:$flag"
    done
    echorun $HOST_NIM c $HOST_NIM_FLAGS --nimcache:nimcache -o:$OUTPUT $SOURCE
  else
    # apostrophe.h/apostrophe_widgets.h branch on these to know which device
    # they're building for (screen size, input mapping, etc.) — see
    # "Platform Detection" in Apostrophe's apostrophe.h.
    case "$platform" in
      tg5040) PLATFORM_CFLAGS="-DPLATFORM_TG5040 -mcpu=cortex-a53 -mtune=cortex-a53" ;;
      tg5050) PLATFORM_CFLAGS="-DPLATFORM_TG5050 -mcpu=cortex-a55 -mtune=cortex-a55" ;;
      my355)  PLATFORM_CFLAGS="-DPLATFORM_MY355 -mcpu=cortex-a55 -mtune=cortex-a55" ;;
      *)      PLATFORM_CFLAGS="" ;;
    esac

    BUILD_SCRIPT=workspace/buildbin.sh
    NIMCACHE=nimcache
    rm -f $BUILD_SCRIPT

    cat > $BUILD_SCRIPT <<EOF
set -e
# clean cache to let different platforms build on the same workspace
if [ ! -f $NIMCACHE/$platform ]; then rm -rf $NIMCACHE; fi
if [ ! -d $NIMCACHE ]; then mkdir $NIMCACHE; fi
touch $NIMCACHE/$platform

# The Docker toolchain sysroots ship sdl2.pc but not SDL2_ttf.pc/SDL2_image.pc
# (the .so stubs exist, just not the pkg-config metadata) — same situation
# Apostrophe's own ports/*/Makefile works around, so we do the same here.
SDL_CFLAGS=\$(pkg-config --cflags sdl2)
SDL_LDFLAGS="\$(pkg-config --libs sdl2) -lSDL2_ttf -lSDL2_image"

NIM_C_FLAGS="$NIM_FLAGS"
for flag in \$SDL_CFLAGS $PLATFORM_CFLAGS; do
  NIM_C_FLAGS="\$NIM_C_FLAGS --passC:\$flag"
done
for flag in \$SDL_LDFLAGS; do
  NIM_C_FLAGS="\$NIM_C_FLAGS --passL:\$flag"
done

nim-${NIM_VER}/bin/nim c --cpu:arm64 --os:linux --nimcache:$NIMCACHE \\
  --arm64.linux.gcc.exe:\${CROSS_ROOT}/bin/\${CROSS_COMPILE}gcc \\
  --arm64.linux.gcc.linkerexe:\${CROSS_ROOT}/bin/\${CROSS_COMPILE}gcc \\
  \$NIM_C_FLAGS -o:$OUTPUT $SOURCE
EOF

    docker run -v "$(pwd)/workspace/:/root/workspace" --rm "ghcr.io/loveretro/${platform}-toolchain" /bin/sh $BUILD_SCRIPT

    cp workspace/$OUTPUT workspace/${OUTPUT}-${platform}
  fi
done
