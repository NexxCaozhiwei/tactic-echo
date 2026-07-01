from __future__ import annotations

import os
import json
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path


APP_DIR_NAME = "TacticEcho"


@dataclass(frozen=True)
class AppPaths:
    root: Path
    logs: Path
    profiles: Path
    config: Path
    crash: Path
    diagnostics: Path
    tray_log: Path
    status_json: Path
    settings_json: Path
    activation_request: Path

    @classmethod
    def from_environment(cls) -> "AppPaths":
        local_app_data = os.environ.get("LOCALAPPDATA")
        base = Path(local_app_data) if local_app_data else Path.home() / "AppData" / "Local"
        return cls.from_root(base / APP_DIR_NAME)

    @classmethod
    def from_root(cls, root: str | Path) -> "AppPaths":
        root = Path(root)
        logs = root / "logs"
        return cls(
            root=root,
            logs=logs,
            profiles=root / "profiles",
            config=root / "config",
            crash=root / "crash",
            diagnostics=root / "diagnostics",
            tray_log=logs / "tek-tray.log",
            status_json=logs / "tek-status.json",
            settings_json=root / "config" / "settings.json",
            activation_request=root / "config" / "show-window.request",
        )

    def ensure(self) -> None:
        for path in (self.root, self.logs, self.profiles, self.config, self.crash, self.diagnostics):
            path.mkdir(parents=True, exist_ok=True)
        self.ensure_default_profile()

    def trace_path_for_today(self) -> Path:
        from datetime import datetime

        return self.logs / f"tek-trace-{datetime.now().strftime('%Y%m%d')}.jsonl"

    def default_profile_path(self) -> Path:
        return self.profiles / "laptop.json"

    def ensure_default_profile(self) -> None:
        target = self.default_profile_path()
        source = resource_path("examples/profiles/laptop.json")
        if not source.exists():
            return

        if not target.exists():
            shutil.copyfile(source, target)
            return

        try:
            bundled = json.loads(source.read_text(encoding="utf-8-sig"))
            current = json.loads(target.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError):
            return

        if (
            current.get("profileId") == bundled.get("profileId") == "laptop"
            and current.get("profileFingerprint") == bundled.get("profileFingerprint")
            and current.get("catalogFingerprint") != bundled.get("catalogFingerprint")
        ):
            shutil.copyfile(source, target)


def resource_path(relative_path: str) -> Path:
    base = getattr(sys, "_MEIPASS", None)
    if base:
        return Path(base) / relative_path
    return Path(__file__).resolve().parents[2] / relative_path
