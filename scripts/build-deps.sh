#!/bin/sh
# Build all pinned third-party dependencies (deps.json) from source into
# .deps/, natively inside an OpenHarmony container.
#
#   ./scripts/build-deps.sh [--jobs N]
#
# The result is a self-contained dependency prefix; nothing from Harmonybrew
# gets linked into the final Python distribution. All intermediate files
# stay inside the repo (.build/, .deps/).
set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd)
JOBS=$(nproc 2>/dev/null || echo 4)
while [ $# -gt 0 ]; do
    case "$1" in
        --jobs) JOBS=$2; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

# deps.json is read with sed rather than python3: the container has no Python
# yet (that is what is being built). See build.sh for the same convention.
json_val() { sed -n "s/.*\"$2\": *\"\([^\"]*\)\".*/\1/p" "$1" | head -n 1; }

DEPS_PREFIX=$REPO/.deps
CACHE=${DEPS_CACHE:-$REPO/.build/deps-cache}
WORK=$REPO/.build/deps
mkdir -p "$CACHE" "$WORK"

export CFLAGS="-fPIC -O2"
export CPPFLAGS="-I$DEPS_PREFIX/include"
export LDFLAGS="-L$DEPS_PREFIX/lib"
export LD_LIBRARY_PATH="$DEPS_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig"

fetch() {  # fetch <name> -> cd into extracted source dir
    block=$(sed -n "/\"name\": \"$1\"/,/sha256/p" "$REPO/deps.json")
    # first URL is canonical; "fallback_urls" (optional) are mirrors with the
    # identical file (same sha256), for networks that cannot reach the origin
    urls=$(echo "$block" | grep -oE '"https?://[^"]+"' | tr -d '"')
    url=$(echo "$urls" | head -1)
    fallbacks=$(echo "$urls" | tail -n +2)
    sha=$(echo "$block" | sed -n 's/.*"sha256": *"\([^"]*\)".*/\1/p')
    ver=$(echo "$block" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')
    tarball=$CACHE/${url##*/}
    if [ ! -f "$tarball" ]; then
        echo "--- download $1-$ver"
        curl -fL --retry 2 --connect-timeout 20 -sS -o "$tarball" "$url" || {
            for fb in $fallbacks; do
                echo "--- retry from mirror: $fb"
                curl -fL --retry 3 -sS -o "$tarball" "$fb" && break
            done
        }
    fi
    echo "$sha  $tarball" | sha256sum -c - >/dev/null
    cd "$WORK"
    rm -rf "$1-src"
    mkdir "$1-src"
    tar -C "$1-src" --strip-components=1 -xf "$tarball"
    cd "$1-src"
    echo "--- build $1-$ver"
}

build_openssl() {
    # Point the default certificate paths at the locations used on OpenHarmony.
    sed -i 's|OPENSSLDIR "/certs"|"/etc/ssl/certs"|' include/internal/common.h
    sed -i 's|OPENSSLDIR "/cert.pem"|"/etc/ssl/certs/cacert.pem"|' include/internal/common.h
    ./Configure --prefix="$DEPS_PREFIX" --openssldir=/etc/ssl linux-aarch64
    make -j"$JOBS"
    make install_dev
}

build_zlib() {
    ./configure --prefix="$DEPS_PREFIX"
    make -j"$JOBS"
    make install
}

build_libffi() {
    echo "apply libffi-ohos-trampoline.patch"
    patch -p1 -i "$REPO/patches/libffi-ohos-trampoline.patch"
    ./configure --prefix="$DEPS_PREFIX"
    make -j"$JOBS"
    make install
}

build_util_linux() {
    ./configure \
        --prefix="$DEPS_PREFIX" \
        --disable-all-programs \
        --enable-libuuid \
        --disable-gtk-doc \
        --disable-nls
    make -j"$JOBS"
    make install
}

build_xz() {
    ./configure --prefix="$DEPS_PREFIX"
    make -j"$JOBS"
    make install
}

build_bzip2() {
    make -j"$JOBS" -f Makefile-libbz2_so
    cp libbz2.so.1.0.8 "$DEPS_PREFIX/lib"
    cp bzlib.h "$DEPS_PREFIX/include"
    cd "$DEPS_PREFIX/lib"
    ln -sf libbz2.so.1.0.8 libbz2.so.1.0
    ln -sf libbz2.so.1.0.8 libbz2.so.1
    ln -sf libbz2.so.1.0.8 libbz2.so
}

build_zstd() {
    # zstd's thread pool assumes a POSIX barrier API that the OHOS libc does
    # not provide; the code already has a fallback used for Android.
    sed -i 's@!defined(__ANDROID__)@!defined(__ANDROID__) \&\& !defined(__OHOS__)@g' \
        lib/common/zstd_deps.h lib/dictBuilder/cover.c
    make -j"$JOBS"
    make install PREFIX="$DEPS_PREFIX"
}

build_ncurses() {
    ./configure \
        --prefix="$DEPS_PREFIX" \
        --enable-termcap \
        --enable-widec \
        --with-shared \
        --with-terminfo-dirs=/system/usr/share/terminfo:/usr/share/terminfo:/etc/terminfo \
        --with-fallbacks=xterm,xterm-256color,xterm-color,screen,screen-256color,tmux,tmux-256color,linux,vt100,vt102,ansi
    # a failed MKfallback.sh run leaves an empty fallback.c behind that make
    # then considers "up to date"; force regeneration
    rm -f ncurses/fallback.c
    # keep the in-progress target libs out of LD_LIBRARY_PATH: build-host
    # tools (brew tic/infocmp, used to generate fallback.c) would otherwise
    # pick up the half-built libncursesw from .deps/lib and fail to run
    env -u LD_LIBRARY_PATH make -j"$JOBS"
    make install
    cp "$DEPS_PREFIX"/include/ncursesw/*.h "$DEPS_PREFIX/include"
}

build_readline() {
    ./configure --prefix="$DEPS_PREFIX" --with-curses
    make -j"$JOBS" SHLIB_LIBS="-lncursesw"
    make install
}

build_sqlite() {
    ./configure --prefix="$DEPS_PREFIX" --disable-readline
    make -j"$JOBS"
    make install
}

for dep in openssl zlib libffi util-linux xz bzip2 zstd ncurses readline sqlite; do
    fetch "$dep"
    func=$(echo "build_$dep" | tr - _)
    "$func"
done

echo
echo "=== all dependencies installed into $DEPS_PREFIX ==="
ls "$DEPS_PREFIX/lib" | head -30
