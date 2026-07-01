from __future__ import annotations

import json
import os
import subprocess
import threading
import time

from tek.app.app_paths import AppPaths, resource_path
from tek.app.settings_store import SettingsStore
from tek.app.status_window import StatusWindow
from tek.app.worker_controller import WorkerController
from tek.runtime.status_mapper import status_color, tooltip_text


def menu_labels(snapshot, *, paused: bool = False) -> list[str]:
    labels = [f"状态：{snapshot.process_state}"]
    if snapshot.worker_alive:
        labels.extend(["恢复" if paused else "暂停", "停止 TEK"])
    else:
        labels.extend(["启动 UI 联动", "启动 Dry-run"])
    labels.extend(["打开状态窗口", "设置", "打开日志目录", "复制当前状态", "退出 TEK"])
    return labels


class TrayController:
    def __init__(self, worker: WorkerController, settings_store: SettingsStore, paths: AppPaths):
        self.worker = worker
        self.settings_store = settings_store
        self.paths = paths
        self.status_window = StatusWindow(worker, settings_store)
        self._icon = None
        self._stop_event = threading.Event()
        self._last_color: str | None = None

    def run(self, *, show_initial_window: bool = False) -> None:
        settings = self.settings_store.load()
        if settings.auto_start_ui_linked:
            self.worker.start_ui_linked()
        if show_initial_window:
            self.status_window.show("status")
        if self._try_pystray():
            return
        # Development fallback only. The production TEK.exe build includes
        # pystray/pywin32 and reaches the branch above.
        self.status_window.show("status")
        while not self._stop_event.wait(0.2):
            self._consume_activation_request()

    def show_status_window(self, page: str = "status") -> None:
        self.status_window.show(page)

    def open_logs(self) -> None:
        log_dir = self.worker.snapshot.log_dir or str(self.paths.logs)
        if os.name == "nt":
            os.startfile(log_dir)  # type: ignore[attr-defined]
        else:
            subprocess.Popen(["xdg-open", log_dir])

    def copy_status(self) -> None:
        try:
            import tkinter as tk

            root = tk.Tk()
            root.withdraw()
            root.clipboard_clear()
            root.clipboard_append(json.dumps(self.worker.snapshot.to_dict(), ensure_ascii=False, indent=2))
            root.update()
            root.destroy()
        except Exception:
            pass

    def toggle_pause(self) -> None:
        if self.worker.paused:
            self.worker.resume()
        else:
            self.worker.pause()

    def quit(self) -> None:
        if self.settings_store.load().exit_confirmation:
            self.status_window.ask_exit_confirm(self._finish_quit)
        else:
            threading.Thread(target=self._finish_quit, daemon=True).start()

    def _finish_quit(self) -> None:
        self.worker.stop()
        self.status_window.shutdown()
        self._stop_event.set()
        if self._icon:
            self._icon.stop()

    def _try_pystray(self) -> bool:
        try:
            import pystray
            from PIL import Image, ImageDraw
        except Exception:
            return False

        def make_image():
            snapshot = self.worker.snapshot
            color = status_color(snapshot)
            state_image = load_state_icon(Image, color)
            if state_image:
                return state_image.convert("RGBA").resize((64, 64))

            image = load_base_icon(Image) or Image.new("RGBA", (64, 64), (238, 240, 243, 255))
            image = image.convert("RGBA").resize((64, 64))
            draw = ImageDraw.Draw(image)
            palette = {
                "gray": (120, 120, 120, 255),
                "blue": (32, 122, 240, 255),
                "green": (30, 185, 82, 255),
                "yellow": (230, 172, 15, 255),
                "red": (214, 58, 58, 255),
            }
            draw.ellipse((40, 40, 61, 61), fill=palette.get(color, palette["blue"]), outline=(255, 255, 255, 255), width=2)
            return image

        def refresh():
            if self._icon:
                snapshot = self.worker.snapshot
                color = status_color(snapshot)
                self._icon.icon = make_image()
                self._icon.title = tooltip_text(snapshot)
                self._notify_error_transition(color, snapshot)

        menu = pystray.Menu(
            pystray.MenuItem(lambda _: f"状态：{self.worker.snapshot.process_state}", None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem(
                "启动 UI 联动",
                lambda _: self.worker.start_ui_linked(),
                visible=lambda _: not self.worker.is_running(),
            ),
            pystray.MenuItem(
                "启动 Dry-run",
                lambda _: self.worker.start_dry_run(),
                visible=lambda _: not self.worker.is_running(),
            ),
            pystray.MenuItem(
                lambda _: "恢复" if self.worker.paused else "暂停",
                lambda _: self.toggle_pause(),
                visible=lambda _: self.worker.is_running(),
            ),
            pystray.MenuItem("停止 TEK", lambda _: self.worker.stop(), visible=lambda _: self.worker.is_running()),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("打开状态窗口", lambda _: self.status_window.toggle(), default=True),
            pystray.MenuItem("设置", lambda _: self.show_status_window("general")),
            pystray.MenuItem("打开日志目录", lambda _: self.open_logs()),
            pystray.MenuItem("复制当前状态", lambda _: self.copy_status()),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("退出 TEK", lambda _: self.quit()),
        )
        self._icon = pystray.Icon("TEK", make_image(), "Tactic Echo Key", menu)

        def updater():
            while self._icon and not self._stop_event.is_set():
                refresh()
                self._consume_activation_request()
                time.sleep(0.6)

        threading.Thread(target=updater, name="TEKTrayUpdater", daemon=True).start()
        self._icon.run()
        return True

    def _consume_activation_request(self) -> None:
        request = self.paths.activation_request
        if not request.exists():
            return
        try:
            request.unlink()
        except OSError:
            return
        self.show_status_window()

    def _notify_error_transition(self, color: str, snapshot) -> None:
        if color == self._last_color:
            return
        previous = self._last_color
        self._last_color = color
        if color != "red" or not self.settings_store.load().tray_notifications:
            return
        if not self._icon:
            return
        reason = snapshot.last_reason or snapshot.error_message or "未知原因"
        try:
            self._icon.notify(f"{snapshot.process_state}: {reason}", "Tactic Echo Key")
        except Exception:
            # Notification support differs by Windows shell; the red tray state
            # remains the source of truth even when a toast cannot be shown.
            pass


def has_asset_icon() -> bool:
    return any(path.exists() for path in icon_candidates())


def load_base_icon(image_module):
    for path in icon_candidates():
        if path.exists():
            return image_module.open(path)
    return None


def load_state_icon(image_module, color: str):
    for path in state_icon_candidates(color):
        if path.exists():
            return image_module.open(path)
    return None


def state_icon_candidates(color: str):
    name_by_color = {
        "gray": "TEK_GREY.png",
        "blue": "TEK_BLUE.png",
        "green": "TEK_GREEN.png",
        "yellow": "TEK_YELLOW.png",
        "red": "TEK_RED.png",
    }
    name = name_by_color.get(color)
    return [resource_path(f"tek/assets/{name}")] if name else []


def icon_candidates():
    return [
        resource_path("tek/assets/tek.ico"),
        resource_path("tek/assets/tek.png"),
    ]
