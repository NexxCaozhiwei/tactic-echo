import unittest

from tek.src.windows_foreground import ForegroundWindow, WindowsForegroundDetector


class WindowsForegroundTests(unittest.TestCase):
    def _detector(self, window):
        detector = WindowsForegroundDetector.__new__(WindowsForegroundDetector)
        detector.allowed_process_names = {"wow.exe", "world of warcraft.exe"}
        detector.current = lambda: window
        return detector

    def test_chinese_title_and_wow_exe_is_foreground_ok(self):
        detector = self._detector(ForegroundWindow(100, "魔兽世界", 42, "Wow.exe", r"E:\\World of Warcraft\\_retail_\\Wow.exe"))
        snapshot = detector.snapshot()
        self.assertTrue(snapshot.ok)
        self.assertEqual("foreground_ok", snapshot.reason)
        self.assertEqual(r"E:\\World of Warcraft\\_retail_\\Wow.exe", snapshot.executable_path)

    def test_mismatch_snapshot_keeps_actual_window_diagnostics(self):
        detector = self._detector(ForegroundWindow(101, "Other App", 43, "other.exe", r"C:\\Other\\other.exe"))
        snapshot = detector.snapshot()
        self.assertFalse(snapshot.ok)
        self.assertEqual("window_process_mismatch", snapshot.reason)
        self.assertEqual("Other App", snapshot.title)
        self.assertEqual("other.exe", snapshot.process_name)
        self.assertEqual(r"C:\\Other\\other.exe", snapshot.executable_path)

class WindowsForegroundIdentityCacheTests(unittest.TestCase):
    def test_process_identity_path_is_cached_for_stable_hwnd_and_pid(self):
        now = [100.0]
        calls = []
        detector = WindowsForegroundDetector.__new__(WindowsForegroundDetector)
        detector._identity_cache = {}
        detector.process_cache_seconds = 0.75
        detector._clock = lambda: now[0]
        detector._process_path = lambda pid: calls.append(pid) or r"C:\\Games\\Wow.exe"

        self.assertEqual(detector._process_identity(77, 88), (r"C:\\Games\\Wow.exe", "Wow.exe"))
        self.assertEqual(detector._process_identity(77, 88), (r"C:\\Games\\Wow.exe", "Wow.exe"))
        self.assertEqual(calls, [88])

        now[0] += 0.76
        detector._process_identity(77, 88)
        self.assertEqual(calls, [88, 88])
