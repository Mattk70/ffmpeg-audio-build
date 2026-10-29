#!/usr/bin/env bash
set -euxo pipefail

# Make sure the MSYS2 UCRT64 toolchain is first on PATH
export PATH="/ucrt64/bin:$PATH"
echo "==> PATH=$PATH"

echo "==> checking required tools"
required="cmp make gcc pkg-config nasm ar curl tar"
for cmd in $required; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' not found in PATH." >&2
    exit 1
  fi
done

cd "$(dirname "$0")"
BASE_DIR=$(pwd)

source common.sh
: ${ARCH?}

LAME_VERSION=3.100
MPG123_VERSION=1.32.10
LAME_URL="https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz"
MPG123_URL="https://downloads.sourceforge.net/project/mpg123/mpg123/${MPG123_VERSION}/mpg123-${MPG123_VERSION}.tar.bz2"

# Static dependencies get installed here (cacheable between CI runs)
DEPS_PREFIX="$BASE_DIR/deps/$ARCH"
mkdir -p "$DEPS_PREFIX"

export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:/ucrt64/lib/pkgconfig:/ucrt64/share/pkgconfig"

# ---------------------------------------------------------------------------
# Static libmp3lame
# ---------------------------------------------------------------------------
if [ ! -f "$DEPS_PREFIX/lib/libmp3lame.a" ]; then
  echo "==> building static LAME $LAME_VERSION"
  DEP_BUILD=$(mktemp -d -p "$BASE_DIR" lame.XXXXXXXX)
  (
    cd "$DEP_BUILD"
    curl -fsSL -o lame.tar.gz "$LAME_URL"
    tar --strip-components=1 -xzf lame.tar.gz

    # Known MinGW issue with LAME 3.100: exported-symbol list references a
    # function that doesn't exist, which breaks linking.
    sed -i.bak '/lame_init_old/d' include/libmp3lame.sym

    ./configure \
      --prefix="$DEPS_PREFIX" \
      --enable-static \
      --disable-shared \
      --disable-frontend \
      --disable-gtktest
    make -j"$(nproc)"
    make install
  )
  rm -rf "$DEP_BUILD"
fi
test -f "$DEPS_PREFIX/lib/libmp3lame.a"

# ---------------------------------------------------------------------------
# Static libmpg123
# ---------------------------------------------------------------------------
if [ ! -f "$DEPS_PREFIX/lib/libmpg123.a" ]; then
  echo "==> building static mpg123 $MPG123_VERSION"
  DEP_BUILD=$(mktemp -d -p "$BASE_DIR" mpg123.XXXXXXXX)
  (
    cd "$DEP_BUILD"
    curl -fsSL -o mpg123.tar.bz2 "$MPG123_URL"
    tar --strip-components=1 -xjf mpg123.tar.bz2

    # Only the library is needed, not the player/output modules.
    ./configure \
      --prefix="$DEPS_PREFIX" \
      --enable-static \
      --disable-shared \
      --disable-components \
      --enable-libmpg123
    make -j"$(nproc)"
    make install
  )
  rm -rf "$DEP_BUILD"
fi
test -f "$DEPS_PREFIX/lib/libmpg123.a"

pkg-config --static --libs --cflags libmpg123

# ---------------------------------------------------------------------------
# FFmpeg
# ---------------------------------------------------------------------------
echo "==> downloading FFmpeg tarball"
if [ ! -e "$FFMPEG_TARBALL" ]; then
  curl -s -L -O "$FFMPEG_TARBALL_URL"
fi

OUTPUT_DIR=artifacts/ffmpeg-$FFMPEG_VERSION-audio-$ARCH-w64-mingw32

BUILD_DIR=$(mktemp -d -p "$BASE_DIR" build.XXXXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT

cd "$BUILD_DIR"
tar --strip-components=1 -xf "$BASE_DIR/$FFMPEG_TARBALL"

# Building natively inside the MSYS2 UCRT64 shell, so no cross prefix/tool
# overrides are needed: gcc, ar, nm, etc. come straight from /ucrt64/bin.
FFMPEG_CONFIGURE_FLAGS+=(
    --prefix="$BASE_DIR/$OUTPUT_DIR"
    --pkg-config-flags=--static
    --extra-cflags="-I$DEPS_PREFIX/include"
    --extra-ldflags="-static -static-libgcc -static-libstdc++ -L$DEPS_PREFIX/lib"
    --target-os=mingw32
    --arch="$ARCH"
)
echo "${FFMPEG_CONFIGURE_FLAGS[@]}"

./configure "${FFMPEG_CONFIGURE_FLAGS[@]}" || (cat ffbuild/config.log && exit 1)

make -j"$(nproc)"
make install

exe="$BASE_DIR/$OUTPUT_DIR/bin/ffmpeg.exe"
test -f "$exe" || { echo "Missing $exe" >&2; exit 1; }
ldd "$exe"

chown "$(stat -c '%u:%g' "$BASE_DIR")" -R "$BASE_DIR/$OUTPUT_DIR"