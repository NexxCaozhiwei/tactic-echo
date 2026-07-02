"""Create privacy-bounded, portable TEK diagnostic archives.

The bundle is intentionally local and read-only: it serializes the persisted
settings/status/trace context plus an optional *sanitized* mapping snapshot
extracted from TacticEcho.lua.  It never writes to WoW files and never includes
macro bodies or the full SavedVariables file.
"""
from __future__ import annotations

import json
import os
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from tek.src.te_savedvariables import read_mapping_export

BUNDLE_SCHEMA_VERSION = 2
MAX_FILE_BYTES = 1_000_000
MAX_TRACE_FILES = 4


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def _tail_bytes(path: Path, *, max_bytes: int = MAX_FILE_BYTES) -> bytes:
    """Return a tail that starts at a complete JSONL line boundary.

    The previous byte-tail implementation could begin in the middle of a JSON
    object, making the first record in a diagnostic bundle unparsable.
    """
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            truncated = size > max_bytes
            if truncated:
                handle.seek(-max_bytes, os.SEEK_END)
            data = handle.read(max_bytes)
        if truncated:
            first_newline = data.find(b"\n")
            if first_newline < 0:
                return b""
            data = data[first_newline + 1 :]
        return data
    except OSError:
        return b""


def _zip_text(archive: zipfile.ZipFile, name: str, value: Any) -> None:
    archive.writestr(name, _safe_json(value).encode("utf-8"))


def _zip_tail(archive: zipfile.ZipFile, path: Path, arcname: str, included: list[str], missing: list[str]) -> None:
    data = _tail_bytes(path)
    if not data:
        missing.append(path.name)
        return
    archive.writestr(arcname, data)
    included.append(arcname)


def _profile_path(paths, settings) -> Path:
    profile_id = str(getattr(settings, "profile_id", "laptop") or "laptop").strip() or "laptop"
    return Path(paths.profiles) / f"{profile_id}.json"


def _recent_trace_paths(logs: Path) -> Iterable[Path]:
    try:
        items = sorted(logs.glob("tek-trace-*.jsonl"), key=lambda value: value.stat().st_mtime, reverse=True)
    except OSError:
        return ()
    return items[:MAX_TRACE_FILES]



def _summary_markdown(snapshot: dict[str, Any], mapping: dict[str, Any] | None, manifest: dict[str, Any]) -> str:
    """Human-readable, privacy-bounded support conclusion.

    This intentionally derives only from already-sanitized runtime and mapping
    data; it does not include macro bodies, character names or absolute paths.
    """
    state = snapshot.get("process_state") or snapshot.get("status") or "unknown"
    reason = snapshot.get("last_reason") or "unknown"
    binding = snapshot.get("last_binding") or "unknown"
    action = snapshot.get("last_action_id") or snapshot.get("last_action_code") or "unknown"
    foreground = snapshot.get("wow_foreground")
    findings = []
    if foreground is False:
        findings.append("WoW 未处于前台：TEK 按安全门禁不会发送输入。")
    if "physical_input" in str(reason):
        findings.append("检测到玩家真实键鼠输入：TEK 正在让权，未发送输入。")
    if "binding" in str(reason) or binding in {None, "", "unknown"}:
        findings.append("推荐缺少可执行现实键位或 Token：请检查默认动作条映射与白名单。")
    if not findings:
        findings.append("未发现可自动归因的硬阻断；请附带 trace 与验收清单复核。")
    mapping_note = "已包含脱敏映射快照。" if mapping else "未包含映射快照（未配置或未找到 SavedVariables）。"
    auto_burst_note = None
    if mapping and isinstance(mapping.get("autoBurst"), dict):
        auto = mapping["autoBurst"]
        rule = auto.get("resolvedRule") if isinstance(auto.get("resolvedRule"), dict) else {}
        decision = auto.get("lastDecision") if isinstance(auto.get("lastDecision"), dict) else {}
        auto_burst_note = (
            "自动爆发：启用=" + str(auto.get("enabled") is True)
            + "；规则=" + str(rule.get("windowSpellID") or "-") + "→" + str(rule.get("injectionSpellID") or "-")
            + "；最近=" + str(decision.get("reason") or auto.get("ruleReason") or "无")
        )
    return "\n".join([
        "# Tactic Echo 诊断摘要",
        "",
        f"- 运行状态：`{state}`",
        f"- 最近动作：`{action}`",
        f"- 最近键位：`{binding}`",
        f"- 最近原因：`{reason}`",
        f"- WoW 前台：`{foreground}`",
        f"- 映射：{mapping_note}",
        *( [f"- {auto_burst_note}"] if auto_burst_note else [] ),
        "",
        "## 自动结论",
        *[f"- {item}" for item in findings],
        "",
        "## 实机验收",
        "- [ ] Notepad：单键、组合键、滚轮均只向前台测试窗口发送。",
        "- [ ] WoW 非前台：TEK 不发送输入。",
        "- [ ] 切换窗口/真实键鼠输入：TEK 立即让权，推荐仍刷新。",
        "- [ ] WoW 前台：仅在明确启用 UI 联动后测试。",
        "",
        "本文件不包含宏正文、角色名、完整 SavedVariables 或绝对本地路径。",
        "",
    ])

