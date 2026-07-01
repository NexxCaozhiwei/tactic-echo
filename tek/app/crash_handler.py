from __future__ import annotations

import logging
import traceback
from logging.handlers import RotatingFileHandler
from datetime import datetime

from tek.app.app_paths import AppPaths


TRAY_LOG_MAX_BYTES = 2_000_000
TRAY_LOG_BACKUP_COUNT = 3


def configure_logging(paths: AppPaths, *, level: str = "INFO") -> None:
    """Configure bounded tray logging without accumulating duplicate handlers."""
    paths.ensure()
    root = logging.getLogger()
    root.setLevel(getattr(logging, str(level).upper(), logging.INFO))
    for handler in list(root.handlers):
        if getattr(handler, "_tactic_echo_tray_log", False):
            root.removeHandler(handler)
            handler.close()
    handler = RotatingFileHandler(
        paths.tray_log,
        maxBytes=TRAY_LOG_MAX_BYTES,
        backupCount=TRAY_LOG_BACKUP_COUNT,
        encoding="utf-8",
    )
    handler._tactic_echo_tray_log = True  # type: ignore[attr-defined]
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
    root.addHandler(handler)


def write_crash(paths: AppPaths, error: BaseException) -> None:
    paths.crash.mkdir(parents=True, exist_ok=True)
    target = paths.crash / f"crash-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
    target.write_text("".join(traceback.format_exception(error)), encoding="utf-8")

