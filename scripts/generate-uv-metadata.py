#!/usr/bin/env python3
"""Generate a uv-compatible Python download metadata JSON from the artifacts
in dist/ (read via SHA256SUMS), containing only the native OHOS platform
(``libc: "ohos"``) entries.

Schema mirrors uv's crates/uv-python/download-metadata.json: a flat map keyed
``{name}-{version}-{os}-{arch}-{libc}`` whose values carry the archive URL and
sha256. Point uv at it with ``python-downloads-json-url`` or
``UV_PYTHON_DOWNLOADS_JSON_URL``.

    generate-uv-metadata.py --tag 20260911 [--repo ohos-python/ohos-python] \
        [--dir dist] [--output python-downloads.json]
"""
import argparse
import json
import re
from pathlib import Path

ARTIFACT_RE = re.compile(
    r"cpython-(?P<version>(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)"
    r"(?P<prerelease>(a|b|rc)\d+)?)"
    r"\+(?P<build>\d+)-aarch64-unknown-linux-ohos"
    r"(?P<freethreaded>-freethreaded)?-install_only\.tar\.gz$"
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True, help="release tag (date, YYYYMMDD)")
    ap.add_argument("--repo", default="ohos-python/ohos-python")
    ap.add_argument("--dir", default="dist")
    ap.add_argument("--output", default=None)
    args = ap.parse_args()

    dist = Path(args.dir)
    sums = {}
    for line in (dist / "SHA256SUMS").read_text().splitlines():
        sha, _, name = line.partition("  ")
        sums[name.strip()] = sha.strip()

    entries = {}
    for name, sha in sorted(sums.items()):
        m = ARTIFACT_RE.match(name)
        if not m:
            continue
        version = m["version"]
        major, minor, patch = (int(m[part]) for part in ("major", "minor", "patch"))
        url = (
            f"https://github.com/{args.repo}/releases/download/{args.tag}/"
            + name.replace("+", "%2B")
        )
        variant = "freethreaded" if m["freethreaded"] else None
        variant_key = "+freethreaded" if m["freethreaded"] else ""
        entries[f"cpython-{version}{variant_key}-linux-aarch64-ohos"] = {
            "name": "cpython",
            "arch": {"family": "aarch64", "variant": None},
            "os": "linux",
            "libc": "ohos",
            "major": major,
            "minor": minor,
            "patch": patch,
            "prerelease": m["prerelease"],
            "url": url,
            "sha256": sha,
            "variant": variant,
            "build": m["build"],
        }

    if not entries:
        raise SystemExit(f"no cpython ohos artifacts found in {dist}/SHA256SUMS")

    out = Path(args.output) if args.output else dist / "python-downloads.json"
    out.write_text(json.dumps(entries, indent=2) + "\n")
    print(f"wrote {out} with {len(entries)} entries")


if __name__ == "__main__":
    main()
