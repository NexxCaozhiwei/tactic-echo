from __future__ import annotations

import json
import os
import time
from dataclasses import asdict, dataclass, fields
from pathlib import Path


SETTINGS_SCHEMA_VERSION = 8


@dataclass(frozen=True)
class AppSettings:
    """User-facing TEK.exe settings persisted under %LOCALAPPDATA%/TacticEcho."""

    schema_version: int = SETTINGS_SCHEMA_VERSION
    profile_id: str = "laptop"
    auto_locate_signal: bool = True
    # Auto mode locates/validates through Pillow first, then promotes the
    # narrow runtime strip to GDI BitBlt when several reads remain healthy.
    signal_sampler_backend: str = "pillow"
    # Used only when automatic client-anchor location is explicitly disabled.
    fixed_signal_x: int = 8
    fixed_signal_y: int = 8
    fixed_signal_block_size: int = 10
    fixed_signal_block_gap: int = 2
    sampling_interval_ms: int = 50
    max_dispatch_per_second: int = 10
    max_wheel_dispatch_per_second: int = 5
    wow_process_names: str = "wow.exe,world of warcraft.exe"
    ui_link_wait_seconds: int = 30
    log_level: str = "INFO"
    show_window_on_boot: bool = True
    tray_notifications: bool = True
    auto_start_ui_linked: bool = True
    exit_confirmation: bool = True
    diagnostics_enabled: bool = False
    # Retain one JSONL row per SendInput only for focused troubleshooting.
    full_trace_debug: bool = False
    # Optional, diagnostics-only mapping export source.  This is never used for
    # physical-input classification or runtime dispatch decisions.
    wow_savedvariables_path: str = ""
    auto_dispatch_exempt_keys: tuple[str, ...] = ("W", "A", "S", "D", "SPACE")
    manual_priority_mode: str = "balanced"
    manual_priority_custom_recovery_ms: int = 30
    manual_priority_custom_freshness_frames: int = 2
    manual_priority_custom_replay_guard_ms: int = 150
    # The status host is tray-first. Persist its last non-minimized rectangle so
    # startup and tray restore return to the user's established workspace.
    window_width: int = 600
    window_height: int = 1000
    window_x: int | None = None
    window_y: int | None = None
    last_boot_marker: str | None = None
    # Verified TEAP geometry survives process restart as a *hint*. It is never
    # trusted for input until a new live frame passes full TEAP validation.
    signal_layout_cache: dict | None = None

    @classmethod
    def defaults(cls) -> "AppSettings":
        return cls()

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict | None) -> "AppSettings":
        if not isinstance(data, dict):
            return cls.defaults()
        allowed = {field.name for field in fields(cls)}
        normalized = {key: value for key, value in data.items() if key in allowed}
        # 0.9.39 shortened the product recovery defaults. Migrate only the exact
        # legacy custom triplet so deliberately tuned custom values remain intact.
        try:
            stored_schema = int(data.get("schema_version", data.get("schemaVersion", 1)))
        except (TypeError, ValueError):
            stored_schema = 1
        if stored_schema < SETTINGS_SCHEMA_VERSION:
            try:
                is_legacy_triplet = (
                    str(normalized.get("manual_priority_mode", "balanced")).strip().lower() == "custom"
                    and int(normalized.get("manual_priority_custom_recovery_ms", 80)) == 80
                    and int(normalized.get("manual_priority_custom_freshness_frames", 2)) == 2
                    and int(normalized.get("manual_priority_custom_replay_guard_ms", 1000)) == 1000
                )
            except (TypeError, ValueError):
                is_legacy_triplet = False
            if is_legacy_triplet:
                normalized.update({
                    "manual_priority_custom_recovery_ms": 30,
                    "manual_priority_custom_freshness_frames": 2,
                    "manual_priority_custom_replay_guard_ms": 150,
                })
        normalized["schema_version"] = SETTINGS_SCHEMA_VERSION
        try:
            settings = cls(**normalized)
            return settings.normalized()
        except (TypeError, ValueError):
            return cls.defaults()

    def normalized(self) -> "AppSettings":
        interval = max(20, min(500, int(self.sampling_interval_ms)))
        wait_seconds = max(1, min(600, int(self.ui_link_wait_seconds)))
        max_dispatch = max(5, min(20, int(self.max_dispatch_per_second)))
        max_wheel_dispatch = max(1, min(5, int(self.max_wheel_dispatch_per_second)))
        profile_id = str(self.profile_id or "laptop").strip() or "laptop"
        log_level = str(self.log_level or "INFO").upper()
        if log_level not in {"DEBUG", "INFO", "WARNING", "ERROR"}:
            log_level = "INFO"
        manual_priority_mode = str(self.manual_priority_mode or "balanced").strip().lower()
        if manual_priority_mode not in {"aggressive", "balanced", "manual_first", "custom"}:
            manual_priority_mode = "balanced"
        manual_priority_custom_recovery_ms = max(0, min(1500, int(self.manual_priority_custom_recovery_ms)))
        manual_priority_custom_freshness_frames = max(1, min(2, int(self.manual_priority_custom_freshness_frames)))
        manual_priority_custom_replay_guard_ms = max(0, min(1500, int(self.manual_priority_custom_replay_guard_ms)))
        window_width = max(450, min(900, int(self.window_width)))
        window_height = max(900, min(2000, int(self.window_height)))
        window_x = _normalize_window_coordinate(self.window_x)
        window_y = _normalize_window_coordinate(self.window_y)
        signal_layout_cache = _normalize_signal_layout_cache(self.signal_layout_cache)
        # A single coordinate is not useful for reproducible restore behavior;
        # retain a position only when both axes are known.
        if window_x is None or window_y is None:
            window_x = None
            window_y = None
        from tek.src.keyboard_whitelist import normalize_keys

        auto_dispatch_exempt_keys = normalize_keys(self.auto_dispatch_exempt_keys)
        signal_sampler_backend = str(self.signal_sampler_backend or "pillow").strip().lower()
        # Preserve the original safe backend contract while extending it with
        # explicit P4-C Auto / GDI-BitBlt modes.
        if signal_sampler_backend not in {"pillow", "gdi"} and signal_sampler_backend not in {"auto", "gdi_blt"}:
            signal_sampler_backend = "pillow"
        return AppSettings(
            schema_version=SETTINGS_SCHEMA_VERSION,
            profile_id=profile_id,
            auto_locate_signal=bool(self.auto_locate_signal),
            signal_sampler_backend=signal_sampler_backend,
            # Virtual desktops can place secondary monitors at negative coordinates.
            fixed_signal_x=max(-32768, min(32767, int(self.fixed_signal_x))),
            fixed_signal_y=max(-32768, min(32767, int(self.fixed_signal_y))),
            fixed_signal_block_size=max(4, min(64, int(self.fixed_signal_block_size))),
            fixed_signal_block_gap=max(0, min(32, int(self.fixed_signal_block_gap))),
            sampling_interval_ms=interval,
            max_dispatch_per_second=max_dispatch,
            max_wheel_dispatch_per_second=max_wheel_dispatch,
            wow_process_names=str(self.wow_process_names or "wow.exe,world of warcraft.exe"),
            ui_link_wait_seconds=wait_seconds,
            log_level=log_level,
            show_window_on_boot=bool(self.show_window_on_boot),
            tray_notifications=bool(self.tray_notifications),
            auto_start_ui_linked=bool(self.auto_start_ui_linked),
            exit_confirmation=bool(self.exit_confirmation),
            diagnostics_enabled=bool(self.diagnostics_enabled),
            full_trace_debug=bool(self.full_trace_debug),
            wow_savedvariables_path=str(self.wow_savedvariables_path or "").strip(),
            auto_dispatch_exempt_keys=auto_dispatch_exempt_keys,
            manual_priority_mode=manual_priority_mode,
            manual_priority_custom_recovery_ms=manual_priority_custom_recovery_ms,
            manual_priority_custom_freshness_frames=manual_priority_custom_freshness_frames,
            manual_priority_custom_replay_guard_ms=manual_priority_custom_replay_guard_ms,
            window_width=window_width,
            window_height=window_height,
            window_x=window_x,
            window_y=window_y,
            last_boot_marker=self.last_boot_marker,
            signal_layout_cache=signal_layout_cache,
        )

    def allowed_process_names(self) -> tuple[str, ...]:
        names = tuple(
            name.strip().lower()
            for name in self.wow_process_names.split(",")
            if name.strip()
        )
        return names or ("wow.exe", "world of warcraft.exe")


