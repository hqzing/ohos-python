#!/bin/sh
# Verify that pip resolves OHOS wheels (ohos_aarch64) no matter what the
# kernel's uname reports: DockerHarmony containers run on a Linux kernel
# (uname -s = Linux), real OpenHarmony devices may report HarmonyOS.
# The second case is simulated with an LD_PRELOAD stub (uname-harmonyos.c).
#
#   tests/test-pip-uname.sh <python-root> <index-url> [package]
#
# <python-root>: extracted install_only tree (the dir containing bin/).
# <index-url>:   PEP 503 index, e.g. file:///path/to/ohos-pypi-ports/site
# [package]:     package to download (default: numpy, must exist in the index)
set -eu

PYROOT=$1
INDEX=$2
PKG=${3:-numpy}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$HERE/../.build/test-pip-uname

# pip refuses plain-HTTP indexes unless the host is explicitly trusted
INDEX_HOST=$(echo "$INDEX" | sed -n 's|^[a-z]*://\([^/:]*\).*|\1|p')
TRUSTED=""
[ -n "$INDEX_HOST" ] && TRUSTED="--trusted-host $INDEX_HOST"

PY=$(echo "$PYROOT"/bin/python3.* | awk '{print $1}')
[ -x "$PY" ] || PY=$PYROOT/bin/python3

rm -rf "$WORK"
mkdir -p "$WORK"

log() { printf '\n=== %s ===\n' "$*"; }

log "build uname stub"
cc -shared -fPIC -o "$WORK/libuname-harmonyos.so" "$HERE/uname-harmonyos.c"

run_case() {  # run_case <label> <ld_preload>
    label=$1
    preload=$2
    log "case: uname -s = $label"
    out="$WORK/out-$label"
    mkdir -p "$out"
    report=$(LD_PRELOAD="$preload" "$PY" - "$out" "$INDEX" "$PKG" $TRUSTED <<'EOF'
import platform, subprocess, sys

out, index, pkg = sys.argv[1], sys.argv[2], sys.argv[3]
trusted = sys.argv[4:]
print("platform.system():", platform.system())
print("sys.platform:", sys.platform)
import sysconfig
print("get_platform():", sysconfig.get_platform())

r = subprocess.run(
    [sys.executable, "-m", "pip", "download", "--no-deps", "--only-binary", ":all:",
     "-d", out, "--index-url", index, *trusted, pkg],
    capture_output=True, text=True)
print(r.stdout)
print(r.stderr, file=sys.stderr)
if r.returncode != 0:
    sys.exit(r.returncode)
EOF
)
    echo "$report"
    wheel=$(ls "$out"/*.whl 2>/dev/null | head -n 1)
    [ -n "$wheel" ] || { echo "FAIL: no wheel downloaded" >&2; exit 1; }
    case "$wheel" in
        *ohos_aarch64*) echo "PASS: got OHOS wheel: $(basename "$wheel")" ;;
        *) echo "FAIL: wrong platform wheel: $(basename "$wheel")" >&2; exit 1 ;;
    esac
}

# Case 1: container reality — Linux kernel.
run_case "Linux" ""

# Case 2: stubbed HarmonyOS kernel.
sys=$(LD_PRELOAD="$WORK/libuname-harmonyos.so" "$PY" -c 'import platform; print(platform.system())')
[ "$sys" = "HarmonyOS" ] || { echo "FAIL: uname stub ineffective (got $sys)" >&2; exit 1; }
run_case "HarmonyOS" "$WORK/libuname-harmonyos.so"

log "all cases passed"
