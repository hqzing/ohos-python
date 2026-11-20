import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class GenerateUvMetadataTest(unittest.TestCase):
    def test_default_and_freethreaded_variants(self):
        regular = (
            "cpython-3.14.7+20261119-aarch64-unknown-linux-ohos-"
            "install_only.tar.gz"
        )
        freethreaded = (
            "cpython-3.14.7+20261119-aarch64-unknown-linux-ohos-"
            "freethreaded-install_only.tar.gz"
        )
        with tempfile.TemporaryDirectory() as tmp:
            dist = Path(tmp)
            (dist / "SHA256SUMS").write_text(
                f"{'1' * 64}  {regular}\n{'2' * 64}  {freethreaded}\n"
            )
            output = dist / "python-downloads.json"
            subprocess.run(
                [
                    sys.executable,
                    str(Path(__file__).parents[1] / "scripts/generate-uv-metadata.py"),
                    "--tag",
                    "20261119",
                    "--repo",
                    "ohos-python/ohos-python",
                    "--dir",
                    str(dist),
                    "--output",
                    str(output),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            entries = json.loads(output.read_text())

        self.assertEqual(
            set(entries),
            {
                "cpython-3.14.7-linux-aarch64-ohos",
                "cpython-3.14.7+freethreaded-linux-aarch64-ohos",
            },
        )
        regular_entry = entries["cpython-3.14.7-linux-aarch64-ohos"]
        free_entry = entries["cpython-3.14.7+freethreaded-linux-aarch64-ohos"]
        self.assertIsNone(regular_entry["variant"])
        self.assertEqual(regular_entry["sha256"], "1" * 64)
        self.assertEqual(free_entry["variant"], "freethreaded")
        self.assertEqual(free_entry["sha256"], "2" * 64)
        self.assertEqual(free_entry["build"], "20261119")
        self.assertEqual(
            free_entry["url"],
            "https://github.com/ohos-python/ohos-python/releases/download/"
            "20261119/cpython-3.14.7%2B20261119-aarch64-unknown-linux-ohos-"
            "freethreaded-install_only.tar.gz",
        )


if __name__ == "__main__":
    unittest.main()
