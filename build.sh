#!/bin/sh
# Build CPython for OpenHarmony (aarch64-unknown-linux-ohos) inside a
# DockerHarmony container.
#
#   ./build.sh [version[+freethreaded] ...] [--tag YYYYMMDD] [--jobs N] [--skip-deps] [--rebuild-deps]
#
# With no version argument, every version in versions.json is built in one
# run, plus free-threaded builds for 3.14 and 3.15. Third-party dependencies
# compile once into .deps/ and are shared by all versions and variants.
# An explicit version builds only that variant; use +freethreaded for a t build.
#
# The ohos-sdk toolchain is installed with Harmonybrew's devel-base package.
# Its clang/lld wrapper signs linked binaries. devel-base also supplies GNU
# make/coreutils.
# Third-party dependencies are compiled from pinned sources (deps.json) into
# .deps/ by scripts/build-deps.sh — nothing is cross-compiled, and no
# prebuilt brew library ends up in the distribution. All intermediate files
# stay inside the repo (.build/, .deps/, dist/).
set -eu

REPO=$(cd "$(dirname "$0")" && pwd)

VERSIONS=""
TAG=$(date +%Y%m%d)
JOBS=$(nproc 2>/dev/null || echo 4)
SKIP_DEPS=0
REBUILD_DEPS=0

while [ $# -gt 0 ]; do
    case "$1" in
        --tag)      TAG=$2; shift 2 ;;
        --jobs)     JOBS=$2; shift 2 ;;
        --skip-deps) SKIP_DEPS=1; shift ;;
        --rebuild-deps) REBUILD_DEPS=1; shift ;;
        -*)         echo "unknown option: $1" >&2; exit 2 ;;
        *)          VERSIONS="$VERSIONS $1"; shift ;;
    esac
done

# Default: build every version listed in versions.json, in order, and add
# free-threaded variants where supported. The build container has no Python
# yet, so the JSON manifest is read with plain sed instead of python3.
if [ -z "$VERSIONS" ]; then
    while IFS= read -r V; do
        VERSIONS="$VERSIONS $V"
        case "$V" in
            3.14.*|3.15.*) VERSIONS="$VERSIONS $V+freethreaded" ;;
        esac
    done <<EOF
$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$REPO/versions.json")
EOF
fi

DIST=$REPO/dist

# Everything the build produces lives inside the repo: .deps/ holds the
# self-contained dependency prefix, .build/ the per-version work trees.
DEPS_PREFIX=$REPO/.deps

log() { printf '\n=== %s ===\n' "$*"; }

log "bootstrap build environment (Harmonybrew + devel-base)"
# Toolchain setup is idempotent and also prepares the container's deviceinfo
# library when the mini rootfs does not provide the real one.
BREW=/storage/Users/currentUser/.harmonybrew/bin/brew
"$REPO/scripts/setup-env.sh"
eval "$("$BREW" shellenv)"

log "configure OpenHarmony API level (compiler SDK detection)"

if [ "$SKIP_DEPS" = 0 ] && { [ "$REBUILD_DEPS" = 1 ] || [ ! -d "$DEPS_PREFIX/lib" ]; }; then
    log "build pinned dependencies from source"
    "$REPO/scripts/build-deps.sh" --jobs "$JOBS"
fi

DEP_INCLUDE="-I$DEPS_PREFIX/include"
DEP_LIB="-L$DEPS_PREFIX/lib"
DEP_PKGCONFIG="$DEPS_PREFIX/lib/pkgconfig"
# configure's run-time probes (getaddrinfo etc.) and the freshly built
# python binary (freeze/compileall) must be able to load these libraries.
export LD_LIBRARY_PATH="$DEPS_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# $ORIGIN-relative rpaths keep the installed tree relocatable without
# patchelf (which would invalidate the OHOS code signature that the brew
# lld wrapper applies at link time).
#
# Quoting: the value lands in the generated Makefile and is used in recipes
# through several variable indirections. Single quotes + '$$' is the one
# combination that survives make expansion and the recipe shell intact
# (verified empirically on the generated Makefile): make reduces '$$' to
# '$', the recipe shell then keeps '$ORIGIN' literal thanks to the quotes.
# Same approach as Harmonybrew/ohos-python.
RPATH_BIN="-Wl,-rpath,'\$\$ORIGIN/../lib'"
RPATH_LIB="-Wl,-rpath,'\$\$ORIGIN'"
RPATH_DYNLOAD="-Wl,-rpath,'\$\$ORIGIN/../../../lib'"
# Some link recipes pass the linker command through extra shell layers
# (environment assignments in recipes); each layer re-expands $ORIGIN.
# Exporting ORIGIN='$ORIGIN' makes that expansion idempotent, so the rpath
# survives every round-trip intact.
export ORIGIN='$ORIGIN'

