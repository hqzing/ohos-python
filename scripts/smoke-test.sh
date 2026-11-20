#!/bin/sh
# Smoke-test a freshly built interpreter: verify its OHOS platform identity,
# requested GIL variant, and extension modules backed by bundled libraries.
set -eu

PY=$1
export VARIANT="${2:-default}"

"$PY" -VV

"$PY" - <<'EOF'
import os, sys, sysconfig

assert sys.platform == "ohos", sys.platform
platform = sysconfig.get_platform()
assert platform.startswith("ohos-"), platform
assert sysconfig.get_config_var("MACHDEP") == "ohos"
suffix = sysconfig.get_config_var("EXT_SUFFIX")
assert "linux-ohos" in suffix, suffix

variant = os.environ["VARIANT"]
freethreaded = variant == "freethreaded"
assert variant in ("default", "freethreaded"), variant
assert bool(sysconfig.get_config_var("Py_GIL_DISABLED")) == freethreaded
assert (("t" in sys.abiflags) == freethreaded), sys.abiflags
abi_prefix = f".cpython-{sys.version_info.major}{sys.version_info.minor}{'t' if freethreaded else ''}-"
assert suffix.startswith(abi_prefix), (suffix, abi_prefix)
if hasattr(sys, "_is_gil_enabled"):
    assert sys._is_gil_enabled() != freethreaded

import bz2, ctypes, curses, lzma, readline, sqlite3, ssl, uuid, zlib
print("platform:", platform)
print("EXT_SUFFIX:", suffix)
print("openssl:", ssl.OPENSSL_VERSION)
print("sqlite:", sqlite3.sqlite_version)
if hasattr(sys, "_is_gil_enabled"):
    print("GIL enabled after extension imports:", sys._is_gil_enabled())
print("OK")
EOF

"$PY" -m pip --version
