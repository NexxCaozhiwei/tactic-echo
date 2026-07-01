from __future__ import annotations

import argparse
import logging
import sys

from tek.app.app_paths import AppPaths
from tek.app.crash_handler import configure_logging, write_crash
from tek.app.settings_store import SettingsStore
from tek.app.single_instance import SingleInstance
from tek.app.tray_controller import TrayController
from tek.app.worker_controller import WorkerController
from tek.src.windows_display import enable_per_monitor_dpi_awareness
from tek.src.sendinput_acceptance import run_sendinput_acceptance, write_acceptance_evidence
from tek.runtime.status_store import StatusStore


def _parse_acceptance_args(argv: list[str] | None):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--sendinput-acceptance", action="store_true")
    parser.add_argument("--confirm", default="")
    parser.add_argument("--expected-process", default="notepad.exe")
    parser.add_argument("--binding", default="Q")
    args, _ = parser.parse_known_args(argv or [])
    return args


def main(argv: list[str] | None = None) -> int:
    dpi_awareness = enable_per_monitor_dpi_awareness()
    paths = AppPaths.from_environment()
    paths.ensure()
    settings_store = SettingsStore(paths.settings_json)
    settings = settings_store.load()
    configure_logging(paths, level=settings.log_level)
    logging.info("DPI awareness: %s", dpi_awareness.to_dict())

    acceptance_args = _parse_acceptance_args(argv)
    if acceptance_args.sendinput_acceptance:
        result = run_sendinput_acceptance(
            confirmation=acceptance_args.confirm,
            expected_process=acceptance_args.expected_process,
            binding=acceptance_args.binding,
        )
        evidence = write_acceptance_evidence(result, paths.diagnostics)
        logging.info("SendInput acceptance: %s; evidence=%s", result.to_dict(), evidence)
        return 0 if result.ok else 2

    instance = SingleInstance(paths.root / "tek.lock")
    if not instance.acquire():
        # The active host polls this tiny request file and raises its own status
        # window. The second TEK.exe never creates a second worker or tray icon.
        try:
            paths.activation_request.write_text("show\n", encoding="utf-8")
        except OSError:
            pass
        logging.info("TEK already running; requested existing status window")
        return 0

    try:
        settings, show_initial_window = settings_store.should_show_window_after_boot(settings)
        worker = WorkerController(
            paths=paths,
            status_store=StatusStore(paths.status_json),
            settings_store=settings_store,
        )
        logging.info("TEK desktop host started")
        TrayController(worker, settings_store, paths).run(show_initial_window=show_initial_window)
        worker.stop()
        logging.info("TEK desktop host stopped")
        return 0
    except Exception as error:
        write_crash(paths, error)
        logging.exception("TEK desktop host crashed")
        return 2
    finally:
        instance.release()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
