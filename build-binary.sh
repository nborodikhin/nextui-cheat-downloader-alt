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

NIM_FLAGS="--threads:off -d:minizDir=workspace/miniz-${MINIZ_VER} --passC:-Iworkspace/miniz-${MINIZ_VER} -p:nim-${NIM_VER}/pkgs/db_connector/src"
if [ "$BUILD_TYPE" = "release" ]; then
  NIM_FLAGS="$NIM_FLAGS -d:release -d:strip --opt:size -d:lto --passC:-fno-strict-aliasing --passL:-fno-strict-aliasing --passL:-Wno-lto-type-mismatch"
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
  cp *.nim workspace/
fi

for platform in $TARGETS; do
  echo "Building $platform $BUILD_TYPE"

  if [ "$platform" = "host" ]; then
    echorun nim c $NIM_FLAGS -o:cheat_manager cheat_manager.nim
  else
    BUILD_SCRIPT=workspace/buildbin.sh
    NIMCACHE=nimcache
    rm -f $BUILD_SCRIPT

    # clean cache to let different platforms build on the same workspace
    echo "if [ ! -f $NIMCACHE/$platform ]; then rm -rf $NIMCACHE; fi" >> $BUILD_SCRIPT
    echo "if [ ! -d $NIMCACHE ]; then mkdir $NIMCACHE; fi" >> $BUILD_SCRIPT
    echo "touch $NIMCACHE/$platform" >> $BUILD_SCRIPT

    echo "nim-${NIM_VER}/bin/nim c --cpu:arm64 --os:linux --nimcache:$NIMCACHE --arm64.linux.gcc.exe:\${CROSS_ROOT}/bin/\${CROSS_COMPILE}gcc --arm64.linux.gcc.linkerexe:\${CROSS_ROOT}/bin/\${CROSS_COMPILE}gcc ${NIM_FLAGS} -o:cheat_manager cheat_manager.nim || exit" >> $BUILD_SCRIPT

    docker run -it -v "$(pwd)/workspace/:/root/workspace" --rm "ghcr.io/loveretro/${platform}-toolchain" /bin/sh $BUILD_SCRIPT

    mkdir -p deps
    cp workspace/cheat_manager workspace/cheat_manager-${platform}
  fi
done
