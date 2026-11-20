#!/bin/sh
# Package a staged CPython install (DESTDIR layout) into a relocatable,
# self-contained tarball following the python-build-standalone install_only
# conventions:
#
#   cpython-<version>+<tag>-aarch64-unknown-linux-ohos-install_only.tar.gz
#   └── python/          (bin/, lib/, include/, share/, licenses/)
#
# Third-party shared libraries from .deps/ (compiled from pinned sources
# by scripts/build-deps.sh) are bundled into python/lib/ so the result runs
# on a bare OpenHarmony system without anything else installed.
set -eu

VERSION=$1
TAG=$2
STAGE=$3
DIST=$4
VARIANT=${5:-default}

TRIPLE=aarch64-unknown-linux-ohos
SERIES=${VERSION%.*}
PKGDIR=$(dirname "$STAGE")/package
PYROOT=$PKGDIR/python
REPO=$(cd "$(dirname "$0")/.." && pwd)
DEPS_PREFIX=$REPO/.deps

rm -rf "$PKGDIR"
mkdir -p "$PYROOT" "$DIST"

# --- install prefix ---------------------------------------------------------
cp -a "$STAGE/install/." "$PYROOT/"

# Slim down to install_only semantics: no test suite, no IDE bits, no static
# libpython.
rm -rf "$PYROOT/lib/python$SERIES/test" \
       "$PYROOT/lib/python$SERIES/idlelib" \
       "$PYROOT/lib/python$SERIES/tkinter" \
       "$PYROOT/lib/python$SERIES/turtledemo" \
       "$PYROOT/lib/python$SERIES/turtle.py"
find "$PYROOT" -name 'libpython*.a' -delete

# --- bundle third-party shared libraries ------------------------------------
readelf=$(command -v llvm-readelf || command -v readelf)

needed_of() {
    "$readelf" -d "$1" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'
}

find_dep() {
    for d in "$DEPS_PREFIX/lib" "$DEPS_PREFIX/lib64"; do
        [ -f "$d/$1" ] && { echo "$d/$1"; return 0; }
    done
    return 1
}

queue=$(find "$PYROOT" -type f \( -name '*.so' -o -name '*.so.*' \) ; find "$PYROOT/bin" -type f)
seen=" "
while [ -n "$queue" ]; do
    next=""
    for f in $queue; do
        case "$seen" in *" $f "*) continue ;; esac
        seen="$seen$f "
        for lib in $(needed_of "$f"); do
            case "$lib" in
                libc.so|libm.so|libdl.so|libpthread.so|librt.so|ld-musl-*.so) continue ;;
            esac
            if src=$(find_dep "$lib"); then
                [ -f "$PYROOT/lib/$lib" ] || cp -L "$src" "$PYROOT/lib/$lib"
                next="$next $PYROOT/lib/$lib"
            fi
        done
    done
    queue=$next
done

# --- relocatable script shebangs --------------------------------------------
# Entry-point scripts (pip, pydoc, ...) get a hardcoded /install shebang from
# make install. Replace it with a shell polyglot that resolves python relative
# to the script's own location.
for script in "$PYROOT/bin"/*; do
    [ -f "$script" ] || continue
    head -c 2 "$script" | grep -q '^#!' || continue
    "$readelf" -h "$script" >/dev/null 2>&1 && continue
    body=$(tail -n +2 "$script")
    cat > "$script" <<'EOF'
#!/bin/sh
'''exec' "$(dirname "$(readlink -f "$0")")/python3" "$0" "$@"' '''
EOF
    printf '%s\n' "$body" >> "$script"
    chmod +x "$script"
done

# --- licenses ---------------------------------------------------------------
mkdir -p "$PYROOT/licenses"
CPYTHON_SRC=$(dirname "$STAGE")/Python-$VERSION
cp "$CPYTHON_SRC/LICENSE" "$PYROOT/licenses/LICENSE.cpython.txt"
"$REPO/scripts/package-licenses.sh" "$REPO" "$PYROOT/licenses" "$CPYTHON_SRC"
{
    echo "This distribution bundles the following third-party libraries,"
    echo "compiled from source (see deps.json for the exact tarballs):"
    echo
    # No python3 in the build container; deps.json fields are one per line.
    grep -E '"(name|version|url)"' "$REPO/deps.json" \
        | sed 's/.*": *"\([^"]*\)".*/\1/' \
        | while read -r n && read -r v && read -r u; do
              printf '%s %s <%s>\n' "$n" "$v" "$u"
          done
} > "$PYROOT/licenses/THIRD-PARTY-NOTICES.txt"

# --- self-containment check ---------------------------------------------------
fail=0
for f in $(find "$PYROOT" -type f \( -name '*.so' -o -name '*.so.*' \)); do
    for lib in $(needed_of "$f"); do
        case "$lib" in
            libc.so|libm.so|libdl.so|libpthread.so|librt.so|ld-musl-*.so) continue ;;
        esac
        [ -f "$PYROOT/lib/$lib" ] || { echo "UNRESOLVED: $f needs $lib" >&2; fail=1; }
    done
done
[ "$fail" = 0 ] || exit 1

# --- tarball ------------------------------------------------------------------
VARIANT_SUFFIX=
[ "$VARIANT" = freethreaded ] && VARIANT_SUFFIX=-freethreaded
ARTIFACT=cpython-$VERSION+$TAG-$TRIPLE$VARIANT_SUFFIX-install_only.tar.gz
tar -C "$PKGDIR" -czf "$DIST/$ARTIFACT" python
echo "created $DIST/$ARTIFACT"
