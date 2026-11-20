#!/bin/sh
set -eu

REPO=$1
OUT=$2
CPYTHON_SRC=$3

copy_license() {
    dependency=$1
    relative_path=$2
    source=$REPO/.build/deps/$dependency-src/$relative_path
    destination=$OUT/$dependency/$relative_path
    if [ ! -f "$source" ]; then
        echo "missing license: $source" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$destination")"
    cp "$source" "$destination"
}

copy_license openssl LICENSE.txt
copy_license zlib LICENSE
copy_license libffi LICENSE
copy_license util-linux README.licensing
copy_license util-linux libuuid/COPYING
copy_license util-linux Documentation/licenses/COPYING.BSD-3-Clause
copy_license xz COPYING
copy_license xz COPYING.0BSD
copy_license bzip2 LICENSE
copy_license zstd LICENSE
copy_license zstd COPYING
copy_license ncurses COPYING
copy_license readline COPYING
copy_license sqlite LICENSE.md

copy_cpython_license() {
    component=$1
    relative_path=$2
    destination_name=$3
    source=$CPYTHON_SRC/$relative_path
    destination=$OUT/$component/$destination_name
    if [ ! -f "$source" ]; then
        echo "missing license: $source" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$destination")"
    cp "$source" "$destination"
}

copy_cpython_comment() {
    component=$1
    relative_path=$2
    source=$CPYTHON_SRC/$relative_path
    destination=$OUT/$component/LICENSE.txt
    if [ ! -f "$source" ]; then
        echo "missing license: $source" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$destination")"
    sed -n '1,/\*\//p' "$source" > "$destination"
}

copy_cpython_license cpython Doc/license.rst LICENSE.incorporated.rst
copy_cpython_license expat Modules/expat/COPYING COPYING
if [ -d "$CPYTHON_SRC/Modules/_hacl" ]; then
    copy_cpython_comment hacl Modules/_hacl/Hacl_Hash_SHA2.h
fi
if [ -d "$CPYTHON_SRC/Modules/_decimal/libmpdec" ]; then
    copy_cpython_comment libmpdec Modules/_decimal/libmpdec/mpdecimal.h
fi
if [ -d "$CPYTHON_SRC/Include/internal/mimalloc" ]; then
    copy_cpython_comment mimalloc Include/internal/mimalloc/mimalloc.h
fi

printf 'third-party licenses: %s\n' "$OUT"
