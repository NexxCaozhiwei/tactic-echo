import re
from pathlib import Path


FIELD_PATTERNS = {
    "schemaVersion": re.compile(r'\["schemaVersion"\]\s*=\s*(\d+)'),
    "component": re.compile(r'\["component"\]\s*=\s*"([^"]+)"'),
    "eventType": re.compile(r'\["eventType"\]\s*=\s*"([^"]+)"'),
    "protocolVersion": re.compile(r'\["protocolVersion"\]\s*=\s*(\d+)'),
    "sessionEpoch": re.compile(r'\["sessionEpoch"\]\s*=\s*(\d+)'),
    "frameFreshnessCounter": re.compile(r'\["frameFreshnessCounter"\]\s*=\s*(\d+)'),
    "catalogVersion": re.compile(r'\["catalogVersion"\]\s*=\s*(\d+)'),
    "catalogFingerprint": re.compile(r'\["catalogFingerprint"\]\s*=\s*(\d+)'),
    "profileFingerprint": re.compile(r'\["profileFingerprint"\]\s*=\s*(\d+)'),
    "sequence": re.compile(r'\["sequence"\]\s*=\s*(\d+)'),
    "actionCode": re.compile(r'\["actionCode"\]\s*=\s*(\d+)'),
    "actionId": re.compile(r'\["actionId"\]\s*=\s*"([^"]+)"'),
    "spellID": re.compile(r'\["spellID"\]\s*=\s*(\d+)'),
    "checksum": re.compile(r'\["checksum"\]\s*=\s*(\d+)'),
    "dispatchState": re.compile(r'\["dispatchState"\]\s*=\s*"([^"]+)"'),
}

_MAPPING_SCALAR_FIELDS = (
    "schemaVersion", "component", "eventType", "exportedAt", "elapsed", "reason",
)
_MAPPING_CACHE_FIELDS = (
    "generation", "scanReason", "scannedButtons", "visibleButtons", "entries", "macroEntries",
    "diagnostics", "mainPage", "blockedBySpecialActionBar",
)
_MAPPING_ENTRY_FIELDS = (
    "buttonName", "bar", "barOrder", "buttonIndex", "visualOrder", "actionSlot", "actionSlotSource",
    "actionType", "actionInfoId", "spellID", "source", "bindingCommand", "rawBinding", "binding",
    "bindingToken", "inputType", "bindingError", "macroID", "macroName", "macroSpellID",
    "macroResolvedSpellID", "macroActionInfoSpellID", "macroLookupSource", "macroFailureReason", "scanReason",
)

_MAPPING_MOVEMENT_FIELDS = ("command", "primary", "secondary")


def read_latest_signal(path: str | Path) -> dict | None:
    return latest_signal_from_text(Path(path).read_text(encoding="utf-8-sig"))


def read_signal_by_sequence(path: str | Path, sequence: int) -> dict | None:
    text = Path(path).read_text(encoding="utf-8-sig")
    return signal_by_sequence_from_text(text, sequence)


def read_mapping_export(path: str | Path) -> dict | None:
    return mapping_export_from_text(Path(path).read_text(encoding="utf-8-sig"))


def signal_by_sequence_from_text(text: str, sequence: int) -> dict | None:
    records = signal_records_from_text(text)
    for record in reversed(records):
        if record.get("sequence") == sequence:
            return record
    return None


def latest_signal_from_text(text: str) -> dict | None:
    records = signal_records_from_text(text)
    if not records:
        return None
    return records[-1]


def signal_records_from_text(text: str) -> list[dict]:
    signal_index = text.find('["signal"]')
    if signal_index < 0:
        return []

    records = []
    for chunk in top_level_table_chunks(text[signal_index:], '["frames"]'):
        record = parse_signal_chunk(chunk)
        if record:
            records.append(record)
    return records


def top_level_table_chunks(text: str, table_name: str) -> list[str]:
    table_index = text.find(table_name)
    if table_index < 0:
        return []
    return top_level_chunks_from_table(text, table_index)


