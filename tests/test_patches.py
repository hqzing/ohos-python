import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


class PatchTest(unittest.TestCase):
    def test_linux_ohos_configuration(self):
        for series in ("3.12", "3.13", "3.14", "3.15"):
            with self.subTest(series=series):
                text = (ROOT / f"patches/{series}/configure.ac.patch").read_text()
                self.assertEqual(text.count("ac_sys_system=Linux-ohos"), 2)
                self.assertNotIn("HarmonyOS", text)
                self.assertLess(
                    text.index('linux-ohos*) MACHDEP="ohos"'),
                    text.index('linux*) MACHDEP="linux"'),
                )
                self.assertNotIn("Linux-ohos*)", text)
                self.assertNotIn("ac_cv_header_libintl_h", text)
                self.assertNotIn("ac_cv_header_linux_can", text)
                self.assertNotIn("lchmod", text)

    def test_patches_have_no_header(self):
        for path in (ROOT / "patches").rglob("*.patch"):
            with self.subTest(path=path):
                self.assertTrue(path.read_text().startswith("--- a/"))


if __name__ == "__main__":
    unittest.main()
