from __future__ import annotations

import os
import queue
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from tek.app.settings_store import AppSettings, SettingsStore
from tek.app.worker_controller import WorkerController
from tek.runtime.status_mapper import status_color
from tek.src.windows_display import virtual_desktop_bounds


class StatusWindow:
    """Small Chinese TEK status window with compact settings tabs.

    Tk owns its own thread. Tray callbacks only enqueue commands, avoiding
    cross-thread Tk calls from pystray's Windows message loop.
    """

    def __init__(self, worker: WorkerController, settings_store: SettingsStore):
        self.worker = worker
        self.settings_store = settings_store
        self.root: tk.Tk | None = None
        self._thread: threading.Thread | None = None
        self._commands: queue.Queue[tuple[str, object | None]] = queue.Queue()
        self._lock = threading.Lock()
        self._ready = threading.Event()
        self._closed = threading.Event()
        self.values: dict[str, tk.StringVar] = {}
        self._settings_vars: dict[str, tk.Variable] = {}
        self._notebook: ttk.Notebook | None = None
        self._tabs: dict[str, ttk.Frame] = {}
        self._status_dot: tk.Canvas | None = None
        self._ui_button: ttk.Button | None = None
        self._pause_button: ttk.Button | None = None
        self._recover_button: ttk.Button | None = None
        self._profile_box: ttk.Combobox | None = None
        self._settings_hint: tk.StringVar | None = None
        self._geometry_save_after_id: str | None = None
        self._ui_refresh_after_id: str | None = None
        self._window_visible = True
        self._last_saved_window_geometry: tuple[int, int, int, int] | None = None

    def show(self, page: str = "status") -> None:
        with self._lock:
            if not self._thread or not self._thread.is_alive():
                self._ready.clear()
                self._closed.clear()
                self._thread = threading.Thread(target=self._thread_main, name="TEKStatusWindow", daemon=True)
                self._thread.start()
                self._ready.wait(timeout=2.0)
        self._commands.put(("show", page))

    def open_settings(self, page: str = "general") -> None:
        self.show(page)

    def toggle(self) -> None:
        with self._lock:
            alive = bool(self._thread and self._thread.is_alive())
        if not alive:
            self.show("status")
            return
        self._commands.put(("toggle", None))

    def ask_exit_confirm(self, on_confirm) -> None:
        self.show("status")
        self._commands.put(("confirm_exit", on_confirm))

    def shutdown(self) -> None:
        if self._thread and self._thread.is_alive():
            self._commands.put(("shutdown", None))

    def _thread_main(self) -> None:
        root = tk.Tk()
        self.root = root
        root.title("Tactic Echo Key")
        # The status/diagnostics pages intentionally remain usable on high-DPI
        # displays.  The user may resize the tray host within a bounded range;
        # no layout decision depends on a fixed desktop resolution.
        root.minsize(450, 900)
        root.maxsize(900, 2000)
        root.resizable(True, True)
        self._restore_saved_window_geometry()
        root.protocol("WM_DELETE_WINDOW", self._withdraw_window)
        root.bind("<Configure>", self._on_window_configure, add="+")
        self._build(root)
        self._ready.set()
        self._refresh()
        self._drain_commands()
        root.mainloop()
        self.root = None
        self._closed.set()

    @staticmethod
    def _geometry_intersects_desktop(
        *,
        x: int,
        y: int,
        width: int,
        height: int,
        desktop_left: int,
        desktop_top: int,
        desktop_width: int,
        desktop_height: int,
    ) -> bool:
        """Require a visible window fragment before restoring a saved position."""
        if desktop_width <= 0 or desktop_height <= 0:
            return True
        minimum_visible = 80
        desktop_right = desktop_left + desktop_width
        desktop_bottom = desktop_top + desktop_height
        return (
            x + minimum_visible < desktop_right
            and x + width > desktop_left + minimum_visible
            and y + minimum_visible < desktop_bottom
            and y + height > desktop_top + minimum_visible
        )

    def _desktop_rect(self) -> tuple[int, int, int, int]:
        """Return a virtual-desktop rectangle with a Tk fallback for tests."""
        desktop = virtual_desktop_bounds()
        if desktop.width > 0 and desktop.height > 0:
            return desktop.left, desktop.top, desktop.width, desktop.height
        if self.root is None:
            return 0, 0, 0, 0
        try:
            return (
                int(self.root.winfo_vrootx()),
                int(self.root.winfo_vrooty()),
                max(1, int(self.root.winfo_vrootwidth())),
                max(1, int(self.root.winfo_vrootheight())),
            )
        except tk.TclError:
            return 0, 0, 0, 0

    def _restore_saved_window_geometry(self) -> None:
        """Apply the last persisted rectangle, recentering stale off-screen data."""
        if self.root is None:
            return
        settings = self.settings_store.load()
        width = settings.window_width
        height = settings.window_height
        x = settings.window_x
        y = settings.window_y
        if x is None or y is None:
            self.root.geometry(f"{width}x{height}")
            return
        desktop_left, desktop_top, desktop_width, desktop_height = self._desktop_rect()
        if not self._geometry_intersects_desktop(
            x=x,
            y=y,
            width=width,
            height=height,
            desktop_left=desktop_left,
            desktop_top=desktop_top,
            desktop_width=desktop_width,
            desktop_height=desktop_height,
        ):
            x = desktop_left + max(0, (desktop_width - width) // 2)
            y = desktop_top + max(0, (desktop_height - height) // 2)
        self.root.geometry(f"{width}x{height}{x:+d}{y:+d}")
        self._last_saved_window_geometry = (width, height, x, y)

    def _on_window_configure(self, event) -> None:
        if self.root is None or event.widget is not self.root:
            return
        self._schedule_window_geometry_save()

    def _schedule_window_geometry_save(self) -> None:
        if self.root is None:
            return
        if self._geometry_save_after_id:
            try:
                self.root.after_cancel(self._geometry_save_after_id)
            except tk.TclError:
                pass
        self._geometry_save_after_id = self.root.after(350, self._persist_window_geometry)

    def _persist_window_geometry(self, *, force: bool = False) -> None:
        if self.root is None:
            return
        self._geometry_save_after_id = None
        try:
            self.root.update_idletasks()
            width = int(self.root.winfo_width())
            height = int(self.root.winfo_height())
            x = int(self.root.winfo_x())
            y = int(self.root.winfo_y())
        except tk.TclError:
            return
        # Ignore Tk's transient 1x1 geometry while a root is being created or
        # torn down. The last stable rectangle remains intact.
        if width < 450 or height < 900:
            return
        geometry = (width, height, x, y)
        if not force and geometry == self._last_saved_window_geometry:
            return
        try:
            saved = self.settings_store.save_window_geometry(
                width=width,
                height=height,
                x=x,
                y=y,
            )
        except Exception as error:
            # Geometry persistence is advisory and must never break the tray UI.
            self._last_saved_window_geometry = geometry
            return
        self._last_saved_window_geometry = (
            saved.window_width,
            saved.window_height,
            int(saved.window_x or 0),
            int(saved.window_y or 0),
        )

    def _cancel_ui_refresh(self) -> None:
        if self.root is None or not self._ui_refresh_after_id:
            return
        try:
            self.root.after_cancel(self._ui_refresh_after_id)
        except tk.TclError:
            pass
        self._ui_refresh_after_id = None

    def _schedule_ui_refresh(self, delay_ms: int = 500) -> None:
        if self.root is None or not self._window_visible or self._ui_refresh_after_id:
            return
        self._ui_refresh_after_id = self.root.after(delay_ms, self._refresh)

    def _withdraw_window(self) -> None:
        self._persist_window_geometry(force=True)
        self._window_visible = False
        self._cancel_ui_refresh()
        if self.root is not None:
            self.root.withdraw()

    def _build(self, root: tk.Tk) -> None:
        outer = ttk.Frame(root, padding=10)
        outer.pack(fill="both", expand=True)
        notebook = ttk.Notebook(outer)
        notebook.pack(fill="both", expand=True)
        self._notebook = notebook

        for key, title in (("status", "状态"), ("general", "常规"), ("connection", "连接"), ("intervention", "连发介入"), ("diagnostics", "诊断")):
            tab = ttk.Frame(notebook, padding=10)
            notebook.add(tab, text=title)
            self._tabs[key] = tab

        self._build_status_tab(self._tabs["status"])
        self._build_general_tab(self._tabs["general"])
        self._build_connection_tab(self._tabs["connection"])
        self._build_intervention_tab(self._tabs["intervention"])
        self._build_diagnostics_tab(self._tabs["diagnostics"])


    def _build_intervention_tab(self, frame: ttk.Frame) -> None:
        """Build the local dispatch-intervention whitelist editor.

        The page deliberately uses a fixed four-column grid.  It must remain
        usable in the compact tray-host window and must not rely on a wide text
        entry that gets clipped by high-DPI scaling.
        """
        settings = self.settings_store.load()
        self._settings_vars["auto_dispatch_exempt_keys"] = tk.StringVar(
            value=", ".join(settings.auto_dispatch_exempt_keys)
        )
        self._intervention_selected: str | None = None
        self._intervention_capture_armed = False
        self._intervention_capture_status = tk.StringVar(value="录入状态：未开始")
        self._intervention_keys_frame: ttk.Frame | None = None
        self._intervention_key_buttons: dict[str, ttk.Button] = {}

        frame.columnconfigure(0, weight=1)
        ttk.Label(frame, text="连发介入按键", font=("Microsoft YaHei UI", 12, "bold")).grid(
            row=0, column=0, sticky="w"
        )
        ttk.Label(
            frame,
            text="当您真实按住下列键时，TEK 不会暂停自动连发。白名单外的任意键仍会立即触发人工接管。",
            wraplength=520,
            foreground="#666666",
            justify="left",
        ).grid(row=1, column=0, sticky="ew", pady=(4, 10))

        ttk.Separator(frame, orient="horizontal").grid(row=2, column=0, sticky="ew", pady=(0, 10))
        ttk.Label(frame, text="已允许：").grid(row=3, column=0, sticky="w")
        keys_frame = ttk.Frame(frame)
        keys_frame.grid(row=4, column=0, sticky="w", pady=(5, 6))
        self._intervention_keys_frame = keys_frame
        ttk.Label(
            frame,
            text="单击按键标签可选中；再次单击可取消。点击“录入按键”后，直接按一个键即可添加。",
            wraplength=520,
            foreground="#666666",
            justify="left",
        ).grid(row=5, column=0, sticky="ew", pady=(0, 10))

        controls = ttk.Frame(frame)
        controls.grid(row=6, column=0, sticky="w")
        ttk.Button(controls, text="录入按键", width=12, command=self._begin_intervention_capture).grid(
            row=0, column=0, padx=(0, 6), pady=2
        )
        ttk.Button(controls, text="删除选中", width=12, command=self._delete_selected_intervention_key).grid(
            row=0, column=1, padx=(0, 6), pady=2
        )
        ttk.Button(controls, text="恢复默认", width=12, command=self._reset_intervention_keys).grid(
            row=0, column=2, pady=2
        )
        ttk.Label(frame, textvariable=self._intervention_capture_status, foreground="#666666").grid(
            row=7, column=0, sticky="w", pady=(5, 10)
        )

        ttk.Separator(frame, orient="horizontal").grid(row=8, column=0, sticky="ew", pady=(0, 10))
        ttk.Label(frame, text="常用按键").grid(row=9, column=0, sticky="w")
        quick = ttk.Frame(frame)
        quick.grid(row=10, column=0, sticky="w", pady=(5, 10))
        # Fixed four columns prevent control overflow in the compact window.
        for index, key in enumerate(("W", "A", "S", "D", "SPACE", "UP", "DOWN", "LEFT", "RIGHT", "Q", "E")):
            row, column = divmod(index, 4)
            ttk.Button(
                quick,
                text=self._intervention_display_name(key),
                width=12,
                command=lambda selected=key: self._add_intervention_key(selected),
            ).grid(row=row, column=column, padx=(0, 6), pady=3, sticky="w")

        ttk.Button(frame, text="保存连发介入设置", command=self._save_intervention).grid(
            row=11, column=0, sticky="w", pady=(0, 12)
        )
        ttk.Label(
            frame,
            text="提示：将 TAB、ESC、数字键、Q/E/R/F 等技能或界面键加入白名单后，按住这些键时 TEK 仍可能继续派发。",
            wraplength=520,
            foreground="#8a5a00",
            justify="left",
        ).grid(row=12, column=0, sticky="ew")

        # Bind only to this page's toplevel.  The handler returns "break" only
        # while recording, so normal application hotkeys are unaffected.
        frame.winfo_toplevel().bind("<KeyPress>", self._capture_intervention_key, add="+")
        self._refresh_intervention_key_buttons()

    @staticmethod
    def _intervention_display_name(key: str) -> str:
        return {"UP": "↑", "DOWN": "↓", "LEFT": "←", "RIGHT": "→"}.get(key, key)

    def _intervention_keys(self) -> list[str]:
        from tek.src.keyboard_whitelist import normalize_keys
        return list(normalize_keys(self._settings_vars["auto_dispatch_exempt_keys"].get().split(",")))

    def _set_intervention_keys(self, keys: list[str] | tuple[str, ...]) -> None:
        from tek.src.keyboard_whitelist import normalize_keys
        normalized = normalize_keys(keys)
        self._settings_vars["auto_dispatch_exempt_keys"].set(", ".join(normalized))
        if getattr(self, "_intervention_selected", None) not in normalized:
            self._intervention_selected = None
        self._refresh_intervention_key_buttons()

    def _refresh_intervention_key_buttons(self) -> None:
        container = getattr(self, "_intervention_keys_frame", None)
        if container is None:
            return
        for child in container.winfo_children():
            child.destroy()
        self._intervention_key_buttons = {}
        keys = self._intervention_keys()
        if not keys:
            ttk.Label(container, text="（当前没有允许按键）", foreground="#666666").grid(row=0, column=0, sticky="w")
            return
        for index, key in enumerate(keys):
            row, column = divmod(index, 4)
            selected = key == getattr(self, "_intervention_selected", None)
            button = ttk.Button(
                container,
                text=("● " if selected else "") + self._intervention_display_name(key),
                width=12,
                command=lambda selected_key=key: self._toggle_intervention_selection(selected_key),
            )
            button.grid(row=row, column=column, padx=(0, 6), pady=3, sticky="w")
            self._intervention_key_buttons[key] = button

    def _toggle_intervention_selection(self, key: str) -> None:
        self._intervention_selected = None if self._intervention_selected == key else key
        self._refresh_intervention_key_buttons()

    def _add_intervention_key(self, key: str) -> None:
        from tek.src.keyboard_whitelist import canonicalize_key, is_modifier_key
        canonical = canonicalize_key(key)
        if not canonical:
            self._intervention_capture_status.set(f"录入状态：不支持按键 {key}")
            return
        if is_modifier_key(canonical):
            self._intervention_capture_status.set("录入状态：Ctrl、Alt、Shift、Win 不能单独加入白名单")
            return
        values = self._intervention_keys()
        if canonical in values:
            self._intervention_selected = canonical
            self._intervention_capture_status.set(f"录入状态：{self._intervention_display_name(canonical)} 已在白名单中")
        else:
            values.append(canonical)
            self._intervention_selected = canonical
            self._intervention_capture_status.set(f"录入状态：已添加 {self._intervention_display_name(canonical)}")
        self._set_intervention_keys(values)

    def _begin_intervention_capture(self) -> None:
        self._intervention_capture_armed = True
        self._intervention_capture_status.set("录入状态：请直接按下一个键；按 Esc 取消")
        self.root.focus_force() if self.root is not None else None

    def _capture_intervention_key(self, event: tk.Event) -> str | None:
        if not getattr(self, "_intervention_capture_armed", False):
            return None
        from tek.src.keyboard_whitelist import canonicalize_key, is_modifier_key
        # Tk's keysym is preferred.  char is a fallback for printable keys.
        candidate = event.keysym or event.char
        canonical = canonicalize_key(candidate)
        if canonical == "ESC":
            self._intervention_capture_armed = False
            self._intervention_capture_status.set("录入状态：已取消")
            return "break"
        if not canonical:
            self._intervention_capture_status.set(f"录入状态：暂不支持 {candidate or event.keycode}")
            return "break"
        if is_modifier_key(canonical):
            self._intervention_capture_status.set("录入状态：Ctrl、Alt、Shift、Win 不能单独加入；请继续按其他键")
            return "break"
        self._intervention_capture_armed = False
        self._add_intervention_key(canonical)
        return "break"

    def _delete_selected_intervention_key(self) -> None:
        selected = getattr(self, "_intervention_selected", None)
        if not selected:
            self._intervention_capture_status.set("录入状态：请先单击一个已允许按键")
            return
        values = [key for key in self._intervention_keys() if key != selected]
        self._intervention_selected = None
        self._set_intervention_keys(values)
        self._intervention_capture_status.set(f"录入状态：已删除 {self._intervention_display_name(selected)}")

    def _reset_intervention_keys(self) -> None:
        self._intervention_selected = None
        self._intervention_capture_armed = False
        self._set_intervention_keys(["W", "A", "S", "D", "SPACE"])
        self._intervention_capture_status.set("录入状态：已恢复默认 W A S D SPACE")

    def _save_intervention(self) -> None:
        keys = self._intervention_keys()
        updated = AppSettings.from_dict({**self.settings_store.load().to_dict(), "auto_dispatch_exempt_keys": list(keys)})
        self.settings_store.save(updated)
        self._set_intervention_keys(list(updated.auto_dispatch_exempt_keys))
        messagebox.showinfo("TEK", "连发介入按键已保存。重新启动 UI 联动后生效。")

    def _build_status_tab(self, frame: ttk.Frame) -> None:
        top = ttk.Frame(frame)
        top.pack(fill="x", pady=(0, 8))
        ttk.Label(top, text="TEK 状态", font=("Microsoft YaHei UI", 12, "bold")).pack(side="left")
        self._status_dot = tk.Canvas(top, width=18, height=18, highlightthickness=0)
        self._status_dot.pack(side="right")

        grid = ttk.Frame(frame)
        grid.pack(fill="x", expand=False)
        fields = [
            ("状态", "process_state"),
            ("模式", "mode"),
            ("WoW 前台", "wow_foreground"),
            ("信号", "signal_found"),
            ("采样后端", "sampler_backend"),
            ("最近动作", "last_action"),
            ("战斗状态", "combat_state"),
            ("协议 / Token", "protocol_token"),
            ("监控", "monitor_state"),
            ("手动接管", "manual_gate"),
            ("连发频率", "dispatch_rate"),
            ("最近结果", "last_reason"),
        ]
        for row, (label, key) in enumerate(fields):
            ttk.Label(grid, text=label).grid(row=row, column=0, sticky="w", padx=(0, 8), pady=4)
            self.values[key] = tk.StringVar(value="-")
            ttk.Label(grid, textvariable=self.values[key], width=38, wraplength=295).grid(
                row=row, column=1, sticky="w", pady=4
            )

        self.values["notice"] = tk.StringVar(value="正在等待状态更新")
        ttk.Label(frame, textvariable=self.values["notice"], foreground="#666666", wraplength=380).pack(
            fill="x", pady=(10, 8)
        )

        controls = ttk.Frame(frame)
        controls.pack(fill="x", pady=(2, 0))
        self._ui_button = ttk.Button(controls, text="启动 UI 联动", command=self._start_ui_linked)
        self._ui_button.grid(row=0, column=0, padx=(0, 6), pady=3, sticky="ew")
        self._pause_button = ttk.Button(controls, text="暂停", command=self._toggle_pause)
        self._pause_button.grid(row=0, column=1, padx=(0, 6), pady=3, sticky="ew")
        ttk.Button(controls, text="停止", command=self.worker.stop).grid(row=0, column=2, pady=3, sticky="ew")
        ttk.Button(controls, text="Dry-run", command=self.worker.start_dry_run).grid(row=1, column=0, padx=(0, 6), pady=3, sticky="ew")
        ttk.Button(controls, text="设置", command=lambda: self._select_tab("general")).grid(
            row=1, column=1, padx=(0, 6), pady=3, sticky="ew"
        )
        ttk.Button(controls, text="日志", command=self.open_logs).grid(row=1, column=2, pady=3, sticky="ew")
        self._recover_button = ttk.Button(controls, text="恢复", command=self.worker.recover_error)
        self._recover_button.grid(row=2, column=0, columnspan=3, pady=(5, 0), sticky="ew")
        self._recover_button.grid_remove()
        for column in range(3):
            controls.columnconfigure(column, weight=1)

    def _build_general_tab(self, frame: ttk.Frame) -> None:
        settings = self.settings_store.load()
        self._settings_vars.update(
            auto_start_ui_linked=tk.BooleanVar(value=settings.auto_start_ui_linked),
            show_window_on_boot=tk.BooleanVar(value=settings.show_window_on_boot),
            tray_notifications=tk.BooleanVar(value=settings.tray_notifications),
            exit_confirmation=tk.BooleanVar(value=settings.exit_confirmation),
            diagnostics_enabled=tk.BooleanVar(value=settings.diagnostics_enabled),
            full_trace_debug=tk.BooleanVar(value=settings.full_trace_debug),
            manual_priority_mode=tk.StringVar(value=settings.manual_priority_mode),
            manual_priority_custom_recovery_ms=tk.StringVar(value=str(settings.manual_priority_custom_recovery_ms)),
            manual_priority_custom_freshness_frames=tk.StringVar(value=str(settings.manual_priority_custom_freshness_frames)),
            manual_priority_custom_replay_guard_ms=tk.StringVar(value=str(settings.manual_priority_custom_replay_guard_ms)),
        )
        for key, label in (
            ("auto_start_ui_linked", "启动 TEK 后自动进入 UI 联动等待"),
            ("show_window_on_boot", "每次 Windows 重启后的首次启动显示状态窗口"),
            ("tray_notifications", "仅错误时显示 Windows 通知"),
            ("exit_confirmation", "退出前确认，并停止 TEK worker"),
            ("diagnostics_enabled", "启用高级诊断信息"),
            ("full_trace_debug", "完整 Trace 调试（逐条记录成功按键，可能增加磁盘写入）"),
        ):
            ttk.Checkbutton(frame, text=label, variable=self._settings_vars[key]).pack(anchor="w", pady=5)

        ttk.Label(frame, text="手动接管恢复策略：").pack(anchor="w", pady=(12, 2))
        ttk.Combobox(
            frame,
            textvariable=self._settings_vars["manual_priority_mode"],
            values=("aggressive", "balanced", "manual_first", "custom"),
            state="readonly",
            width=20,
        ).pack(anchor="w")
        ttk.Label(
            frame,
            text=("aggressive：释放后 0ms + 1 帧 freshness + 100ms 回放保护；\n"
                  "balanced：30ms + 2 帧 freshness + 150ms；manual_first：250ms + 2 帧 + 500ms。\n"
                  "所有非豁免键盘输入按住期间持续让步；白名单键不进入恢复状态机；鼠标输入全部忽略。"),
            foreground="#666666",
            wraplength=620,
            justify="left",
        ).pack(anchor="w", pady=(2, 8))

        custom = ttk.LabelFrame(frame, text="自定义模式", padding=(8, 6))
        custom.pack(fill="x", pady=(2, 8))
        ttk.Label(custom, text="释放后等待（ms）").grid(row=0, column=0, sticky="w")
        tk.Spinbox(custom, from_=0, to=1500, increment=10, textvariable=self._settings_vars["manual_priority_custom_recovery_ms"], width=8).grid(row=0, column=1, padx=(8, 18), sticky="w")
        ttk.Label(custom, text="新 freshness 帧").grid(row=0, column=2, sticky="w")
        tk.Spinbox(custom, from_=1, to=2, increment=1, textvariable=self._settings_vars["manual_priority_custom_freshness_frames"], width=5).grid(row=0, column=3, padx=(8, 18), sticky="w")
        ttk.Label(custom, text="回放保护（ms）").grid(row=1, column=0, sticky="w", pady=(7, 0))
        tk.Spinbox(custom, from_=0, to=1500, increment=10, textvariable=self._settings_vars["manual_priority_custom_replay_guard_ms"], width=8).grid(row=1, column=1, padx=(8, 18), pady=(7, 0), sticky="w")
        ttk.Label(custom, text="仅 custom 模式使用；范围 0–1500ms，freshness 为 1 或 2 帧。当前推荐默认：30ms、2 帧、150ms。", foreground="#666666", wraplength=560).grid(row=2, column=0, columnspan=4, sticky="w", pady=(7, 0))

        self._settings_hint = tk.StringVar(value="常规设置保存后，在下次启动 UI 联动时生效。")
        ttk.Label(frame, textvariable=self._settings_hint, foreground="#666666", wraplength=620).pack(fill="x", pady=(12, 8))
        ttk.Button(frame, text="保存常规设置", command=self._save_general).pack(anchor="e")

    def _build_connection_tab(self, frame: ttk.Frame) -> None:
        settings = self.settings_store.load()
        self._settings_vars.update(
            profile_id=tk.StringVar(value=settings.profile_id),
            auto_locate_signal=tk.BooleanVar(value=settings.auto_locate_signal),
            signal_sampler_backend=tk.StringVar(value=settings.signal_sampler_backend),
            fixed_signal_x=tk.StringVar(value=str(settings.fixed_signal_x)),
            fixed_signal_y=tk.StringVar(value=str(settings.fixed_signal_y)),
            sampling_interval_ms=tk.StringVar(value=str(settings.sampling_interval_ms)),
            max_dispatch_per_second=tk.StringVar(value=str(settings.max_dispatch_per_second)),
            max_wheel_dispatch_per_second=tk.StringVar(value=str(settings.max_wheel_dispatch_per_second)),
            wow_process_names=tk.StringVar(value=settings.wow_process_names),
            ui_link_wait_seconds=tk.StringVar(value=str(settings.ui_link_wait_seconds)),
        )
        ttk.Label(frame, text="Profile（仅停止后可切换）").pack(anchor="w")
        self._profile_box = ttk.Combobox(
            frame,
            textvariable=self._settings_vars["profile_id"],
            values=self._profile_names(),
            state="readonly",
            width=30,
        )
        self._profile_box.pack(fill="x", pady=(2, 8))
        ttk.Checkbutton(frame, text="后台自动定位 TEAP（固定客户区左上）", variable=self._settings_vars["auto_locate_signal"]).pack(anchor="w")
        ttk.Label(
            frame,
            text="自动模式只在 WoW 客户区左上小区域寻找 v3 的 T / E / 3 头；定位后需连续两帧完整校验。未验证时不会使用固定坐标或派发输入。",
            foreground="#666666",
            wraplength=390,
        ).pack(anchor="w", pady=(2, 5))

        sampler = ttk.Frame(frame)
        sampler.pack(fill="x", pady=(7, 2))
        ttk.Label(sampler, text="运行期采样后端").pack(side="left")
        ttk.Combobox(
            sampler,
            textvariable=self._settings_vars["signal_sampler_backend"],
            values=("auto", "pillow", "gdi", "gdi_blt"),
            state="readonly",
            width=12,
        ).pack(side="left", padx=(10, 0))
        ttk.Label(
            frame,
            text="auto：先用 Pillow 定位并连续验证，再自动切换到 GDI BitBlt 条带采样；任一会话内连续失败会回退 Pillow。",
            foreground="#666666",
            wraplength=390,
        ).pack(anchor="w", pady=(0, 5))

        fixed = ttk.Frame(frame)
        fixed.pack(fill="x", pady=8)
        ttk.Label(fixed, text="手动固定布局 X / Y（仅关闭自动定位时使用）").grid(row=0, column=0, sticky="w")
        ttk.Entry(fixed, textvariable=self._settings_vars["fixed_signal_x"], width=8).grid(row=0, column=1, padx=4)
        ttk.Entry(fixed, textvariable=self._settings_vars["fixed_signal_y"], width=8).grid(row=0, column=2, padx=4)
        ttk.Button(fixed, text="取鼠标位置", command=self._capture_pointer).grid(row=0, column=3, padx=(4, 0))

        interval = ttk.Frame(frame)
        interval.pack(fill="x", pady=4)
        ttk.Label(interval, text="采样间隔（ms）").grid(row=0, column=0, sticky="w")
        tk.Spinbox(interval, from_=20, to=500, increment=10, textvariable=self._settings_vars["sampling_interval_ms"], width=8).grid(
            row=0, column=1, padx=4
        )
        ttk.Label(interval, text="默认 50；建议 50–100", foreground="#666666").grid(row=0, column=2, sticky="w")

        rate = ttk.LabelFrame(frame, text="连续按键频率", padding=(8, 6))
        rate.pack(fill="x", pady=(8, 6))
        ttk.Label(rate, text="普通按键连发频率（次/秒）").grid(row=0, column=0, sticky="w")
        tk.Spinbox(
            rate,
            from_=5,
            to=20,
            increment=1,
            textvariable=self._settings_vars["max_dispatch_per_second"],
            width=8,
        ).grid(row=0, column=1, padx=(8, 0), sticky="w")
        ttk.Label(rate, text="滚轮连发频率（次/秒）").grid(row=1, column=0, sticky="w", pady=(7, 0))
        tk.Spinbox(
            rate,
            from_=1,
            to=5,
            increment=1,
            textvariable=self._settings_vars["max_wheel_dispatch_per_second"],
            width=8,
        ).grid(row=1, column=1, padx=(8, 0), pady=(7, 0), sticky="w")
        presets = ttk.Frame(rate)
        presets.grid(row=2, column=0, columnspan=2, sticky="w", pady=(8, 2))
        ttk.Label(presets, text="普通键预设：").pack(side="left")
        for value in (5, 10, 15, 20):
            ttk.Button(
                presets,
                text=f"{value}/s",
                width=5,
                command=lambda selected=value: self._settings_vars["max_dispatch_per_second"].set(str(selected)),
            ).pack(side="left", padx=(4, 0))
        ttk.Label(
            rate,
            text="连发频率是派发上限；采样 50ms 时可更快识别暂停帧，实际派发仍受上面的连发上限控制。",
            foreground="#666666",
            wraplength=370,
        ).grid(row=3, column=0, columnspan=2, sticky="w", pady=(6, 0))

        ttk.Label(frame, text="WoW 进程名（逗号分隔）").pack(anchor="w", pady=(8, 0))
        ttk.Entry(frame, textvariable=self._settings_vars["wow_process_names"]).pack(fill="x", pady=(2, 8))
        ttk.Label(frame, text="UI 联动等待提示（秒）").pack(anchor="w")
        tk.Spinbox(frame, from_=1, to=600, increment=1, textvariable=self._settings_vars["ui_link_wait_seconds"], width=8).pack(
            anchor="w", pady=(2, 12)
        )
        ttk.Label(frame, text="连接、采样与连发频率设置在停止 TEK 后重新启动时生效。", foreground="#666666", wraplength=390).pack(
            fill="x", pady=(0, 8)
        )
        connection_actions = ttk.Frame(frame)
        connection_actions.pack(fill="x")
        ttk.Label(
            connection_actions,
            text="无需切出 WoW 手动校准；自动定位会在 WoW 成为前台后后台完成。",
            foreground="#666666",
            wraplength=270,
        ).pack(side="left")
        ttk.Button(connection_actions, text="保存连接设置", command=self._save_connection).pack(side="right")

    def _build_diagnostics_tab(self, frame: ttk.Frame) -> None:
        settings = self.settings_store.load()
        self._settings_vars["log_level"] = tk.StringVar(value=settings.log_level)
        self._settings_vars["wow_savedvariables_path"] = tk.StringVar(value=settings.wow_savedvariables_path)
        ttk.Label(frame, text="日志级别").pack(anchor="w")
        ttk.Combobox(frame, textvariable=self._settings_vars["log_level"], values=("DEBUG", "INFO", "WARNING", "ERROR"), state="readonly").pack(
            anchor="w", pady=(2, 8)
        )
        ttk.Label(frame, text="诊断摘要").pack(anchor="w")
        self.values["diagnostic_paths"] = tk.StringVar(value=f"日志：{self.worker.paths.logs}")
        ttk.Label(frame, textvariable=self.values["diagnostic_paths"], foreground="#666666", wraplength=620).pack(fill="x", pady=(2, 0))
        self.values["log_size"] = tk.StringVar(value="日志：计算中")
        self.values["foreground_diagnostics"] = tk.StringVar(value="等待前台窗口诊断")
        self.values["signal_diagnostics"] = tk.StringVar(value="等待色块定位诊断")
        self.values["physical_input_diagnostics"] = tk.StringVar(value="物理输入协作：等待 UI 联动")
        for key in ("log_size", "foreground_diagnostics", "signal_diagnostics", "physical_input_diagnostics"):
            ttk.Label(frame, textvariable=self.values[key], foreground="#666666", wraplength=620, justify="left").pack(fill="x")

        ttk.Label(frame, text="映射快照（可选）").pack(anchor="w", pady=(8, 0))
        source_row = ttk.Frame(frame)
        source_row.pack(fill="x", pady=(2, 8))
        ttk.Entry(source_row, textvariable=self._settings_vars["wow_savedvariables_path"], width=52).pack(side="left", fill="x", expand=True)
        ttk.Button(source_row, text="选择", command=self._choose_savedvariables).pack(side="left", padx=(5, 0))

        ttk.Label(frame, text="最近原因计数").pack(anchor="w")
        self.values["reason_counts"] = tk.StringVar(value="-")
        ttk.Label(frame, textvariable=self.values["reason_counts"], foreground="#666666", wraplength=620).pack(fill="x", pady=(2, 6))
        ttk.Label(frame, text="最近事件（最多 20 条）").pack(anchor="w")
        self._events_text = tk.Text(frame, height=7, width=72, state="disabled", wrap="none", font=("Consolas", 8))
        self._events_text.pack(fill="both", expand=True, pady=(2, 8))
        actions = ttk.Frame(frame)
        actions.pack(fill="x")
        ttk.Button(actions, text="生成诊断包", command=self._create_diagnostic_bundle).grid(row=0, column=0, padx=(0, 5), pady=3, sticky="ew")
        ttk.Button(actions, text="复制诊断摘要", command=self._copy_diagnostic_summary).grid(row=0, column=1, padx=(0, 5), pady=3, sticky="ew")
        ttk.Button(actions, text="打开日志", command=self.open_logs).grid(row=1, column=0, padx=(0, 5), pady=3, sticky="ew")
        ttk.Button(actions, text="清理旧日志", command=self._clean_old_logs).grid(row=1, column=1, padx=(0, 5), pady=3, sticky="ew")
        ttk.Button(actions, text="导出设置", command=self._export_settings).grid(row=2, column=0, padx=(0, 5), pady=3, sticky="ew")
        ttk.Button(actions, text="导入设置", command=self._import_settings).grid(row=2, column=1, padx=(0, 5), pady=3, sticky="ew")
        for col in range(2):
            actions.columnconfigure(col, weight=1)
        ttk.Label(frame, text="诊断包包含设置、状态、近期 trace 和可选映射快照；不会复制完整 SavedVariables 或宏正文。", foreground="#666666", wraplength=620).pack(
            fill="x", pady=(8, 6)
        )
        ttk.Button(frame, text="保存诊断设置", command=self._save_diagnostics).pack(anchor="e")

    def _refresh(self) -> None:
        self._ui_refresh_after_id = None
        if not self.root:
            return
        try:
            if self.root.state() == "withdrawn":
                self._window_visible = False
                return
        except tk.TclError:
            return
        self._window_visible = True
        snapshot = self.worker.snapshot
        action = " / ".join(
            part for part in (snapshot.last_action_id, str(snapshot.last_action_code or ""), snapshot.last_binding) if part
        )
        self.values["process_state"].set(_process_label(snapshot.process_state))
        self.values["mode"].set(snapshot.mode or "-")
        self.values["wow_foreground"].set(_foreground_label(snapshot.wow_foreground))
        self.values["signal_found"].set("已定位" if snapshot.signal_found else "等待信号")
        signal = snapshot.signal_diagnostics or {}
        backend = str(signal.get("sampler_backend") or self.settings_store.load().signal_sampler_backend or "pillow").lower()
        backend_label = {"pillow": "Pillow", "gdi": "GDI 像素读取（实验）", "gdi_blt": "GDI BitBlt 条带（自动优化）"}.get(backend, backend)
        if signal.get("sampler_fallback_locked"):
            backend_label = "Pillow（会话回退）"
        self.values["sampler_backend"].set(backend_label)
        self.values["combat_state"].set("战斗中" if snapshot.last_in_combat is True else ("脱战" if snapshot.last_in_combat is False else "-"))
        self.values["protocol_token"].set(f"v{snapshot.last_protocol_version or '-'} / {snapshot.last_binding_token if snapshot.last_binding_token is not None else '-'}")
        monitor = []
        if snapshot.last_target_casting:
            monitor.append("目标读条")
        if snapshot.last_target_interruptible:
            monitor.append("可打断")
        if snapshot.last_player_health_critical:
            monitor.append("低血预警")
        self.values["monitor_state"].set(" / ".join(monitor) if monitor else "无监控告警")
        physical = snapshot.physical_input_diagnostics or {}
        if physical:
            whitelist = physical.get("intervention_whitelist") or {}
            held = ", ".join(physical.get("held_inputs") or ()) or "-"
            hook = "键盘就绪" if physical.get("hook_healthy") else (physical.get("hook_health_reason") or "未就绪")
            source = whitelist.get("source") or "tek_local_configuration"
            self.values["manual_gate"].set(
                f"{physical.get('phase') or '-'} / Hook {hook} / 按住 {held} / 白名单 {source}"
            )
        else:
            self.values["manual_gate"].set("Dry-run 未启用")
        limiter = snapshot.rate_limiter or {}
        if limiter:
            self.values["dispatch_rate"].set(
                "普通 {max_per_second}/s（当前 {used_global}） / 滚轮 {max_wheel_per_second}/s（当前 {used_wheel}）".format(**limiter)
            )
        else:
            settings = self.settings_store.load()
            self.values["dispatch_rate"].set(
                f"普通 {settings.max_dispatch_per_second}/s / 滚轮 {settings.max_wheel_dispatch_per_second}/s"
            )
        self.values["last_action"].set(action or "-")
        self.values["last_reason"].set(snapshot.last_reason or "-")
        self.values["notice"].set(_notice_text(snapshot.process_state, snapshot.last_reason))
        self._draw_status_dot(status_color(snapshot))
        self._refresh_buttons(snapshot.process_state)
        self._refresh_diagnostic_values(snapshot)
        self._refresh_diagnostics()
        if self._profile_box:
            self._profile_box.configure(state="disabled" if self.worker.is_running() else "readonly")
        self._schedule_ui_refresh(500)

    def _refresh_buttons(self, state: str) -> None:
        hook_stopping = self.worker.hook_shutdown_pending()
        if self._ui_button:
            if hook_stopping:
                self._ui_button.configure(text="等待 Hook 停止", state="disabled")
            elif self.worker.is_running():
                self._ui_button.configure(text="运行中", state="disabled")
            else:
                self._ui_button.configure(text="启动 UI 联动", state="normal")
        if self._pause_button:
            if hook_stopping or not self.worker.is_running():
                self._pause_button.configure(text="暂停", state="disabled")
            elif self.worker.paused:
                self._pause_button.configure(text="恢复", state="normal")
            else:
                self._pause_button.configure(text="暂停", state="normal")
        if self._recover_button:
            if state == "ErrorLocked" and self.worker.is_running():
                self._recover_button.grid()
            else:
                self._recover_button.grid_remove()

    def _draw_status_dot(self, color: str) -> None:
        if not self._status_dot:
            return
        palette = {"gray": "#8b8b8b", "blue": "#1d7df2", "green": "#20b85a", "yellow": "#e2a900", "red": "#d94141"}
        self._status_dot.delete("all")
        self._status_dot.create_oval(2, 2, 16, 16, fill=palette.get(color, "#1d7df2"), outline="white")

    def _toggle_pause(self) -> None:
        if self.worker.paused:
            self.worker.resume()
        else:
            self.worker.pause()

    def _start_ui_linked(self) -> None:
        self.worker.start_ui_linked()

    def _save_general(self) -> None:
        settings = self.settings_store.load()
        try:
            updated = AppSettings.from_dict(
                {
                    **settings.to_dict(),
                    "auto_start_ui_linked": self._settings_vars["auto_start_ui_linked"].get(),
                    "show_window_on_boot": self._settings_vars["show_window_on_boot"].get(),
                    "tray_notifications": self._settings_vars["tray_notifications"].get(),
                    "exit_confirmation": self._settings_vars["exit_confirmation"].get(),
                    "diagnostics_enabled": self._settings_vars["diagnostics_enabled"].get(),
                    "full_trace_debug": self._settings_vars["full_trace_debug"].get(),
                    "manual_priority_mode": self._settings_vars["manual_priority_mode"].get(),
                    "manual_priority_custom_recovery_ms": int(self._settings_vars["manual_priority_custom_recovery_ms"].get()),
                    "manual_priority_custom_freshness_frames": int(self._settings_vars["manual_priority_custom_freshness_frames"].get()),
                    "manual_priority_custom_replay_guard_ms": int(self._settings_vars["manual_priority_custom_replay_guard_ms"].get()),
                }
            )
        except ValueError:
            messagebox.showerror("TEK", "自定义手动接管参数必须是整数。")
            return
        self.settings_store.save(updated)
        if self._settings_hint:
            self._settings_hint.set("已保存。手动接管策略将在下次启动 UI 联动时生效。")

    def _calibrate_signal_layout(self) -> None:
        try:
            layout, diagnostics = self.worker.calibrate_signal_layout()
        except OSError as error:
            messagebox.showerror("TEK", f"色块校准失败：{error}")
            return
        if "fixed_signal_x" in self._settings_vars:
            self._settings_vars["fixed_signal_x"].set(str(layout.x))
            self._settings_vars["fixed_signal_y"].set(str(layout.y))
        display = diagnostics.get("display") or {}
        mode = display.get("window_mode") or "unknown"
        dpi = display.get("dpi") or "-"
        messagebox.showinfo("TEK", f"校准完成：x={layout.x}, y={layout.y}, size={layout.block_size}, gap={layout.block_gap}\n窗口模式：{mode}；DPI：{dpi}")

    def _save_connection(self) -> None:
        if self.worker.is_running() and self._profile_box:
            current = self.settings_store.load().profile_id
            if self._settings_vars["profile_id"].get() != current:
                messagebox.showwarning("TEK", "请先停止 TEK，再切换 Profile。")
                self._settings_vars["profile_id"].set(current)
                return
        settings = self.settings_store.load()
        try:
            updated = AppSettings.from_dict(
                {
                    **settings.to_dict(),
                    "profile_id": self._settings_vars["profile_id"].get(),
                    "auto_locate_signal": self._settings_vars["auto_locate_signal"].get(),
                    "signal_sampler_backend": self._settings_vars["signal_sampler_backend"].get(),
                    "fixed_signal_x": int(self._settings_vars["fixed_signal_x"].get()),
                    "fixed_signal_y": int(self._settings_vars["fixed_signal_y"].get()),
                    "sampling_interval_ms": int(self._settings_vars["sampling_interval_ms"].get()),
                    "max_dispatch_per_second": int(self._settings_vars["max_dispatch_per_second"].get()),
                    "max_wheel_dispatch_per_second": int(self._settings_vars["max_wheel_dispatch_per_second"].get()),
                    "wow_process_names": self._settings_vars["wow_process_names"].get(),
                    "ui_link_wait_seconds": int(self._settings_vars["ui_link_wait_seconds"].get()),
                }
            )
        except ValueError:
            messagebox.showerror("TEK", "连接设置格式无效。")
            return
        self.settings_store.save(updated)
        messagebox.showinfo("TEK", "已保存。连接、Profile、采样与连发频率设置将在停止后重新启动 TEK 时生效。")

    def _choose_savedvariables(self) -> None:
        selected = filedialog.askopenfilename(
            title="选择 WoW 的 TacticEcho.lua",
            filetypes=(("Lua 保存变量", "TacticEcho.lua"), ("Lua 文件", "*.lua"), ("所有文件", "*.*")),
        )
        if selected:
            self._settings_vars["wow_savedvariables_path"].set(selected)

    def _create_diagnostic_bundle(self) -> None:
        # Persist the optional mapping source before packaging so one click is
        # repeatable on later support runs.
        self._save_diagnostics(show_message=False)
        try:
            path, manifest = self.worker.create_diagnostic_bundle()
        except OSError as error:
            messagebox.showerror("TEK", f"生成诊断包失败：{error}")
            return
        mapping_note = "已包含映射快照" if manifest.get("mappingExportIncluded") else "未包含映射快照（可选择 TacticEcho.lua 后重试）"
        messagebox.showinfo("TEK", f"诊断包已生成：\n{path}\n{mapping_note}")

    def _copy_diagnostic_summary(self) -> None:
        """Generate the redacted bundle and copy its human summary to clipboard."""
        self._save_diagnostics(show_message=False)
        try:
            path, _ = self.worker.create_diagnostic_bundle()
            import zipfile
            with zipfile.ZipFile(path) as archive:
                summary = archive.read("SUMMARY.md").decode("utf-8")
            if self.root:
                self.root.clipboard_clear()
                self.root.clipboard_append(summary)
                self.root.update()
            messagebox.showinfo("TEK", "诊断摘要已复制到剪贴板。")
        except (OSError, KeyError, UnicodeError) as error:
            messagebox.showerror("TEK", f"复制诊断摘要失败：{error}")

    def _save_diagnostics(self, *, show_message: bool = True) -> None:
        settings = self.settings_store.load()
        self.settings_store.save(AppSettings.from_dict({
            **settings.to_dict(),
            "log_level": self._settings_vars["log_level"].get(),
            "wow_savedvariables_path": self._settings_vars["wow_savedvariables_path"].get(),
        }))
        if show_message:
            messagebox.showinfo("TEK", "已保存诊断设置。")

    def _refresh_diagnostic_values(self, snapshot) -> None:
        foreground = snapshot.foreground_diagnostics or {}
        if foreground:
            self.values["foreground_diagnostics"].set(
                "前台：{reason}；{title}；{name} PID {pid}".format(
                    title=foreground.get("title") or "-", name=foreground.get("process_name") or "-",
                    pid=foreground.get("process_id") or "-", reason=foreground.get("reason") or "-",
                )
            )
        else:
            self.values["foreground_diagnostics"].set("前台：等待")
        signal = snapshot.signal_diagnostics or {}
        layout = signal.get("layout") or {}
        if signal:
            coords = "-" if not layout else "x={x}, y={y}, size={block_size}, gap={gap}".format(**layout)
            display = signal.get("display") or {}
            window_text = ""
            if display:
                window_text = "；DPI {dpi}/{mode}".format(
                    dpi=display.get("dpi") or "-", mode=display.get("window_mode") or "unknown"
                )
            sampler_backend = signal.get("sampler_backend") or signal.get("configured_sampler_backend") or "pillow"
            if signal.get("sampler_fallback_locked"):
                sampler_backend = "pillow（会话回退）"
            recent_error = signal.get("recent_decode_error") or signal.get("last_decode_error") or "-"
            backoff_ms = signal.get("auto_locate_backoff_remaining_ms", 0)
            verify = "候选验证" if signal.get("layout_verification_required") else "已验证"
            self.values["signal_diagnostics"].set(
                "采样：{source}/{sampler}；{verify}；布局 {coords}；退避 {backoff}ms；最近 {error}{window}".format(
                    source=signal.get("layout_source") or "none", sampler=sampler_backend, coords=coords,
                    verify=verify, backoff=backoff_ms, error=recent_error, window=window_text,
                )
            )
        else:
            self.values["signal_diagnostics"].set("采样：等待")
        physical = snapshot.physical_input_diagnostics or {}
        if physical:
            whitelist = physical.get("intervention_whitelist") or {}
            held_inputs = ", ".join(physical.get("held_inputs") or ()) or "-"
            hook = "键盘就绪" if physical.get("hook_healthy") else (physical.get("hook_health_reason") or physical.get("hook_error") or "未就绪")
            native_error = physical.get("hook_native_error")
            hook_detail = f"（WinError {native_error}）" if native_error else ""
            self.values["physical_input_diagnostics"].set(
                "接管：{phase}；Hook {hook}{hook_detail}；按住 {held}；等待 {remaining}/{recovery}ms；freshness {seen}/{required}；白名单 {valid}".format(
                    phase=physical.get("phase") or ("暂停中" if physical.get("active") else "就绪"),
                    hook=hook,
                    hook_detail=hook_detail,
                    held=held_inputs,
                    remaining=physical.get("remaining_ms", 0),
                    recovery=physical.get("recovery_ms", 0),
                    seen=physical.get("observed_freshness_frames", 0),
                    required=physical.get("required_freshness_frames", 0),
                    valid=whitelist.get("key_count", 0),
                )
            )
        else:
            self.values["physical_input_diagnostics"].set("接管：等待 UI 联动")
        if "binding_telemetry" in self.values:
            self.values["binding_telemetry"].set(
                f"协议=v{snapshot.last_protocol_version or '-'}  token={snapshot.last_binding_token if snapshot.last_binding_token is not None else '-'}  键={snapshot.last_binding or '-'}"
            )
        limiter = snapshot.rate_limiter or {}
        limiter_text = ""
        if limiter:
            limiter_text = " | 限速：{used_global}/{max_per_second}，滚轮 {used_wheel}/{max_wheel_per_second}".format(**limiter)
        failures = snapshot.dispatch_failures or {}
        failure_text = ""
        if failures:
            failure_text = " | 输入失败：{recent_failures}/{threshold}（{window_seconds}s）".format(**failures)
        counts = snapshot.reason_counts or {}
        self.values["reason_counts"].set(("；".join(f"{key}: {value}" for key, value in counts.items()) or "-") + limiter_text + failure_text)

    def _refresh_diagnostics(self) -> None:
        events_widget = getattr(self, "_events_text", None)
        if events_widget is not None:
            events_widget.configure(state="normal")
            events_widget.delete("1.0", "end")
            events_widget.insert("1.0", "\n".join(self.worker.recent_events[-20:]) or "暂无运行事件")
            events_widget.configure(state="disabled")
        variable = self.values.get("log_size")
        if variable is not None:
            total = 0
            try:
                total = sum(path.stat().st_size for path in self.worker.paths.logs.glob("*") if path.is_file())
            except OSError:
                pass
            variable.set(f"日志：{total / 1024:.1f} KB；状态：{self.worker.paths.status_json.name}；诊断包：{self.worker.paths.diagnostics}")

    def _clean_old_logs(self) -> None:
        if not messagebox.askyesno("清理旧日志", "将删除 14 天前的 trace 和轮转日志。是否继续？"):
            return
        from datetime import datetime, timedelta

        cutoff = datetime.now().timestamp() - timedelta(days=14).total_seconds()
        removed = 0
        for path in self.worker.paths.logs.glob("*"):
            if not path.is_file() or path == self.worker.paths.tray_log or path == self.worker.paths.status_json:
                continue
            try:
                if path.stat().st_mtime < cutoff or path.name.endswith(".1"):
                    path.unlink()
                    removed += 1
            except OSError:
                continue
        messagebox.showinfo("TEK", f"已清理 {removed} 个旧日志文件。")

    def _capture_pointer(self) -> None:
        try:
            x, y = self.root.winfo_pointerxy() if self.root else (0, 0)
            self._settings_vars["fixed_signal_x"].set(str(x))
            self._settings_vars["fixed_signal_y"].set(str(y))
        except Exception as error:
            messagebox.showerror("TEK", f"无法读取鼠标位置：{error}")

    def _profile_names(self) -> tuple[str, ...]:
        profiles = sorted(path.stem for path in self.worker.paths.profiles.glob("*.json"))
        return tuple(profiles or ["laptop"])

    def open_logs(self) -> None:
        log_dir = self.worker.snapshot.log_dir or str(self.worker.paths.logs)
        if os.name == "nt":
            os.startfile(log_dir)  # type: ignore[attr-defined]
        else:
            subprocess.Popen(["xdg-open", log_dir])

    def _export_settings(self) -> None:
        destination = filedialog.asksaveasfilename(
            title="导出 TEK 设置",
            defaultextension=".json",
            filetypes=[("JSON 文件", "*.json")],
            initialfile="tek-settings.json",
        )
        if destination:
            self.settings_store.export_to(destination)

    def _import_settings(self) -> None:
        source = filedialog.askopenfilename(title="导入 TEK 设置", filetypes=[("JSON 文件", "*.json")])
        if not source:
            return
        try:
            result = self.settings_store.import_with_result(source)
        except Exception as error:
            messagebox.showerror("TEK", f"导入失败：{error}")
            return
        detail = "\n\n".join(result.warnings)
        message = "设置已导入。连接相关设置将在停止后重新启动时生效。"
        if detail:
            message += "\n\n" + detail
        messagebox.showinfo("TEK", message)
        self._reload_settings_controls()

    def _reload_settings_controls(self) -> None:
        settings = self.settings_store.load()
        for key, value in settings.to_dict().items():
            variable = self._settings_vars.get(key)
            if variable is None:
                continue
            if key == "auto_dispatch_exempt_keys":
                variable.set(", ".join(value))
            else:
                variable.set(value)
        if "auto_dispatch_exempt_keys" in self._settings_vars:
            self._set_intervention_keys(list(settings.auto_dispatch_exempt_keys))

    def _select_tab(self, key: str) -> None:
        if self._notebook and key in self._tabs:
            self._notebook.select(self._tabs[key])

    def _drain_commands(self) -> None:
        if not self.root:
            return
        while True:
            try:
                command, value = self._commands.get_nowait()
            except queue.Empty:
                break
            if command == "show":
                if self.root.state() == "withdrawn":
                    self._restore_saved_window_geometry()
                self.root.deiconify()
                self.root.lift()
                self._window_visible = True
                self._cancel_ui_refresh()
                self._refresh()
                self._select_tab(str(value or "status"))
            elif command == "toggle":
                if self.root.state() == "withdrawn":
                    self._restore_saved_window_geometry()
                    self.root.deiconify()
                    self.root.lift()
                    self._window_visible = True
                    self._cancel_ui_refresh()
                    self._refresh()
                else:
                    self._withdraw_window()
            elif command == "confirm_exit":
                if messagebox.askyesno("退出 TEK", "退出 TEK 将停止当前 worker。是否继续？", parent=self.root):
                    callback = value
                    if callable(callback):
                        threading.Thread(target=callback, daemon=True).start()
            elif command == "shutdown":
                self._persist_window_geometry(force=True)
                self._window_visible = False
                self._cancel_ui_refresh()
                self.root.destroy()
                return
        self.root.after(120, self._drain_commands)


def _foreground_label(value: bool | None) -> str:
    if value is True:
        return "WoW 正常"
    if value is False:
        return "等待 WoW 前台"
    return "未知"


def _process_label(value: str) -> str:
    labels = {
        "Stopped": "已停止",
        "Starting": "正在启动",
        "Waiting": "等待 TEAP 信号",
        "WaitingForForeground": "等待前台",
        "Bootstrap": "正在建立会话",
        "AwaitingStartToggle": "等待游戏内武装",
        "Armed": "运行中",
        "Paused": "已暂停",
        "Blocked": "已阻断",
        "Stale": "信号陈旧",
        "ErrorLocked": "错误锁定",
        "WorkerExited": "Worker 已退出",
        "Stopping": "正在停止",
    }
    return labels.get(value, value)


def _notice_text(process_state: str, reason: str | None) -> str:
    if process_state == "AwaitingStartToggle":
        return "TEK 已连接，等待游戏内 TE 切换为武装状态。"
    if process_state == "Paused":
        return "TEK 已暂停：仍监测信号，但不会派发按键。"
    if process_state == "ErrorLocked":
        return "发生输入异常，已锁定。请检查日志后点击“恢复”或停止。"
    if process_state == "Blocked":
        return f"当前条件阻断：{reason or '-'}"
    if process_state == "WaitingForForeground":
        return "等待前台：WoW 未处于前台。"
    if process_state == "Stopping" and reason == "physical_input_hook_stopping":
        return "正在等待键盘 Hook 完整退出；退出前不会启动新的 UI 联动。"
    if process_state == "Waiting":
        return "等待有效 TEAP 信号。"
    if process_state == "Armed":
        return "TEK 正在处理有效 TE 信号。输入提交不等于游戏内施法成功。"
    return reason or "TEK 已就绪。"