def _table_chunk_after(text: str, index: int) -> str | None:
    start = text.find("{", index)
    if start < 0:
        return None
    depth = 0
    in_string = False
    escaped = False
    for offset in range(start, len(text)):
        char = text[offset]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start:offset + 1]
    return None


def top_level_chunks_from_table(text: str, table_index: int) -> list[str]:
    table = _table_chunk_after(text, table_index)
    if not table:
        return []
    chunks = []
    depth = 0
    record_start = None
    in_string = False
    escaped = False
    for index, char in enumerate(table[1:], start=1):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
            if depth == 1:
                record_start = index
        elif char == "}":
            if depth == 1 and record_start is not None:
                chunks.append(table[record_start:index + 1])
                record_start = None
            depth -= 1
    return chunks


def _unescape_lua_string(value: str) -> str:
    return value.replace(r'\\', '\\').replace(r'\"', '"').replace(r'\n', '\n')


def _parse_scalar(chunk: str, key: str):
    pattern = re.compile(r'\["' + re.escape(key) + r'"\]\s*=\s*(?:"((?:\\.|[^"])*)"|(true|false)|(-?\d+(?:\.\d+)?))')
    match = pattern.search(chunk)
    if not match:
        return None
    if match.group(1) is not None:
        return _unescape_lua_string(match.group(1))
    if match.group(2) is not None:
        return match.group(2) == "true"
    number = match.group(3)
    if number is not None:
        return float(number) if "." in number else int(number)
    return None


def _parse_fields(chunk: str, keys: tuple[str, ...]) -> dict:
    return {key: value for key in keys if (value := _parse_scalar(chunk, key)) is not None}


def mapping_export_from_text(text: str) -> dict | None:
    marker = '["mappingExport"]'
    index = text.find(marker)
    if index < 0:
        return None
    chunk = _table_chunk_after(text, index)
    if not chunk:
        return None
    export = _parse_fields(chunk, _MAPPING_SCALAR_FIELDS)
    if not export:
        return None

    cache_index = chunk.find('["cache"]')
    cache_chunk = _table_chunk_after(chunk, cache_index) if cache_index >= 0 else None
    if cache_chunk:
        export["cache"] = _parse_fields(cache_chunk, _MAPPING_CACHE_FIELDS)

    # cache.entries is a scalar count; use the final entries table at the mapping-export root.
    entries_index = chunk.rfind('["entries"]')
    entries_chunk = _table_chunk_after(chunk, entries_index) if entries_index >= 0 else None
    entries: list[dict] = []
    if entries_chunk:
        for entry_chunk in top_level_chunks_from_table(entries_chunk, 0):
            item = _parse_fields(entry_chunk, _MAPPING_ENTRY_FIELDS)
            if item:
                entries.append(item)
    export["entries"] = entries

    movement_index = chunk.find('["movementBindings"]')
    movement_chunk = _table_chunk_after(chunk, movement_index) if movement_index >= 0 else None
    movement_bindings: list[dict] = []
    if movement_chunk:
        for movement_entry in top_level_chunks_from_table(movement_chunk, 0):
            item = _parse_fields(movement_entry, _MAPPING_MOVEMENT_FIELDS)
            if item.get("command"):
                movement_bindings.append(item)
    export["movementBindings"] = movement_bindings

    # The addon snapshot already excludes macro bodies.  This defensive filter
    # keeps the Python-side contract true even if an older/custom export has
    # additional fields.
    forbidden = {"macroBody", "body", "actionText"}
    for entry in export["entries"]:
        for key in list(entry):
            if key in forbidden:
                entry.pop(key, None)
    return export


def parse_signal_chunk(chunk: str) -> dict | None:
    record = {}
    for key, pattern in FIELD_PATTERNS.items():
        match = pattern.search(chunk)
        if not match:
            continue
        value = match.group(1)
        record[key] = int(value) if value.isdigit() else value

    if "sequence" not in record or "actionCode" not in record:
        return None
    record.setdefault("schemaVersion", 1)
    record.setdefault("component", "TE")
    record.setdefault("eventType", "signal_frame")
    return record
