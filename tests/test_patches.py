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

    def test_ohos_api_and_runtime_patches(self):
        for series in ("3.12", "3.13", "3.14", "3.15"):
            with self.subTest(series=series):
                configure = (ROOT / f"patches/{series}/configure.ac.patch").read_text()
                self.assertNotIn("AC_ARG_VAR([OHOS_SDK_NATIVE]", configure)
                self.assertIn("OHOS_SDK_NATIVE=`cd", configure)
                self.assertIn("-print-file-name=libc.so", configure)
                self.assertIn("OH_UNI_PACKAGE_JSON", configure)
                self.assertIn("oh-uni-package.json", configure)
                self.assertIn("OpenHarmony SDK metadata file oh-uni-package.json was not found", configure)
                self.assertIn("apiVersion in oh-uni-package.json must be a positive integer", configure)
                self.assertIn("AC_DEFINE_UNQUOTED([OHOS_API_LEVEL]", configure)

                sysconfig_name = (
                    "Lib_sysconfig.py.patch"
                    if series == "3.12"
                    else "Lib_sysconfig___init__.py.patch"
                )
                sysconfig = (ROOT / f"patches/{series}/{sysconfig_name}").read_text()
                self.assertIn("OHOS_API_LEVEL", sysconfig)
                self.assertIn('osname == "ohos" or sys.platform == "ohos"', sysconfig)
                self.assertNotIn('return f"ohos-{machine}"', sysconfig)

                platform = (ROOT / f"patches/{series}/Lib_platform.py.patch").read_text()
                self.assertIn('CDLL(', platform)
                self.assertIn("OH_GetSdkApiVersion", platform)
                self.assertIn("OH_GetOSFullName", platform)
                self.assertIn('.removeprefix("OpenHarmony-")', platform)
                self.assertIn('namedtuple("OhosVer", "release api_level")', platform)
                self.assertIn("def ohos_ver", platform)

        for series in ("3.12", "3.13"):
            with self.subTest(series=f"{series} sysconfig bootstrap"):
                name = (
                    "Lib_sysconfig.py.patch"
                    if series == "3.12"
                    else "Lib_sysconfig___main__.py.patch"
                )
                text = (ROOT / f"patches/{series}/{name}").read_text()
                self.assertIn("'darwin' in sys.platform or 'ohos' in sys.platform", text)

        self.assertFalse(list((ROOT / "patches").rglob("*test*.patch")))

    def test_patches_have_no_header(self):
        for path in (ROOT / "patches").rglob("*.patch"):
            with self.subTest(path=path):
                self.assertTrue(path.read_text().startswith("--- a/"))


if __name__ == "__main__":
    unittest.main()
