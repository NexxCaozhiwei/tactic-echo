"""Offline parser for SimulationCraft Action Priority Lists.

This tool intentionally produces review data only.  It does not modify the
Tactic Echo AddOn, create spell bindings, or participate in TEAP / TEK input.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence
import json
import re
import subprocess


SCHEMA_VERSION = 1
TOOL_VERSION = "1.0.0"
DEFAULT_REF = "midnight"

# Actions that are SimC control syntax or non-player combat actions.  They do
# not describe a candidate Window or Inject action for TE review data.
IGNORED_ACTIONS = frozenset(
    {
        "auto_attack",
        "call_action_list",
        "run_action_list",
        "call_variable",
        "variable",
        "snapshot_stats",
        "wait",
        "wait_until_ready",
        "pool_resource",
        "cancel_buff",
        "start_moving",
        "stop_moving",
        "use_items",  # Generic SimC container; concrete items are unknown.
        "use_item",   # Processed separately as an item inject, never Window.
        "potion",     # Processed separately as a consumable inject.
        "invoke_external_buff",  # Context only; the player cannot cast it.
    }
)

INJECT_ACTION_TYPES = frozenset({"potion", "use_item", "invoke_external_buff"})
ACTION_LIST_CALLS = frozenset({"call_action_list", "run_action_list"})

# Safe, explicit racial action names commonly emitted in SimC cooldown lists.
# They remain candidates and are never auto-applied to the AddOn.
RACIAL_ACTIONS = frozenset(
    {
        "ancestral_call",
        "arcane_torrent",
        "berserking",
        "blood_fury",
        "fireblood",
        "lights_judgment",
        "rocket_barrage",
    }
)

# Class/spec identifiers are only presentation metadata.  Unknown future specs
# remain parseable and are emitted with their source filename as the key.
SPEC_METADATA: dict[str, tuple[str, str, str | None]] = {
    "deathknight_blood": ("死亡骑士", "鲜血", "DEATHKNIGHT_1"),
    "deathknight_frost": ("死亡骑士", "冰霜", "DEATHKNIGHT_2"),
    "deathknight_unholy": ("死亡骑士", "邪恶", "DEATHKNIGHT_3"),
    "demonhunter_havoc": ("恶魔猎手", "浩劫", "DEMONHUNTER_1"),
    "demonhunter_vengeance": ("恶魔猎手", "复仇", "DEMONHUNTER_2"),
    "druid_balance": ("德鲁伊", "平衡", "DRUID_1"),
    "druid_feral": ("德鲁伊", "野性", "DRUID_2"),
    "druid_guardian": ("德鲁伊", "守护", "DRUID_3"),
    "druid_restoration": ("德鲁伊", "恢复", "DRUID_4"),
    "evoker_devastation": ("唤魔师", "湮灭", "EVOKER_1"),
    "evoker_preservation": ("唤魔师", "恩护", "EVOKER_2"),
    "evoker_augmentation": ("唤魔师", "增辉", "EVOKER_3"),
    "hunter_beast_mastery": ("猎人", "兽王", "HUNTER_1"),
    "hunter_marksmanship": ("猎人", "射击", "HUNTER_2"),
    "hunter_survival": ("猎人", "生存", "HUNTER_3"),
    "mage_arcane": ("法师", "奥术", "MAGE_1"),
    "mage_fire": ("法师", "火焰", "MAGE_2"),
    "mage_frost": ("法师", "冰霜", "MAGE_3"),
    "monk_brewmaster": ("武僧", "酒仙", "MONK_1"),
    "monk_mistweaver": ("武僧", "织雾", "MONK_2"),
    "monk_windwalker": ("武僧", "踏风", "MONK_3"),
    "paladin_holy": ("圣骑士", "神圣", "PALADIN_1"),
    "paladin_protection": ("圣骑士", "防护", "PALADIN_2"),
    "paladin_retribution": ("圣骑士", "惩戒", "PALADIN_3"),
    "priest_discipline": ("牧师", "戒律", "PRIEST_1"),
    "priest_holy": ("牧师", "神圣", "PRIEST_2"),
    "priest_shadow": ("牧师", "暗影", "PRIEST_3"),
    "rogue_assassination": ("潜行者", "奇袭", "ROGUE_1"),
    "rogue_outlaw": ("潜行者", "狂徒", "ROGUE_2"),
    "rogue_subtlety": ("潜行者", "敏锐", "ROGUE_3"),
    "shaman_elemental": ("萨满祭司", "元素", "SHAMAN_1"),
    "shaman_enhancement": ("萨满祭司", "增强", "SHAMAN_2"),
    "shaman_restoration": ("萨满祭司", "恢复", "SHAMAN_3"),
    "warlock_affliction": ("术士", "痛苦", "WARLOCK_1"),
    "warlock_demonology": ("术士", "恶魔学识", "WARLOCK_2"),
    "warlock_destruction": ("术士", "毁灭", "WARLOCK_3"),
    "warrior_arms": ("战士", "武器", "WARRIOR_1"),
    "warrior_fury": ("战士", "狂怒", "WARRIOR_2"),
    "warrior_protection": ("战士", "防护", "WARRIOR_3"),
}

_ACTION_ASSIGNMENT = re.compile(
    r"^actions(?:\.(?P<list_name>[A-Za-z0-9_]+))?(?P<operator>\+?=)(?P<body>.+)$"
)
_REFERENCE_RE = re.compile(r"(?:buff|debuff|cooldown|dot)\.([a-z0-9_]+)", re.IGNORECASE)


class SimcParserError(RuntimeError):
    """Raised when the supplied SimulationCraft tree cannot be parsed safely."""


@dataclass(frozen=True)
class ActionEntry:
    list_name: str
    action: str
    params: dict[str, str]
    condition: str | None
    line_number: int
    raw: str


@dataclass
class SimcProfile:
    path: Path
    lists: dict[str, list[ActionEntry]] = field(default_factory=dict)
    source_sha256: str = ""


@dataclass(frozen=True)
class Candidate:
    candidate_key: str
    action: str
    kind: str
    inject_type: str | None
    rank: int
    source_list: str
    source_line: int
    condition: str | None
    condition_references: tuple[str, ...]
    source_reason: str
    review_required: bool = True


@dataclass
class SpecReport:
    spec_key: str
    class_label: str
    spec_label: str
    te_profile_key: str | None
    source_files: dict[str, str]
    windows: list[Candidate]
    injects: list[Candidate]
    pair_hints: list[dict[str, Any]]
    notes: list[str]
    override_pairs: list[dict[str, Any]]


def _slug_display(slug: str) -> str:
    return slug.replace("_", " ").strip().title()


def _strip_comment(line: str) -> str:
    # SimC comments use #.  APL expressions do not use quoted strings in the
    # generated ActionPriorityLists, so a simple first-# split is deliberate.
    return line.split("#", 1)[0].strip()


def _logical_lines(text: str) -> Iterable[tuple[int, str]]:
    """Yield physical start line + a joined SimC logical line.

    Generated APLs are normally one action per line.  Backslash continuation is
    supported for hand-edited local copies so the parser remains useful beyond
    the generated source tree.
    """

    pending: list[str] = []
    start_line: int | None = None
    for number, physical in enumerate(text.splitlines(), start=1):
        cleaned = _strip_comment(physical)
        if not cleaned:
            continue
        if start_line is None:
            start_line = number
        if cleaned.endswith("\\"):
            pending.append(cleaned[:-1].rstrip())
            continue
        pending.append(cleaned)
        yield start_line, "".join(pending)
        pending = []
        start_line = None
    if pending:
        raise SimcParserError(f"Unterminated line continuation at line {start_line}.")


def _split_top_level_csv(body: str) -> list[str]:
    fields: list[str] = []
    current: list[str] = []
    depth = 0
    for char in body:
        if char == "(":
            depth += 1
        elif char == ")" and depth > 0:
            depth -= 1
        if char == "," and depth == 0:
            fields.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    fields.append("".join(current).strip())
    return [field for field in fields if field]


def _parse_action_body(body: str) -> tuple[str, dict[str, str], str | None]:
    fields = _split_top_level_csv(body)
    if not fields:
        raise SimcParserError("Action assignment has an empty action body.")
    action = fields[0].lstrip("/").strip().lower()
    if not action:
        raise SimcParserError("Action assignment has an empty action name.")
    params: dict[str, str] = {}
    condition: str | None = None
    for field in fields[1:]:
        if "=" not in field:
            params[field.lower()] = "true"
            continue
        key, value = field.split("=", 1)
        normalized_key = key.strip().lower()
        normalized_value = value.strip()
        params[normalized_key] = normalized_value
        if normalized_key == "if":
            condition = normalized_value
    return action, params, condition


def parse_simc_file(path: Path) -> SimcProfile:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise SimcParserError(f"Cannot read '{path}': {exc}") from exc
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise SimcParserError(f"'{path}' is not UTF-8 text: {exc}") from exc

    profile = SimcProfile(path=path, source_sha256=sha256(raw).hexdigest())
    for line_number, line in _logical_lines(text):
        match = _ACTION_ASSIGNMENT.match(line)
        if not match:
            continue
        list_name = (match.group("list_name") or "main").lower()
        action, params, condition = _parse_action_body(match.group("body"))
        profile.lists.setdefault(list_name, []).append(
            ActionEntry(
                list_name=list_name,
                action=action,
                params=params,
                condition=condition,
                line_number=line_number,
                raw=line,
            )
        )
    return profile


def _flatten_action_list(
    profile: SimcProfile,
    roots: Sequence[str],
    *,
    include_calls: bool = False,
) -> list[ActionEntry]:
    """Flatten reachable lists in priority order without recursing forever."""

    ordered: list[ActionEntry] = []
    active_stack: set[str] = set()

    def walk(list_name: str) -> None:
        normalized = list_name.lower()
        if normalized in active_stack:
            return
        entries = profile.lists.get(normalized)
        if not entries:
            return
        active_stack.add(normalized)
        for entry in entries:
            if entry.action in ACTION_LIST_CALLS:
                target = entry.params.get("name", "").lower()
                if include_calls:
                    ordered.append(entry)
                if target:
                    walk(target)
                continue
            ordered.append(entry)
        active_stack.remove(normalized)

    for root in roots:
        walk(root)
    return ordered


def _condition_references(condition: str | None) -> tuple[str, ...]:
    if not condition:
        return ()
    return tuple(dict.fromkeys(match.lower() for match in _REFERENCE_RE.findall(condition)))


def _is_real_action(action: str) -> bool:
    return bool(action) and action not in IGNORED_ACTIONS and action not in ACTION_LIST_CALLS


def _detect_inject_type(entry: ActionEntry) -> str:
    if entry.action == "potion":
        return "potion"
    if entry.action == "use_item":
        slot = entry.params.get("slot", "").lower()
        if slot in {"trinket1", "trinket2"}:
            return slot
        if entry.params.get("name"):
            return "named_item"
        return "item"
    if entry.action == "invoke_external_buff":
        return "external_buff"
    if entry.action in RACIAL_ACTIONS:
        return "racial"
    return "spell"


def _inject_candidate_key(entry: ActionEntry, inject_type: str) -> str:
    if inject_type in {"trinket1", "trinket2"}:
        return inject_type
    if inject_type == "named_item":
        item_name = entry.params.get("name", "").strip().lower()
        return f"item:{item_name}" if item_name else "item"
    if inject_type == "item":
        return "item"
    return entry.action


def _candidate(
    entry: ActionEntry,
    *,
    kind: str,
    rank: int,
    source_reason: str,
    inject_type: str | None = None,
    candidate_key: str | None = None,
) -> Candidate:
    return Candidate(
        candidate_key=candidate_key or entry.action,
        action=entry.action,
        kind=kind,
        inject_type=inject_type,
        rank=rank,
        source_list=entry.list_name,
        source_line=entry.line_number,
        condition=entry.condition,
        condition_references=_condition_references(entry.condition),
        source_reason=source_reason,
    )


def _cooldown_roots(profile: SimcProfile) -> list[str]:
    roots = [
        list_name
        for list_name in profile.lists
        if "cooldown" in list_name or list_name in {"burst", "bursts", "cds"}
    ]
    return sorted(set(roots))


def _collect_inject_candidates(profile: SimcProfile) -> tuple[list[Candidate], list[str]]:
    entries = _flatten_action_list(profile, _cooldown_roots(profile))
    candidates: list[Candidate] = []
    seen: set[tuple[str, str]] = set()
    notes: list[str] = []

    for entry in entries:
        if entry.action == "use_items":
            notes.append("检测到通用 use_items 容器；具体饰品须在角色配置阶段确认。")
            continue
        if not _is_real_action(entry.action) and entry.action not in INJECT_ACTION_TYPES:
            continue
        inject_type = _detect_inject_type(entry)
        if inject_type == "external_buff":
            notes.append("检测到外部增益同步条件；该条不属于玩家可主动释放的注入技能。")
            continue
        candidate_key = _inject_candidate_key(entry, inject_type)
        identity = (candidate_key, inject_type)
        if identity in seen:
            continue
        seen.add(identity)
        candidates.append(
            _candidate(
                entry,
                kind="inject",
                inject_type=inject_type,
                candidate_key=candidate_key,
                rank=len(candidates) + 1,
                source_reason="来自 SimulationCraft 默认 APL 的 cooldown/burst 列表",
            )
        )

    return candidates, list(dict.fromkeys(notes))


def _window_roots(profile: SimcProfile) -> tuple[list[str], str]:
    if "assisted_combat" in profile.lists:
        return ["assisted_combat"], "来自 SimulationCraft assisted_combat 列表"
    if "main" in profile.lists:
        return ["main"], "assisted_combat 缺失，回退至 SimC main 列表"
    if profile.lists:
        first = next(iter(profile.lists))
        return [first], f"assisted_combat/main 缺失，回退至 '{first}' 列表"
    return [], "未发现任何动作列表"


def _collect_window_candidates(
    profile: SimcProfile,
    inject_actions: set[str],
) -> tuple[list[Candidate], list[str]]:
    roots, reason = _window_roots(profile)
    if not roots:
        return [], [reason]
    entries = _flatten_action_list(profile, roots)
    candidates: list[Candidate] = []
    seen: set[str] = set()
    notes: list[str] = []

    if "回退" in reason:
        notes.append(reason)

    for entry in entries:
        if not _is_real_action(entry.action):
            continue
        if entry.action in inject_actions:
            continue
        if entry.action in seen:
            continue
        seen.add(entry.action)
        candidates.append(
            _candidate(
                entry,
                kind="window",
                rank=len(candidates) + 1,
                source_reason=reason,
            )
        )
    return candidates, notes


def _source_git_revision(simc_root: Path) -> str | None:
    if not (simc_root / ".git").exists():
        return None
    try:
        result = subprocess.run(
            ["git", "-C", str(simc_root), "rev-parse", "HEAD"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() if result.returncode == 0 and result.stdout.strip() else None


def resolve_apl_root(simc_root: Path) -> Path:
    """Accept a SimC root, ActionPriorityLists, or a source subdirectory."""

    candidate = simc_root.expanduser().resolve()
    if (candidate / "ActionPriorityLists").is_dir():
        return candidate / "ActionPriorityLists"
    if candidate.name == "ActionPriorityLists" and candidate.is_dir():
        return candidate
    if candidate.name in {"default", "assisted_combat"} and candidate.is_dir():
        return candidate.parent
    raise SimcParserError(
        "未找到 ActionPriorityLists 目录。请传入 SimulationCraft 仓库根目录，"
        "或直接传入其 ActionPriorityLists 目录。"
    )


def _load_json_file(path: Path) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SimcParserError(f"无法读取 overrides 文件 '{path}': {exc}") from exc
    if not isinstance(raw, dict):
        raise SimcParserError("overrides 根节点必须是 JSON object。")
    if raw.get("schema_version", SCHEMA_VERSION) != SCHEMA_VERSION:
        raise SimcParserError(
            f"overrides schema_version 必须为 {SCHEMA_VERSION}。"
        )
    if "spec_overrides" in raw and not isinstance(raw["spec_overrides"], dict):
        raise SimcParserError("overrides.spec_overrides 必须是 JSON object。")
    return raw


def _as_slug_list(value: Any, *, path: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
        raise SimcParserError(f"{path} 必须是非空字符串组成的 array。")
    return [item.strip().lower() for item in value]


def _apply_overrides(
    spec_key: str,
    windows: list[Candidate],
    injects: list[Candidate],
    raw_overrides: Mapping[str, Any],
) -> tuple[list[Candidate], list[Candidate], list[dict[str, Any]], list[str]]:
    spec_overrides = raw_overrides.get("spec_overrides", {}) if raw_overrides else {}
    override = spec_overrides.get(spec_key, {})
    if not override:
        return windows, injects, [], []
    if not isinstance(override, dict):
        raise SimcParserError(f"spec_overrides.{spec_key} 必须是 JSON object。")

    notes: list[str] = []

    def merge(
        base: list[Candidate],
        group_name: str,
        default_inject_type: str | None,
    ) -> list[Candidate]:
        group = override.get(group_name, {})
        if not isinstance(group, dict):
            raise SimcParserError(f"spec_overrides.{spec_key}.{group_name} 必须是 object。")
        include = _as_slug_list(group.get("include", []), path=f"{spec_key}.{group_name}.include")
        exclude = set(_as_slug_list(group.get("exclude", []), path=f"{spec_key}.{group_name}.exclude"))
        result = [candidate for candidate in base if candidate.candidate_key not in exclude]
        existing = {candidate.candidate_key for candidate in result}
        for action in include:
            if action in exclude or action in existing:
                continue
            result.append(
                Candidate(
                    candidate_key=action,
                    action=action,
                    kind=group_name.rstrip("s"),
                    inject_type=default_inject_type,
                    rank=len(result) + 1,
                    source_list="user_override",
                    source_line=0,
                    condition=None,
                    condition_references=(),
                    source_reason="用户 overrides 显式加入",
                    review_required=False,
                )
            )
            existing.add(action)
        return [
            Candidate(
                candidate_key=item.candidate_key,
                action=item.action,
                kind=item.kind,
                inject_type=item.inject_type,
                rank=index,
                source_list=item.source_list,
                source_line=item.source_line,
                condition=item.condition,
                condition_references=item.condition_references,
                source_reason=item.source_reason,
                review_required=item.review_required,
            )
            for index, item in enumerate(result, start=1)
        ]

    windows = merge(windows, "window", None)
    injects = merge(injects, "inject", "spell")

    pairs = override.get("pairs", [])
    if not isinstance(pairs, list):
        raise SimcParserError(f"spec_overrides.{spec_key}.pairs 必须是 array。")
    validated_pairs: list[dict[str, Any]] = []
    known_windows = {candidate.candidate_key for candidate in windows}
    known_injects = {candidate.candidate_key for candidate in injects}
    for index, pair in enumerate(pairs, start=1):
        if not isinstance(pair, dict):
            raise SimcParserError(f"{spec_key}.pairs[{index}] 必须是 object。")
        window = str(pair.get("window", "")).strip().lower()
        inject_list = _as_slug_list(pair.get("injects", []), path=f"{spec_key}.pairs[{index}].injects")
        readiness_mode = str(pair.get("readiness_mode", "any_ready")).strip()
        order = str(pair.get("order", "pre")).strip()
        min_ready = pair.get("min_ready_injects", 1)
        if not window or window not in known_windows:
            raise SimcParserError(f"{spec_key}.pairs[{index}].window 必须存在于窗口技能列表。")
        unknown_injects = [action for action in inject_list if action not in known_injects]
        if unknown_injects:
            raise SimcParserError(
                f"{spec_key}.pairs[{index}].injects 包含未定义注入技能: {', '.join(unknown_injects)}"
            )
        if readiness_mode not in {"all_ready", "any_ready", "min_ready"}:
            raise SimcParserError("readiness_mode 仅允许 all_ready / any_ready / min_ready。")
        if order not in {"pre", "post"}:
            raise SimcParserError("order 仅允许 pre / post。")
        if not isinstance(min_ready, int) or min_ready < 1:
            raise SimcParserError("min_ready_injects 必须是大于等于 1 的整数。")
        validated_pairs.append(
            {
                "window": window,
                "injects": inject_list,
                "readiness_mode": readiness_mode,
                "min_ready_injects": min_ready,
                "order": order,
                "source": "user_override",
            }
        )

    if override.get("notes"):
        if not isinstance(override["notes"], str):
            raise SimcParserError(f"spec_overrides.{spec_key}.notes 必须是 string。")
        notes.append(override["notes"].strip())

    return windows, injects, validated_pairs, notes


def _build_pair_hints(windows: list[Candidate], injects: list[Candidate]) -> list[dict[str, Any]]:
    inject_by_action = {candidate.action: candidate.candidate_key for candidate in injects}
    hints: list[dict[str, Any]] = []
    for inject in injects:
        references = set(inject.condition_references)
        linked_windows = [
            candidate.candidate_key for candidate in windows if candidate.action in references
        ]
        linked_injects = sorted(
            candidate_key
            for action, candidate_key in inject_by_action.items()
            if action != inject.action and action in references
        )
        if not linked_windows and not linked_injects:
            continue
        hints.append(
            {
                "inject": inject.candidate_key,
                "linked_windows": linked_windows,
                "linked_injects": linked_injects,
                "condition": inject.condition,
                "interpretation": "仅为 APL 条件共现提示；注入前后顺序必须人工确认。",
            }
        )
    return hints


def _metadata_for_spec(spec_key: str) -> tuple[str, str, str | None]:
    if spec_key in SPEC_METADATA:
        return SPEC_METADATA[spec_key]
    pieces = spec_key.split("_", 1)
    class_label = _slug_display(pieces[0]) if pieces else spec_key
    spec_label = _slug_display(pieces[1]) if len(pieces) > 1 else "未知专精"
    return class_label, spec_label, None


def _profile_paths(apl_root: Path) -> dict[str, dict[str, Path]]:
    result: dict[str, dict[str, Path]] = {}
    for source in ("assisted_combat", "default"):
        directory = apl_root / source
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.simc")):
            result.setdefault(path.stem.lower(), {})[source] = path
    return result


def build_reports(
    simc_root: Path,
    *,
    selected_specs: Sequence[str] | None = None,
    overrides_path: Path | None = None,
) -> tuple[list[SpecReport], dict[str, Any]]:
    apl_root = resolve_apl_root(simc_root)
    source_root = apl_root.parent if apl_root.name == "ActionPriorityLists" else apl_root
    source_paths = _profile_paths(apl_root)
    if not source_paths:
        raise SimcParserError("ActionPriorityLists 下未找到任何 .simc 文件。")

    selected = {item.strip().lower() for item in selected_specs or [] if item.strip()}
    unknown = sorted(selected - set(source_paths))
    if unknown:
        raise SimcParserError(f"未找到指定专精文件: {', '.join(unknown)}")

    raw_overrides = _load_json_file(overrides_path) if overrides_path else {}
    reports: list[SpecReport] = []
    source_manifest: dict[str, Any] = {
        "simc_root": str(source_root),
        "apl_root": str(apl_root),
        "git_revision": _source_git_revision(source_root),
        "generated_at_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "files": {},
    }

    for spec_key in sorted(source_paths):
        if selected and spec_key not in selected:
            continue
        paths = source_paths[spec_key]
        default_profile = parse_simc_file(paths["default"]) if "default" in paths else None
        assisted_profile = parse_simc_file(paths["assisted_combat"]) if "assisted_combat" in paths else None

        injects, inject_notes = _collect_inject_candidates(default_profile) if default_profile else ([], [])
        inject_actions = {candidate.action for candidate in injects if candidate.inject_type == "spell"}
        windows, window_notes = (
            _collect_window_candidates(assisted_profile, inject_actions)
            if assisted_profile
            else ([], ["缺少 assisted_combat APL；未自动生成窗口技能候选。"])
        )
        windows, injects, override_pairs, override_notes = _apply_overrides(
            spec_key,
            windows,
            injects,
            raw_overrides,
        )
        class_label, spec_label, te_profile_key = _metadata_for_spec(spec_key)
        source_files: dict[str, str] = {}
        for source, path in paths.items():
            profile = default_profile if source == "default" else assisted_profile
            assert profile is not None
            source_files[source] = str(path.relative_to(apl_root))
            source_manifest["files"][str(path.relative_to(apl_root))] = {
                "sha256": profile.source_sha256,
                "source": source,
            }

        notes = list(dict.fromkeys(inject_notes + window_notes + override_notes))
        reports.append(
            SpecReport(
                spec_key=spec_key,
                class_label=class_label,
                spec_label=spec_label,
                te_profile_key=te_profile_key,
                source_files=source_files,
                windows=windows,
                injects=injects,
                pair_hints=_build_pair_hints(windows, injects),
                notes=notes,
                override_pairs=override_pairs,
            )
        )

    return reports, source_manifest


def _candidate_to_json(candidate: Candidate) -> dict[str, Any]:
    value = asdict(candidate)
    value["condition_references"] = list(candidate.condition_references)
    value["display_name"] = _slug_display(candidate.action)
    return value


def report_to_json(reports: Sequence[SpecReport], manifest: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "tool_version": TOOL_VERSION,
        "purpose": "review_only_window_inject_candidates",
        "safety": "此数据仅供审核，不会修改 AddOn、BindingToken、TEAP 或 TEK 输入链路。",
        "source": dict(manifest),
        "specs": [
            {
                "spec_key": report.spec_key,
                "class": report.class_label,
                "spec": report.spec_label,
                "te_profile_key": report.te_profile_key,
                "source_files": report.source_files,
                "window_candidates": [_candidate_to_json(candidate) for candidate in report.windows],
                "inject_candidates": [_candidate_to_json(candidate) for candidate in report.injects],
                "pair_hints": report.pair_hints,
                "user_pairs": report.override_pairs,
                "notes": report.notes,
            }
            for report in reports
        ],
    }


def _pipe_safe(value: str) -> str:
    return value.replace("|", "/").replace("\n", " ").strip()


def render_review_txt(reports: Sequence[SpecReport], manifest: Mapping[str, Any]) -> str:
    lines = [
        "TACTIC ECHO - SimC Window / Inject 审核清单",
        f"工具版本: {TOOL_VERSION}",
        f"生成时间(UTC): {manifest.get('generated_at_utc', '')}",
        f"SimC 来源: {manifest.get('simc_root', '')}",
        "说明: Window=assisted_combat 官方辅助战斗序列候选；Inject=default APL cooldown/burst 列表候选。",
        "说明: 本文件仅用于人工审核，未映射 SpellID 前不得导入 AddOn 运行时资料库。",
        "",
        "序号 | 职业 | 专精 | TE专精键 | 窗口技能候选 | 注入技能候选 | 条件配对提示 | 审核备注",
        "-" * 180,
    ]
    for index, report in enumerate(reports, start=1):
        windows = ", ".join(candidate.action for candidate in report.windows) or "(无)"
        injects = ", ".join(
            f"{candidate.candidate_key}[{candidate.inject_type}]" for candidate in report.injects
        ) or "(无)"
        hints = "; ".join(
            f"{hint['inject']} -> window:{','.join(hint['linked_windows']) or '-'} / inject:{','.join(hint['linked_injects']) or '-'}"
            for hint in report.pair_hints
        ) or "(无)"
        notes = "; ".join(report.notes + (["已读取用户 pairs"] if report.override_pairs else [])) or "需审核"
        lines.append(
            " | ".join(
                _pipe_safe(value)
                for value in (
                    str(index),
                    report.class_label,
                    report.spec_label,
                    report.te_profile_key or "未映射",
                    windows,
                    injects,
                    hints,
                    notes,
                )
            )
        )
    lines.append("")
    return "\n".join(lines)


def build_override_template(reports: Sequence[SpecReport]) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "description": "复制后填写 include/exclude/pairs；window/include/exclude 使用候选 candidate_key（窗口候选通常等于 action），pairs.injects 必须使用注入候选 candidate_key，例如 trinket1/trinket2/potion。",
        "spec_overrides": {
            report.spec_key: {
                "window": {"include": [], "exclude": []},
                "inject": {"include": [], "exclude": []},
                "pairs": [],
                "notes": "",
            }
            for report in reports
        },
    }


def render_lua_seed(reports: Sequence[SpecReport], manifest: Mapping[str, Any]) -> str:
    """Render a review-only Lua seed without spell IDs or runtime registration."""

    def lua_string(value: str) -> str:
        return json.dumps(value, ensure_ascii=False)

    lines = [
        "-- Generated by SimC Window / Inject Parser.",
        "-- REVIEW ONLY: not included by !TacticEcho.toc and contains no SpellID mapping.",
        "-- Do not load this file into the AddOn before manual review and SpellID resolution.",
        "return {",
        f"  schemaVersion = {SCHEMA_VERSION},",
        f"  toolVersion = {lua_string(TOOL_VERSION)},",
        f"  generatedAtUtc = {lua_string(str(manifest.get('generated_at_utc', '')))},",
        "  specs = {",
    ]
    for report in reports:
        lines.extend(
            [
                f"    [{lua_string(report.spec_key)}] = {{",
                f"      class = {lua_string(report.class_label)},",
                f"      spec = {lua_string(report.spec_label)},",
                f"      teProfileKey = {lua_string(report.te_profile_key or '')},",
                "      windowActions = {",
            ]
        )
        lines.extend(f"        {lua_string(candidate.action)}," for candidate in report.windows)
        lines.extend(["      },", "      injectActions = {"])
        lines.extend(
            f"        {{ key = {lua_string(candidate.candidate_key)}, action = {lua_string(candidate.action)}, kind = {lua_string(candidate.inject_type or 'spell')} }},"
            for candidate in report.injects
        )
        lines.extend(["      },", "    },"])
    lines.extend(["  },", "}", ""])
    return "\n".join(lines)


def write_outputs(
    out_dir: Path,
    reports: Sequence[SpecReport],
    manifest: Mapping[str, Any],
) -> dict[str, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "simc_window_inject_candidates.json"
    txt_path = out_dir / "simc_window_inject_review.txt"
    template_path = out_dir / "simc_window_inject_overrides.template.json"
    lua_path = out_dir / "simc_window_inject_review_seed.lua"
    manifest_path = out_dir / "simc_window_inject_source_manifest.json"

    json_path.write_text(
        json.dumps(report_to_json(reports, manifest), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    txt_path.write_text(render_review_txt(reports, manifest), encoding="utf-8")
    template_path.write_text(
        json.dumps(build_override_template(reports), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    lua_path.write_text(render_lua_seed(reports, manifest), encoding="utf-8")
    manifest_path.write_text(
        json.dumps(dict(manifest), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return {
        "candidates_json": json_path,
        "review_txt": txt_path,
        "overrides_template": template_path,
        "review_lua_seed": lua_path,
        "source_manifest": manifest_path,
    }


def run_parser(
    simc_root: Path | str,
    out_dir: Path | str,
    *,
    selected_specs: Sequence[str] | None = None,
    overrides_path: Path | str | None = None,
) -> dict[str, Path]:
    reports, manifest = build_reports(
        Path(simc_root),
        selected_specs=selected_specs,
        overrides_path=Path(overrides_path) if overrides_path else None,
    )
    if not reports:
        raise SimcParserError("筛选后没有可输出的专精。")
    return write_outputs(Path(out_dir), reports, manifest)
