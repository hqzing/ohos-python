#!/bin/sh
# Bootstrap the build environment inside a bare DockerHarmony container:
# install ohos-zsh, Harmonybrew, the OHOS SDK, and the autotools. Real OHOS
# devices provide libdeviceinfo_ndk.z.so; the mini container does not, so
# install an API 26 stub only when no library is present. Idempotent.
set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd)
TOOLS=$REPO/.tools
prefix=/storage/Users/currentUser/.harmonybrew
brew=$prefix/bin/brew

if [ -x "$brew" ]; then
    echo "Harmonybrew already installed: $prefix"
else
    if ! command -v zsh >/dev/null 2>&1; then
        echo "=== install ohos-zsh ==="
        mkdir -p "$TOOLS"
        curl -fL -o "$TOOLS/zsh-5.9-ohos-arm64.tar.gz" https://github.com/Harmonybrew/ohos-zsh/releases/download/5.9/zsh-5.9-ohos-arm64.tar.gz
        tar -zxf "$TOOLS/zsh-5.9-ohos-arm64.tar.gz" -C "$TOOLS"
        rm "$TOOLS/zsh-5.9-ohos-arm64.tar.gz"
        ZSH=$TOOLS/zsh-5.9-ohos-arm64/bin/zsh
        ln -sf "$ZSH" /usr/bin/zsh
    else
        ZSH=zsh
    fi

    echo "=== install Harmonybrew ==="
    export NONINTERACTIVE=1
    "$ZSH" -c "$(curl -fsSL https://harmonybrew.atomgit.com/install.sh)"
    [ -x "$brew" ] || { echo "brew not found after install" >&2; exit 1; }

    if ! grep -q 'harmonybrew/bin/brew shellenv' "$HOME/.profile" 2>/dev/null; then
        printf 'eval "$(%s/bin/brew shellenv)"\n' "$prefix" >> "$HOME/.profile"
    fi
    echo "Harmonybrew installed: $prefix"
fi

eval "$("$brew" shellenv)"
brew install -y devel-base autoconf autoconf-archive automake pkgconf

if [ ! -e /system/lib64/ndk/libdeviceinfo_ndk.z.so ]; then
    echo "=== install OpenHarmony deviceinfo stub (API 26) ==="
    mkdir -p /system
    if [ ! -e /system/lib64 ]; then
        ln -s /lib64 /system/lib64
    fi
    mkdir -p /system/lib64/ndk
    clang -shared -fPIC "$REPO/scripts/deviceinfo-stub.c" \
        -o /system/lib64/ndk/libdeviceinfo_ndk.z.so
fi
