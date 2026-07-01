"""TEK-local keyboard whitelist for continuous dispatch intervention.

This module deliberately contains no WoW configuration discovery.  Whether a
real key press should preserve TEK dispatch is defined only by the user's local
TEK whitelist.
"""
from __future__ import annotations

import ast
from dataclasses import dataclass
from typing import Iterable


DEFAULT_DISPATCH_EXEMPT_KEYS = ("W", "A", "S", "D", "SPACE")
MODIFIER_KEYS = frozenset({"CTRL", "ALT", "SHIFT", "WIN"})

# Windows virtual-key constants used by the low-level hook.  Standalone
# modifier keys are intentionally absent: they cannot be added to the local
# dispatch whitelist because a modifier alone is not a usable intervention key.
_NAME_TO_VK = {"SPACE": 0x20, "UP": 0x26, "DOWN": 0x28, "LEFT": 0x25, "RIGHT": 0x27}
_NAME_TO_VK.update({chr(code): code for code in range(ord("A"), ord("Z") + 1)})
_NAME_TO_VK.update({str(number): ord(str(number)) for number in range(10)})
for number in range(1, 13):
    _NAME_TO_VK[f"F{number}"] = 0x6F + number
_NAME_TO_VK.update({"ESC": 0x1B, "ENTER": 0x0D, "TAB": 0x09})

_ALIASES = {
    " ": "SPACE",
    "SPACEBAR": "SPACE",
    "VK_SPACE": "SPACE",
    "ARROWUP": "UP",
    "ARROWDOWN": "DOWN",
    "ARROWLEFT": "LEFT",
    "ARROWRIGHT": "RIGHT",
    # Tk keysyms emitted by the record-key control on Windows.
    "CONTROL": "CTRL",
    "CONTROL_L": "CTRL",
    "CONTROL_R": "CTRL",
    "SHIFT_L": "SHIFT",
    "SHIFT_R": "SHIFT",
    "ALT_L": "ALT",
    "ALT_R": "ALT",
    "OPTION": "ALT",
    "WIN_L": "WIN",
    "WIN_R": "WIN",
    "SUPER_L": "WIN",
    "SUPER_R": "WIN",
    "RETURN": "ENTER",
    "ESCAPE": "ESC",
}

_HIGH_RISK = {
    "ESC",
    "ENTER",
    "TAB",
    *[str(i) for i in range(10)],
    *[f"F{i}" for i in range(1, 13)],
    "Q",
    "E",
    "R",
    "F",
    "G",
}


@dataclass(frozen=True)
class KeyNormalizationResult:
    """Result of parsing a persisted or imported whitelist value.

    ``valid`` means the container/serialization itself was understood.  It does
    not mean every supplied token was accepted: unsupported names and standalone
    modifiers are returned in ``discarded`` so import UX can explain the cleanup.
    """

    keys: tuple[str, ...]
    valid: bool
    discarded: tuple[str, ...] = ()


def canonicalize_key(value: object) -> str | None:
    """Return a canonical supported key name or canonical modifier name.

    Modifiers are recognized separately so the UI can explain why they cannot
    be inserted as standalone whitelist entries.  ``normalize_keys`` filters
    them from all persisted runtime values.
    """

    key = str(value or "").strip().upper()
    key = _ALIASES.get(key, key)
    return key if key in _NAME_TO_VK or key in MODIFIER_KEYS else None


def is_modifier_key(value: object) -> bool:
    return canonicalize_key(value) in MODIFIER_KEYS


def _parse_key_values(values: object) -> tuple[list[object] | None, bool]:
    """Parse list-like values plus legacy string serializations safely."""

    if isinstance(values, (list, tuple, set)):
        return list(values), True
    if isinstance(values, str):
        text = values.strip()
        if not text:
            return [], True
        # Older UI reload paths could stringify a tuple, for example
        # ``('W', 'A', 'S', 'D', 'SPACE')``.  Parse only Python literals;
        # never evaluate arbitrary text.
        if text[0:1] in {"[", "(", "{"}:
            try:
                parsed = ast.literal_eval(text)
            except (SyntaxError, ValueError):
                return None, False
            if isinstance(parsed, (list, tuple, set)):
                return list(parsed), True
            return None, False
        if "," in text:
            return [part.strip() for part in text.split(",")], True
        return [text], True
    return None, False


def parse_keys(values: object) -> KeyNormalizationResult:
    """Normalize a whitelist value without silently replacing malformed input."""

    raw_values, parsed = _parse_key_values(values)
    if not parsed or raw_values is None:
        return KeyNormalizationResult((), False)
    if not raw_values:
        return KeyNormalizationResult((), True)

    result: list[str] = []
    discarded: list[str] = []
    for value in raw_values:
        key = canonicalize_key(value)
        if key is None or key in MODIFIER_KEYS:
            discarded.append(str(value))
            continue
        if key not in result:
            result.append(key)

    # A nonempty persisted value containing no usable key is not a trustworthy
    # whitelist.  Import callers can then preserve the user's current setting
    # instead of silently turning the list empty or resetting it.
    if not result:
        return KeyNormalizationResult((), False, tuple(discarded))
    return KeyNormalizationResult(tuple(result), True, tuple(discarded))


def normalize_keys(values: object) -> tuple[str, ...]:
    """Normalize runtime settings, falling back only for malformed values."""

    parsed = parse_keys(values)
    return parsed.keys if parsed.valid else DEFAULT_DISPATCH_EXEMPT_KEYS


@dataclass(frozen=True)
class KeyboardInterventionWhitelist:
    keys: tuple[str, ...] = DEFAULT_DISPATCH_EXEMPT_KEYS

    @classmethod
    def from_keys(cls, values: object) -> "KeyboardInterventionWhitelist":
        return cls(normalize_keys(values))

    def is_exempt_vk(self, vk_code: int) -> bool:
        return int(vk_code) in {_NAME_TO_VK[key] for key in self.keys}

    def diagnostics(self) -> dict:
        return {
            "keys": list(self.keys),
            "key_count": len(self.keys),
            "source": "tek_local_configuration",
            "standalone_modifiers_allowed": False,
        }

    @staticmethod
    def is_high_risk(name: str) -> bool:
        return str(name).upper() in _HIGH_RISK