def create_diagnostic_bundle(
    *,
    paths,
    settings_store,
    status_snapshot=None,
    saved_variables_path: str | Path | None = None,
    destination: str | Path | None = None,
    recent_trace_records: list[dict] | tuple[dict, ...] | None = None,
) -> tuple[Path, dict]:
    """Create a local ZIP and return ``(path, manifest)``.

    The caller can omit ``saved_variables_path``.  In that case the archive is
    still complete for TEK diagnostics, but reports that an addon mapping
    snapshot was not selected.  A supplied path is parsed to a constrained
    mapping export; raw SavedVariables are never copied into the archive.
    """
    paths.ensure()
    settings = settings_store.load()
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    target = Path(destination) if destination else Path(paths.diagnostics) / f"tek-diagnostic-{timestamp}.zip"
    target.parent.mkdir(parents=True, exist_ok=True)

    snapshot_payload: dict[str, Any]
    if status_snapshot is not None:
        snapshot_payload = status_snapshot.to_dict() if hasattr(status_snapshot, "to_dict") else dict(status_snapshot)
    else:
        try:
            snapshot_payload = json.loads(Path(paths.status_json).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, TypeError):
            snapshot_payload = {"status": "unavailable"}

    included: list[str] = []
    missing: list[str] = []
    mapping_result: dict[str, Any] | None = None
    mapping_error: str | None = None
    if saved_variables_path:
        try:
            mapping_result = read_mapping_export(saved_variables_path)
            if mapping_result is None:
                mapping_error = "mapping_export_not_found"
        except (OSError, UnicodeError, ValueError) as error:
            mapping_error = f"mapping_export_read_failed:{type(error).__name__}"
    else:
        mapping_error = "mapping_export_path_not_configured"

    manifest = {
        "schemaVersion": BUNDLE_SCHEMA_VERSION,
        "component": "TEK",
        "eventType": "diagnostic_bundle",
        "createdAt": utc_now_iso(),
        "redacted": True,
        "mappingExportIncluded": mapping_result is not None,
        "mappingExportError": mapping_error,
        "included": included,
        "missing": missing,
    }

    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        _zip_text(archive, "settings.json", settings.to_dict())
        included.append("settings.json")
        _zip_text(archive, "status.json", snapshot_payload)
        included.append("status.json")

        profile = _profile_path(paths, settings)
        if profile.exists():
            _zip_tail(archive, profile, f"profiles/{profile.name}", included, missing)
        else:
            missing.append(profile.name)

        tray_log = Path(paths.tray_log)
        _zip_tail(archive, tray_log, f"logs/{tray_log.name}", included, missing)
        for trace_path in _recent_trace_paths(Path(paths.logs)):
            _zip_tail(archive, trace_path, f"traces/{trace_path.name}", included, missing)

        # The worker keeps a bounded in-memory ring of meaningful records. It
        # survives a transient trace-file lock and gives support bundles recent
        # context without restoring high-frequency disk logging.
        if recent_trace_records:
            rows = "".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n" for row in recent_trace_records)
            archive.writestr("traces/in-memory-recent.jsonl", rows.encode("utf-8"))
            included.append("traces/in-memory-recent.jsonl")

        if mapping_result is not None:
            _zip_text(archive, "te-mapping-export.json", mapping_result)
            included.append("te-mapping-export.json")

        summary = _summary_markdown(snapshot_payload, mapping_result, manifest)
        archive.writestr("SUMMARY.md", summary.encode("utf-8"))
        included.append("SUMMARY.md")

        # Manifest is written last so its member inventory describes the final
        # archive.  It intentionally exposes only relative archive names.
        _zip_text(archive, "manifest.json", manifest)

    return target, manifest
