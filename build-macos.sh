#!/usr/bin/env bash

set -eux

cd $(dirname $0)
BASE_DIR=$(pwd)

source common.sh

if [ ! -e $FFMPEG_TARBALL ]
then
	curl -s -L -O $FFMPEG_TARBALL_URL
fi

: ${TARGET?}

case $TARGET in
    x86_64-*)
        ARCH="x86_64"
        ;;
    arm64-*)
        ARCH="arm64"
        ;;
    *)
        echo "Unknown target: $TARGET"
        exit 1
        ;;
esac

OUTPUT_DIR=artifacts/ffmpeg-$FFMPEG_VERSION-audio-$TARGET

BUILD_DIR=$BASE_DIR/$(mktemp -d build.XXXXXXXX)
trap 'rm -rf $BUILD_DIR' EXIT

cd $BUILD_DIR
tar --strip-components=1 -xf $BASE_DIR/$FFMPEG_TARBALL

LAME_PREFIX="$RUNNER_TEMP/lame-install"


export PKG_CONFIG_PATH="\
$LAME_PREFIX/lib/pkgconfig:\
$MPG123_PREFIX/lib/pkgconfig:\
$OPUS_PREFIX/lib/pkgconfig:\
$VORBIS_PREFIX/lib/pkgconfig:\
$OGG_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
INSTALL_PREFIX="$BASE_DIR/$OUTPUT_DIR""

FFMPEG_CONFIGURE_FLAGS+=(
  "--prefix=$INSTALL_PREFIX"
  "--libdir=$INSTALL_PREFIX/lib"
  "--extra-cflags=-I$LAME_PREFIX/include -I$MPG123_PREFIX/include -I$OPUS_PREFIX/include -I$VORBIS_PREFIX/include -I$OGG_PREFIX/include -I/opt/homebrew/include -target $TARGET"
  "--extra-ldflags=-L$LAME_PREFIX/lib -L$MPG123_PREFIX/lib -L$OPUS_PREFIX/lib -L$VORBIS_PREFIX/lib -L$OGG_PREFIX/lib -L/opt/homebrew/lib -target $TARGET"
  --extra-libs=-lmpg123
)

cat > "$BUILD_DIR/lame-probe.c" <<'EOF'
#include <lame/lame.h>
int main(void) {
    lame_t lame = lame_init();
    return lame == 0;
}
EOF

/usr/bin/clang -target "$TARGET" \
  -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
  -I"$LAME_PREFIX/include" \
  -I"$MPG123_PREFIX/include" \
  "$BUILD_DIR/lame-probe.c" \
  "$LAME_PREFIX/lib/libmp3lame.a" \
  "$MPG123_PREFIX/lib/libmpg123.a" \
  -o "$BUILD_DIR/lame-probe"

./configure "${FFMPEG_CONFIGURE_FLAGS[@]}" || (cat ffbuild/config.log && exit 1)

perl -pi -e 's{HAVE_MACH_MACH_TIME_H 1}{HAVE_MACH_MACH_TIME_H 0}' config.h

make V=8
make install

exe="$BASE_DIR/$OUTPUT_DIR/bin/ffmpeg"
test -f "$exe" || { echo "Missing $exe" >&2; exit 1; }
otool -L "$exe"
chown -R $(stat -f '%u:%g' $BASE_DIR) $BASE_DIR/$OUTPUT_DIR