def _normalize_window_coordinate(value) -> int | None:
    if value is None or value == "":
        return None
    try:
        return max(-32768, min(32767, int(value)))
    except (TypeError, ValueError):
        return None


def _normalize_signal_layout_cache(value) -> dict | None:
    """Validate a cross-start TEAP layout hint without accepting arbitrary JSON."""
    if not isinstance(value, dict):
        return None
    relative = value.get("relative_layout") or value.get("relative")
    layout = value.get("layout")
    if not isinstance(relative, dict) or not isinstance(layout, dict):
        return None
    try:
        normalized_relative = {
            "x_ratio": float(relative["x_ratio"]),
            "y_ratio": float(relative["y_ratio"]),
            "block_size_ratio": float(relative["block_size_ratio"]),
            "block_gap_ratio": float(relative["block_gap_ratio"]),
            "block_count": int(relative.get("block_count", 20)),
            "baseline_client_width": int(relative["baseline_client_width"]),
            "baseline_client_height": int(relative["baseline_client_height"]),
        }
        normalized_layout = {
            "x": int(layout["x"]),
            "y": int(layout["y"]),
            "block_size": int(layout["block_size"]),
            "block_gap": int(layout.get("block_gap", 0)),
            "block_count": int(layout.get("block_count", 20)),
        }
    except (KeyError, TypeError, ValueError):
        return None
    floats = (
        normalized_relative["x_ratio"], normalized_relative["y_ratio"],
        normalized_relative["block_size_ratio"], normalized_relative["block_gap_ratio"],
    )
    if any(number != number or abs(number) > 10.0 for number in floats):
        return None
    if (
        normalized_relative["block_count"] != 20
        or normalized_layout["block_count"] != 20
        or normalized_relative["baseline_client_width"] <= 0
        or normalized_relative["baseline_client_height"] <= 0
        or not (0 < normalized_relative["block_size_ratio"] <= 0.25)
        or not (0 <= normalized_relative["block_gap_ratio"] <= 0.25)
        or not (4 <= normalized_layout["block_size"] <= 128)
        or not (0 <= normalized_layout["block_gap"] <= 64)
    ):
        return None
    return {
        "schema_version": 1,
        "relative_layout": normalized_relative,
        "layout": normalized_layout,
    }


