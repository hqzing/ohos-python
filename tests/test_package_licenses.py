import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts/package-licenses.sh"
EXPECTED_LICENSES = [
    ("openssl", "LICENSE.txt"),
    ("zlib", "LICENSE"),
    ("libffi", "LICENSE"),
    ("util-linux", "README.licensing"),
    ("util-linux", "libuuid/COPYING"),
    ("util-linux", "Documentation/licenses/COPYING.BSD-3-Clause"),
    ("xz", "COPYING"),
    ("xz", "COPYING.0BSD"),
    ("bzip2", "LICENSE"),
    ("zstd", "LICENSE"),
    ("zstd", "COPYING"),
    ("ncurses", "COPYING"),
    ("readline", "COPYING"),
    ("sqlite", "LICENSE.md"),
]
HACL_TEXT = "/* HACL license\n * Copyright HACL contributors\n */\nvoid f(void);\n"
MPDEC_TEXT = "/* libmpdec license\n * Copyright libmpdec authors\n */\n#define X 1\n"
MIMALLOC_TEXT = "/* mimalloc license\n * Copyright mimalloc authors\n */\n#pragma once\n"


def license_calls():
    return re.findall(
        r"^copy_license ([a-z0-9-]+) (\S+)$",
        SCRIPT.read_text(),
        re.MULTILINE,
    )


def create_sources(repo, calls):
    for dependency, relative_path in calls:
        path = repo / ".build/deps" / f"{dependency}-src" / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"{dependency}: {relative_path}\n")


def create_cpython_sources(root, include_hacl=True):
    files = {
        "Doc/license.rst": "CPython incorporated licenses\n",
        "Modules/expat/COPYING": "Expat license\n",
        "Modules/_decimal/libmpdec/mpdecimal.h": MPDEC_TEXT,
        "Include/internal/mimalloc/mimalloc.h": MIMALLOC_TEXT,
    }
    if include_hacl:
        files["Modules/_hacl/Hacl_Hash_SHA2.h"] = HACL_TEXT
    for relative_path, text in files.items():
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


def run_packaging(repo, output, cpython, check=True):
    return subprocess.run(
        [str(SCRIPT), str(repo), str(output), str(cpython)],
        check=check,
        capture_output=True,
        text=True,
    )


class PackageLicensesTest(unittest.TestCase):
    def test_all_dependency_licenses_are_copied(self):
        dependencies = {
            entry["name"]
            for entry in json.loads((ROOT / "deps.json").read_text())["deps"]
        }
        calls = license_calls()
        self.assertEqual(calls, EXPECTED_LICENSES)
        self.assertEqual({dependency for dependency, _ in calls}, dependencies)

        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            cpython = Path(tmp) / "cpython"
            output = Path(tmp) / "licenses"
            create_sources(repo, calls)
            create_cpython_sources(cpython)
            run_packaging(repo, output, cpython)

            for dependency, relative_path in calls:
                copied = output / dependency / relative_path
                self.assertEqual(
                    copied.read_text(), f"{dependency}: {relative_path}\n"
                )
            self.assertEqual(
                (output / "cpython/LICENSE.incorporated.rst").read_text(),
                "CPython incorporated licenses\n",
            )
            self.assertEqual((output / "expat/COPYING").read_text(), "Expat license\n")
            self.assertEqual(
                (output / "hacl/LICENSE.txt").read_text(),
                HACL_TEXT.split("void f(void);")[0],
            )
            self.assertEqual(
                (output / "libmpdec/LICENSE.txt").read_text(),
                MPDEC_TEXT.split("#define X 1")[0],
            )
            self.assertEqual(
                (output / "mimalloc/LICENSE.txt").read_text(),
                MIMALLOC_TEXT.split("#pragma once")[0],
            )

    def test_hacl_is_optional(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            cpython = Path(tmp) / "cpython"
            output = Path(tmp) / "licenses"
            create_sources(repo, EXPECTED_LICENSES)
            create_cpython_sources(cpython, include_hacl=False)
            run_packaging(repo, output, cpython)
            self.assertFalse((output / "hacl").exists())

    def test_missing_license_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            cpython = Path(tmp) / "cpython"
            output = Path(tmp) / "licenses"
            create_sources(repo, EXPECTED_LICENSES)
            create_cpython_sources(cpython)
            dependency, relative_path = EXPECTED_LICENSES[0]
            missing = repo / ".build/deps" / f"{dependency}-src" / relative_path
            missing.unlink()

            result = run_packaging(repo, output, cpython, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing license", result.stderr)
            self.assertIn(str(missing), result.stderr)


if __name__ == "__main__":
    unittest.main()
