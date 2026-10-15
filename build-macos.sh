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

LAME_PREFIX=/opt/homebrew/Cellar/lame/4.0

printf 'TARGET=%s\nARCH=%s\n' "$TARGET" "$ARCH"
/usr/bin/clang -target "$TARGET" -print-target-triple

cat > /tmp/lame-probe.c <<'EOF'
#include <lame/lame.h>
int main(void) {
    lame_t lame = lame_init();
    return lame == 0;
}
EOF

/usr/bin/clang -target "$TARGET" \
  -I"$LAME_PREFIX/include" \
  /tmp/lame-probe.c "$LAME_PREFIX/lib/libmp3lame.a" \
  -o /tmp/lame-probe

  
FFMPEG_CONFIGURE_FLAGS+=(
    --cc=/usr/bin/clang
    --prefix=$BASE_DIR/$OUTPUT_DIR
    --enable-cross-compile
    --target-os=darwin
    --arch=$ARCH
    --extra-ldflags="-L/opt/homebrew/lib -target $TARGET -L$LAME_PREFIX/lib -target $TARGET"
    --extra-cflags="-static -static-libgcc -static-libstdc++ -I/opt/homebrew/include -target $TARGET -I$LAME_PREFIX/include -target $TARGET"
)


mv "$LAME_PREFIX/lib/libmp3lame.dylib" "$LAME_PREFIX/lib/libmp3lame.dylib.disabled"
mv "$LAME_PREFIX/lib/libmp3lame.0.dylib" "$LAME_PREFIX/lib/libmp3lame.0.dylib.disabled"
# Run FFmpeg configure and make here.

./configure "${FFMPEG_CONFIGURE_FLAGS[@]}" || (cat ffbuild/config.log && exit 1)

perl -pi -e 's{HAVE_MACH_MACH_TIME_H 1}{HAVE_MACH_MACH_TIME_H 0}' config.h

make V=8
make install
mv "$LAME_PREFIX/lib/libmp3lame.0.dylib.disabled" "$LAME_PREFIX/lib/libmp3lame.0.dylib"
mv "$LAME_PREFIX/lib/libmp3lame.dylib.disabled" "$LAME_PREFIX/lib/libmp3lame.dylib"
exe="$BASE_DIR/$OUTPUT_DIR/bin/ffmpeg"
test -f "$exe" || { echo "Missing $exe" >&2; exit 1; }
otool -L "$exe"
chown -R $(stat -f '%u:%g' $BASE_DIR) $BASE_DIR/$OUTPUT_DIR