@dataclass(frozen=True)
class SettingsImportResult:
    settings: AppSettings
    warnings: tuple[str, ...] = ()


def windows_boot_marker() -> str:
    """Return a stable marker for the current Windows boot session.

    The marker is only used to decide whether to show the compact status window
    on the first TEK launch after a reboot. The rounded boot timestamp avoids
    a changing marker during one Windows session.
    """

    if os.name == "nt":
        try:
            import ctypes

            uptime_ms = int(ctypes.windll.kernel32.GetTickCount64())
            boot_epoch = int(time.time() - uptime_ms / 1000.0)
            return f"windows:{boot_epoch // 60}"
        except Exception:
            pass
    # Tests and non-Windows development hosts only need a session-stable marker.
    return f"host:{os.getpid()}"


class SettingsStore:
    def __init__(self, path: str | Path):
        self.path = Path(path)

    def load(self) -> AppSettings:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, TypeError):
            return AppSettings.defaults()
        return AppSettings.from_dict(data)

    def save(self, settings: AppSettings) -> AppSettings:
        normalized = settings.normalized()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        with temporary.open("w", encoding="utf-8") as file:
            json.dump(normalized.to_dict(), file, ensure_ascii=False, indent=2)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, self.path)
        return normalized

    def save_window_geometry(self, *, width: int, height: int, x: int, y: int) -> AppSettings:
        """Persist the tray host rectangle without touching unrelated settings.

        Geometry is intentionally stored in the same user settings document so
        it survives process restart, hide/show from the tray and TEK.exe rebuilds.
        Validation stays in :meth:`AppSettings.normalized`.
        """
        current = self.load()
        merged = {
            **current.to_dict(),
            "window_width": width,
            "window_height": height,
            "window_x": x,
            "window_y": y,
        }
        return self.save(AppSettings.from_dict(merged))

    def should_show_window_after_boot(self, settings: AppSettings, *, boot_marker: str | None = None) -> tuple[AppSettings, bool]:
        marker = boot_marker or windows_boot_marker()
        should_show = settings.show_window_on_boot and settings.last_boot_marker != marker
        updated = AppSettings.from_dict({**settings.to_dict(), "last_boot_marker": marker})
        self.save(updated)
        return updated, should_show

    def export_to(self, destination: str | Path) -> None:
        settings = self.load()
        target = Path(destination)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(settings.to_dict(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def import_with_result(self, source: str | Path) -> SettingsImportResult:
        """Import settings without letting a malformed whitelist erase it.

        Older releases briefly serialized the whitelist editor's tuple through
        ``StringVar``.  That legacy representation is accepted.  A truly
        malformed whitelist keeps the existing local list and produces a clear
        warning for the caller to display.
        """

        data = json.loads(Path(source).read_text(encoding="utf-8-sig"))
        if not isinstance(data, dict):
            raise ValueError("设置文件根节点必须是 JSON 对象。")

        current = self.load()
        merged = dict(data)
        warnings: list[str] = []
        from tek.src.keyboard_whitelist import parse_keys

        if "auto_dispatch_exempt_keys" in data:
            parsed = parse_keys(data.get("auto_dispatch_exempt_keys"))
            if parsed.valid:
                merged["auto_dispatch_exempt_keys"] = list(parsed.keys)
                if parsed.discarded:
                    names = "、".join(parsed.discarded)
                    warnings.append(f"已忽略不支持或不能单独加入的连发介入按键：{names}。")
            else:
                merged["auto_dispatch_exempt_keys"] = list(current.auto_dispatch_exempt_keys)
                warnings.append("导入文件中的连发介入白名单格式无法识别，已保留当前本地白名单。")
        else:
            merged["auto_dispatch_exempt_keys"] = list(current.auto_dispatch_exempt_keys)
            warnings.append("导入文件未包含连发介入白名单，已保留当前本地白名单。")

        saved = self.save(AppSettings.from_dict(merged))
        return SettingsImportResult(settings=saved, warnings=tuple(warnings))

    def import_from(self, source: str | Path) -> AppSettings:
        """Compatibility wrapper returning only the saved settings object."""

        return self.import_with_result(source).settings