build_one() {
    REQUEST=$1
    VERSION=${REQUEST%+freethreaded}
    VARIANT=default
    if [ "$VERSION" != "$REQUEST" ]; then
        VARIANT=freethreaded
        case "$VERSION" in
            3.14.*|3.15.*) ;;
            *) echo "free-threaded builds are supported only for 3.14 and 3.15: $VERSION" >&2; return 1 ;;
        esac
    fi
    SERIES=$(echo "$VERSION" | cut -d. -f1-2)
    WORK=$REPO/.build/$VERSION
    [ "$VARIANT" = freethreaded ] && WORK=$REPO/.build/$VERSION-freethreaded
    SRC=$WORK/Python-$VERSION
    STAGE=$WORK/stage

    block=$(sed -n "/\"version\": \"$VERSION\"/,/sha256/p" "$REPO/versions.json")
    URL=$(echo "$block" | sed -n 's/.*"url": *"\([^"]*\)".*/\1/p')
    SHA256=$(echo "$block" | sed -n 's/.*"sha256": *"\([^"]*\)".*/\1/p')
    if [ -z "$URL" ] || [ -z "$SHA256" ]; then
        echo "version $VERSION not listed in versions.json" >&2
        return 1
    fi

    log "[$REQUEST] download"
    mkdir -p "$WORK" "$DIST"
    TARBALL=$WORK/Python-$VERSION.tgz
    if [ ! -f "$TARBALL" ]; then
        curl -fL --retry 3 -o "$TARBALL" "$URL"
    fi
    echo "$SHA256  $TARBALL" | sha256sum -c -

    log "[$REQUEST] extract and patch"
    rm -rf "$SRC" "$STAGE"
    tar -C "$WORK" -xf "$TARBALL"
    cd "$SRC"
    # Each series directory is self-contained (no shared common directory):
    # when a new series appears, copy the nearest series directory and adjust
    # the patches; patches of older series are never affected by new ones.
    for p in "$REPO"/patches/"$SERIES"/*.patch; do
        echo "apply $(basename "$p")"
        patch -p1 -F0 < "$p"
    done

    log "[$REQUEST] regenerate configure"
    # CPython does not use automake; run the autoconf tools directly instead
    # of `autoreconf -i`, which would otherwise replace our patched
    # config.guess/config.sub with automake's bundled copies.
    # pkg.m4 comes from brew's pkgconf, AX_* macros from autoconf-archive.
    BREW_PREFIX=$(brew --prefix)
    export ACLOCAL_PATH="$BREW_PREFIX/share/aclocal${ACLOCAL_PATH:+:$ACLOCAL_PATH}"
    rm -rf autom4te.cache
    aclocal --force
    autoconf --force
    autoheader --force

    log "[$REQUEST] configure"
    # config.guess uses __OHOS__ to identify the target, while
    # configure.ac derives ac_sys_system=Linux-ohos from the detected host triple.
    #
    # -D__MUSL__: the OHOS libc is musl-derived but the SDK clang does not
    # define __MUSL__ itself. Defining it activates the libc-compat guards in
    # the sysroot's linux/*.h kernel headers, so e.g. linux/netfilter_ipv4.h
    # (pulled in by socketmodule.h) no longer redefines sockaddr_storage. It
    # goes into CFLAGS (not CPPFLAGS) so it propagates to extension builds
    # through _sysconfigdata.
    CONFIGURE_FLAGS=
    [ "$VARIANT" = freethreaded ] && CONFIGURE_FLAGS=--disable-gil
    ./configure \
        --prefix=/install \
        --enable-shared \
        --with-openssl="$DEPS_PREFIX" \
        $CONFIGURE_FLAGS \
        CPPFLAGS="$DEP_INCLUDE" \
        CFLAGS="-D__MUSL__ -fno-emulated-tls" \
        LDFLAGS="$DEP_LIB -Wl,-z,global $RPATH_BIN $RPATH_LIB $RPATH_DYNLOAD" \
        PKG_CONFIG_PATH="$DEP_PKGCONFIG"

    log "[$REQUEST] make -j$JOBS"
    make -j"$JOBS"

    log "[$REQUEST] make install"
    make install DESTDIR="$STAGE"

    log "[$REQUEST] package"
    "$REPO/scripts/package.sh" "$VERSION" "$TAG" "$STAGE" "$DIST" "$VARIANT"

    log "[$REQUEST] smoke test"
    PY=$STAGE/install/bin/python${VERSION%.*}
    [ "$VARIANT" = freethreaded ] && PY=${PY}t
    "$REPO/scripts/smoke-test.sh" "$PY" "$VARIANT"

    cd "$REPO"
}

for V in $VERSIONS; do
    build_one "$V"
done

echo
echo "artifacts:"
ls "$DIST"/cpython-*.tar.gz
