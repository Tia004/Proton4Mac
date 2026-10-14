import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("launcher", Path(__file__).parents[1] / "proton4mac.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)
sys.modules["proton4mac"] = launcher
entry_spec = importlib.util.spec_from_file_location("entry", Path(__file__).parents[1] / "proton_entry.py")
entry = importlib.util.module_from_spec(entry_spec)
entry_spec.loader.exec_module(entry)


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()

    def pe(self, machine=0x8664):
        target = self.root / "game with spaces.exe"
        header = bytearray(64)
        header[:2] = b"MZ"
        struct.pack_into("<I", header, 60, 64)
        target.write_bytes(header + b"PE\0\0" + struct.pack("<H", machine))
        return target

    def test_prefix_traversal_rejected(self):
        for name in ("../other", "a/b", "", ".", "a" * 65):
            with self.assertRaises(launcher.LauncherError):
                launcher.prefix_path(self.root, name)

    def test_prefix_lock_prevents_concurrent_launch(self):
        prefix = launcher.prefix_path(self.root, "game")
        with launcher.prefix_lock(prefix):
            with self.assertRaises(launcher.LauncherError):
                with launcher.prefix_lock(prefix):
                    pass

    def test_environment_cannot_inherit_another_prefix_or_linux_runtime(self):
        with patch.dict(os.environ, {"WINEPREFIX": "/other", "WINEFSYNC": "1",
                                     "PROTON_LOG": "1", "LD_LIBRARY_PATH": "/linux",
                                     "DXVK_CONFIG_FILE": "/other.conf", "WINELOADER": "/linux/wine"}):
            env = launcher.environment(self.root)
        self.assertEqual(env["WINEPREFIX"], str(self.root))
        for key in ("WINEFSYNC", "PROTON_LOG", "LD_LIBRARY_PATH", "DXVK_CONFIG_FILE", "WINELOADER"):
            self.assertNotIn(key, env)

    def test_pe_validation(self):
        self.assertEqual(launcher.windows_executable(self.pe()), self.pe())
        with self.assertRaises(launcher.LauncherError):
            launcher.windows_executable(self.pe(0xAA64))
        invalid = self.root / "invalid.exe"
        invalid.write_text("hello")
        with self.assertRaises(launcher.LauncherError):
            launcher.windows_executable(invalid)

    def test_explicit_missing_runtime_does_not_silently_fall_back(self):
        with self.assertRaises(launcher.LauncherError):
            launcher.runtime(str(self.root / "absent"))

    def test_unmanaged_prefix_not_modified(self):
        prefix = self.root / "existing"
        prefix.mkdir()
        with self.assertRaises(launcher.LauncherError):
            launcher.initialize(Path("/wine"), prefix)
        self.assertEqual(list(prefix.iterdir()), [])

    def test_incomplete_initialization_retried(self):
        prefix = self.root / "prefix"
        prefix.mkdir()
        marker = prefix / ".proton4mac.json"
        marker.write_text(json.dumps({"wine": "/wine", "ready": False}))
        with patch.object(launcher, "execute", return_value=launcher.subprocess.CompletedProcess([], 0, "", "")) as run:
            launcher.initialize(Path("/wine"), prefix)
        run.assert_called_once()
        self.assertTrue(json.loads(marker.read_text())["ready"])

    def test_dry_run_preserves_arguments_and_does_not_create_prefix(self):
        exe = self.pe()
        output = io.StringIO()
        with patch.object(launcher.platform, "system", return_value="Darwin"), patch.object(launcher, "runtime", return_value=Path("/wine")), contextlib.redirect_stdout(output):
            code = launcher.main(["--root", str(self.root), "run", "--dry-run", str(exe),
                                  "two words", "$(touch nope)", "--flag"])
        report = json.loads(output.getvalue())
        self.assertEqual(code, 0)
        self.assertEqual(report["argv"], ["/wine", str(exe), "two words", "$(touch nope)", "--flag"])
        self.assertFalse((self.root / "prefixes").exists())

    def test_exit_code_forwarded(self):
        exe = self.pe()
        with patch.object(launcher.platform, "system", return_value="Darwin"), patch.object(launcher, "runtime", return_value=Path("/wine")), patch.object(launcher, "initialize"), patch.object(launcher, "execute", return_value=launcher.subprocess.CompletedProcess([], 42)):
            self.assertEqual(launcher.main(["--root", str(self.root), "run", str(exe)]), 42)

    def test_capture_and_timeout(self):
        result = launcher.execute([sys.executable, "-c", "print('captured')"], capture=True, timeout=5)
        self.assertEqual(result.stdout.strip(), "captured")
        with self.assertRaises(launcher.LauncherError):
            launcher.execute([sys.executable, "-c", "import time; time.sleep(5)"], capture=True, timeout=0.1)

    def test_proton_verbs_use_separate_compat_storage(self):
        result = entry.translate(["waitforexitandrun", "/game.exe", "two words"],
                                 {"STEAM_COMPAT_DATA_PATH": str(self.root), "SteamAppId": "123"})
        self.assertEqual(result, ["--root", str(self.root / "proton4mac"),
                                  "run", "--prefix", "123", "--wait-for-exit", "/game.exe", "two words"])
        with self.assertRaises(ValueError):
            entry.translate(["getcompatpath", "/game.exe"], {})


if __name__ == "__main__":
    unittest.main()
