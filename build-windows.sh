#!/usr/bin/env bash
set -euxo pipefail


# ensure mingw-ucrt bin is first so mingw tools are found
export PATH="/ucrt64/bin:/ucrt64/x86_64-w64-mingw32/bin:$PATH"
echo "==> PATH=$PATH"
echo "==> checking required tools"
# required commands
required="cmp make gcc pkg-config nasm ar"
for cmd in $required; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' not found in PATH." >&2
    echo "Current PATH: $PATH" >&2
    exit 1
  fi
done


set -eu

cd $(dirname $0)
BASE_DIR=$(pwd)

source common.sh
echo "==> downloading FFmpeg tarball"
if [ ! -e $FFMPEG_TARBALL ]
then
	curl -s -L -O $FFMPEG_TARBALL_URL
fi

: ${ARCH?}

OUTPUT_DIR=artifacts/ffmpeg-$FFMPEG_VERSION-audio-$ARCH-w64-mingw32

BUILD_DIR=$(mktemp -d -p $(pwd) build.XXXXXXXX)
trap 'rm -rf $BUILD_DIR' EXIT

cd $BUILD_DIR
tar --strip-components=1 -xf $BASE_DIR/$FFMPEG_TARBALL

# Set cross-compilation flags for MinGW
export CC=x86_64-w64-mingw32-gcc
export CXX=x86_64-w64-mingw32-g++
export AR=x86_64-w64-mingw32-ar
export RANLIB=x86_64-w64-mingw32-ranlib

which nm
# which nasm

# ls /ucrt64/lib/libmp3*
# ls /ucrt64/include/lame
echo ${PATH}


FFMPEG_CONFIGURE_FLAGS+=(
    --nm=/ucrt64/bin/nm.exe
    --ar=/ucrt64/x86_64-w64-mingw32/bin/ar.exe
    --strip=/ucrt64/x86_64-w64-mingw32/bin/strip.exe
    --prefix=$BASE_DIR/$OUTPUT_DIR
    --extra-cflags='-I/ucrt64/include'
    # --extra-cflags='-static -static-libgcc -static-libstdc++ -I/c/ucrt64/include'
    --extra-ldflags='-static -static-libgcc -static-libstdc++ -L/ucrt64/lib'
    --target-os=mingw32
    --arch=$ARCH
    --cross-prefix=$ARCH-w64-mingw32-
)
echo "${FFMPEG_CONFIGURE_FLAGS[@]}"

./configure "${FFMPEG_CONFIGURE_FLAGS[@]}"  || (cat ffbuild/config.log && exit 1)

make -j$(nproc)
make install

exe="$BASE_DIR/$OUTPUT_DIR/bin/ffmpeg.exe"
test -f "$exe" || { echo "Missing $exe" >&2; exit 1; }
ldd "$exe"

chown $(stat -c '%u:%g' $BASE_DIR) -R $BASE_DIR/$OUTPUT_DIR
