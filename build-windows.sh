#!/usr/bin/env bash

set -eu

cd $(dirname $0)
BASE_DIR=$(pwd)

source common.sh

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

FFMPEG_CONFIGURE_FLAGS+=(
    --cc=gcc
    --prefix=$BASE_DIR/$OUTPUT_DIR
    --extra-cflags='-static -static-libgcc -static-libstdc++ -I/usr/local/include'
    --extra-ldflags='-L/usr/local/lib'
    --target-os=mingw32
    --arch=$ARCH
    --cross-prefix=$ARCH-w64-mingw32-
)
echo "${FFMPEG_CONFIGURE_FLAGS[@]}"

./configure "${FFMPEG_CONFIGURE_FLAGS[@]}"
make
make install
chown $(stat -c '%u:%g' $BASE_DIR) -R $BASE_DIR/$OUTPUT_DIR
