import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from tek.app.settings_store import AppSettings, SettingsStore
from tek.app.status_window import StatusWindow
from tek.app.worker_controller import WorkerOptions
from tek.src.windows_display import VirtualDesktopBounds


class SettingsStoreTests(unittest.TestCase):
    def test_defaults_are_safe_for_ui_linked_product_flow(self):
        settings = AppSettings.defaults()
        self.assertTrue(settings.auto_start_ui_linked)
        self.assertTrue(settings.auto_locate_signal)
        self.assertEqual(settings.sampling_interval_ms, 50)
        self.assertEqual(settings.signal_sampler_backend, "pillow")
        self.assertEqual(settings.profile_id, "laptop")
        self.assertEqual(WorkerOptions(mode="Dry-run").interval_seconds, 0.05)
        self.assertEqual(settings.auto_dispatch_exempt_keys, ("W", "A", "S", "D", "SPACE"))

    def test_normalizes_sampling_range_and_process_names(self):
        settings = AppSettings.from_dict(
            {
                "sampling_interval_ms": 2,
                "ui_link_wait_seconds": 1000,
                "wow_process_names": " wow.exe, World of Warcraft.exe ",
            }
        )
        self.assertEqual(settings.sampling_interval_ms, 20)
        self.assertEqual(settings.ui_link_wait_seconds, 600)
        self.assertEqual(settings.allowed_process_names(), ("wow.exe", "world of warcraft.exe"))
        self.assertNotIn("protocol_mode", settings.to_dict())

    def test_normalizes_and_persists_repeat_rate_limits(self):
        settings = AppSettings.from_dict(
            {
                "max_dispatch_per_second": 99,
                "max_wheel_dispatch_per_second": 0,
            }
        )
        self.assertEqual(settings.max_dispatch_per_second, 20)
        self.assertEqual(settings.max_wheel_dispatch_per_second, 1)

        with tempfile.TemporaryDirectory() as directory:
            store = SettingsStore(Path(directory) / "settings.json")
            saved = store.save(AppSettings.from_dict({"max_dispatch_per_second": 15, "max_wheel_dispatch_per_second": 3}))
            loaded = store.load()
            self.assertEqual(saved.max_dispatch_per_second, 15)
            self.assertEqual(saved.max_wheel_dispatch_per_second, 3)
            self.assertEqual(loaded.max_dispatch_per_second, 15)
            self.assertEqual(loaded.max_wheel_dispatch_per_second, 3)


    def test_manual_handover_profiles_and_custom_values_are_normalized(self):
        settings = AppSettings.from_dict({
            "manual_priority_mode": "custom",
            "manual_priority_custom_recovery_ms": 2000,
            "manual_priority_custom_freshness_frames": 99,
            "manual_priority_custom_replay_guard_ms": -1,
        })
        self.assertEqual(settings.manual_priority_mode, "custom")
        self.assertEqual(settings.manual_priority_custom_recovery_ms, 1500)
        self.assertEqual(settings.manual_priority_custom_freshness_frames, 2)
        self.assertEqual(settings.manual_priority_custom_replay_guard_ms, 0)
        self.assertNotIn("wow_bindings_cache_path", settings.to_dict())

    def test_legacy_custom_manual_recovery_triplet_migrates_to_new_defaults(self):
        settings = AppSettings.from_dict({
            "schema_version": 3,
            "manual_priority_mode": "custom",
            "manual_priority_custom_recovery_ms": 80,
            "manual_priority_custom_freshness_frames": 2,
            "manual_priority_custom_replay_guard_ms": 1000,
        })
        self.assertEqual(settings.manual_priority_custom_recovery_ms, 30)
        self.assertEqual(settings.manual_priority_custom_freshness_frames, 2)
        self.assertEqual(settings.manual_priority_custom_replay_guard_ms, 150)
        self.assertEqual(settings.schema_version, 8)

    def test_intervention_whitelist_normalizes_and_persists(self):
        with tempfile.TemporaryDirectory() as directory:
            store = SettingsStore(Path(directory) / "settings.json")
            saved = store.save(AppSettings.from_dict({"auto_dispatch_exempt_keys": ["w", "spacebar", "Q", "bad", "W"]}))
            self.assertEqual(saved.auto_dispatch_exempt_keys, ("W", "SPACE", "Q"))
            self.assertEqual(store.load().auto_dispatch_exempt_keys, ("W", "SPACE", "Q"))

    def test_import_accepts_legacy_tuple_string_and_discards_standalone_modifiers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = SettingsStore(root / "settings.json")
            source = root / "legacy.json"
            source.write_text(json.dumps({
                "auto_dispatch_exempt_keys": "('w', 'spacebar', 'CTRL', 'Shift', 'Q', 'W')",
            }), encoding="utf-8")
            result = store.import_with_result(source)
            self.assertEqual(result.settings.auto_dispatch_exempt_keys, ("W", "SPACE", "Q"))
            self.assertTrue(result.warnings)

    def test_import_preserves_current_whitelist_when_source_field_is_malformed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = SettingsStore(root / "settings.json")
            store.save(AppSettings.from_dict({"auto_dispatch_exempt_keys": ["UP", "DOWN"]}))
            source = root / "invalid.json"
            source.write_text(json.dumps({"auto_dispatch_exempt_keys": "[not valid"}), encoding="utf-8")
            result = store.import_with_result(source)
            self.assertEqual(result.settings.auto_dispatch_exempt_keys, ("UP", "DOWN"))
            self.assertIn("已保留当前本地白名单", "\n".join(result.warnings))

    def test_window_geometry_normalizes_persists_and_keeps_virtual_desktop_coordinates(self):
        with tempfile.TemporaryDirectory() as directory:
            store = SettingsStore(Path(directory) / "settings.json")
            saved = store.save_window_geometry(width=2000, height=200, x=-1920, y=88)
            self.assertEqual((saved.window_width, saved.window_height), (900, 900))
            self.assertEqual((saved.window_x, saved.window_y), (-1920, 88))
            loaded = store.load()
            self.assertEqual((loaded.window_width, loaded.window_height, loaded.window_x, loaded.window_y), (900, 900, -1920, 88))

    def test_window_geometry_requires_both_coordinates_or_restores_size_only(self):
        settings = AppSettings.from_dict({"window_width": 650, "window_height": 1100, "window_x": 240})
        self.assertEqual((settings.window_width, settings.window_height), (650, 1100))
        self.assertIsNone(settings.window_x)
        self.assertIsNone(settings.window_y)

    def test_saved_window_geometry_visibility_rejects_removed_monitor_position(self):
        self.assertTrue(StatusWindow._geometry_intersects_desktop(
            x=-1600, y=80, width=600, height=1000,
            desktop_left=-1920, desktop_top=0, desktop_width=3840, desktop_height=1080,
        ))
        self.assertFalse(StatusWindow._geometry_intersects_desktop(
            x=-1600, y=80, width=600, height=1000,
            desktop_left=0, desktop_top=0, desktop_width=1920, desktop_height=1080,
        ))

    def test_status_window_restore_uses_saved_rectangle_and_recenters_removed_monitor_position(self):
        class FakeRoot:
            def __init__(self):
                self.calls = []
            def geometry(self, value):
                self.calls.append(value)
            def winfo_vrootx(self):
                return 0
            def winfo_vrooty(self):
                return 0
            def winfo_vrootwidth(self):
                return 1920
            def winfo_vrootheight(self):
                return 1080

        with tempfile.TemporaryDirectory() as directory:
            store = SettingsStore(Path(directory) / "settings.json")
            store.save(AppSettings.from_dict({
                "window_width": 600,
                "window_height": 1000,
                "window_x": -1600,
                "window_y": 80,
            }))
            window = StatusWindow.__new__(StatusWindow)
            window.root = FakeRoot()
            window.settings_store = store
            window._last_saved_window_geometry = None
            # On Windows, StatusWindow correctly prefers Win32 virtual-desktop
            # metrics over Tk's vroot values. Patch that host-dependent provider
            # here so this unit test exercises the FakeRoot fallback deterministically.
            with patch(
                "tek.app.status_window.virtual_desktop_bounds",
                return_value=VirtualDesktopBounds(),
            ):
                window._restore_saved_window_geometry()
            # The saved monitor is gone, so the host is centered on the active
            # desktop rather than restoring to an invisible negative coordinate.
            self.assertEqual(window.root.calls, ["600x1000+660+40"])
            self.assertEqual(window._last_saved_window_geometry, (600, 1000, 660, 40))

    def test_boot_marker_only_requests_window_once_per_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            store = SettingsStore(Path(directory) / "settings.json")
            first, first_should_show = store.should_show_window_after_boot(AppSettings.defaults(), boot_marker="boot-a")
            second, second_should_show = store.should_show_window_after_boot(first, boot_marker="boot-a")
            _, third_should_show = store.should_show_window_after_boot(second, boot_marker="boot-b")
            self.assertTrue(first_should_show)
            self.assertFalse(second_should_show)
            self.assertTrue(third_should_show)

    def test_export_and_import_only_settings_json(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = SettingsStore(root / "settings.json")
            saved = store.save(AppSettings.from_dict({"sampling_interval_ms": 150, "profile_id": "laptop"}))
            exported = root / "export.json"
            store.export_to(exported)
            self.assertEqual(json.loads(exported.read_text(encoding="utf-8"))["sampling_interval_ms"], 150)

            imported = SettingsStore(root / "other.json")
            settings = imported.import_from(exported)
            self.assertEqual(settings.sampling_interval_ms, saved.sampling_interval_ms)


class SamplerBackendSettingsTests(unittest.TestCase):
    def test_sampler_backend_normalizes_to_auto_pillow_or_gdi_variants(self):
        self.assertEqual(AppSettings.from_dict({"signal_sampler_backend": "GDI"}).signal_sampler_backend, "gdi")
        self.assertEqual(AppSettings.from_dict({"signal_sampler_backend": "gdi_blt"}).signal_sampler_backend, "gdi_blt")
        self.assertEqual(AppSettings.from_dict({"signal_sampler_backend": "auto"}).signal_sampler_backend, "auto")
        self.assertEqual(AppSettings.from_dict({"signal_sampler_backend": "unsupported"}).signal_sampler_backend, "pillow")

    def test_sampler_backend_persists(self):
        with tempfile.TemporaryDirectory() as directory:
            store = SettingsStore(Path(directory) / "settings.json")
            store.save(AppSettings.from_dict({"signal_sampler_backend": "gdi"}))
            self.assertEqual(store.load().signal_sampler_backend, "gdi")


if __name__ == "__main__":
    unittest.main()

    def test_virtual_desktop_coordinates_and_mapping_path_are_preserved(self):
        settings = AppSettings.from_dict({
            "fixed_signal_x": -1920,
            "fixed_signal_y": -100,
            "wow_savedvariables_path": r"C:\\Games\\WoW\\WTF\\Account\\x\\SavedVariables\\TacticEcho.lua",
        })
        self.assertEqual(settings.fixed_signal_x, -1920)
        self.assertEqual(settings.fixed_signal_y, -100)
        self.assertTrue(settings.wow_savedvariables_path.endswith("TacticEcho.lua"))
