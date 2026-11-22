#!/bin/sh
# Smoke-test a freshly built interpreter: verify its OHOS platform identity,
# versioned wheel tags, requested GIL variant, and bundled extension modules.
set -eu

PY=$1
export VARIANT="${2:-default}"

"$PY" -VV

"$PY" - <<'EOF'
import os, platform, re, sys, sysconfig

assert sys.platform == "ohos", sys.platform
platform_name = sysconfig.get_platform()
match = re.fullmatch(r"ohos-([0-9]+)-aarch64", platform_name)
assert match, platform_name
build_api = int(match[1])
assert sysconfig.get_config_var("OHOS_API_LEVEL") == build_api
assert sysconfig.get_config_var("MACHDEP") == "ohos"

ohos_version = platform.ohos_ver()
runtime_api = ohos_version.api_level
assert isinstance(runtime_api, int) and runtime_api >= 10, runtime_api
assert ohos_version.release == "7.0.0.109", ohos_version
from pip._vendor.packaging import tags
platform_tags = list(tags.platform_tags())
assert platform_tags == [f"ohos_{build_api}_aarch64"], platform_tags

os.environ["_PYTHON_HOST_PLATFORM"] = "ohos-aarch64"
sys.platform = "linux"
assert sysconfig.get_platform() == platform_name
sys.platform = "ohos"
del os.environ["_PYTHON_HOST_PLATFORM"]

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
print("platform:", platform_name)
print("build API:", build_api)
print("runtime API:", runtime_api)
print("release:", ohos_version.release)
print("pip platform tags:", platform_tags)
print("EXT_SUFFIX:", suffix)
print("openssl:", ssl.OPENSSL_VERSION)
print("sqlite:", sqlite3.sqlite_version)
if hasattr(sys, "_is_gil_enabled"):
    print("GIL enabled after extension imports:", sys._is_gil_enabled())
print("OK")
EOF

"$PY" -m pip --version
