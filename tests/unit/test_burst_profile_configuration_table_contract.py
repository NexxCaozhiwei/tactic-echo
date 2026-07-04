from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILE_SOURCE = (ROOT / "addon" / "!TacticEcho" / "Tactics" / "BurstProfiles.lua").read_text(encoding="utf-8")

EXPECTED = {
    "trigger": {
        "PALADIN_3": [343527],
        "MAGE_3": [84714],
        "MAGE_2": [153561],
        "MAGE_1": [321507],
        "DRUID_2": [391528],
        "DRUID_1": [202770],
        "HUNTER_2": [260243],
    },
    "injection": {
        "PALADIN_3": [31884],
        "MAGE_3": [55342],
        "MAGE_2": [190319],
        "MAGE_1": [365350],
        "DRUID_2": [106951],
        "DRUID_1": [102560],
        "HUNTER_2": [288613],
    },
}


def _seed_section(name: str, next_name: str) -> str:
    start = PROFILE_SOURCE.index(f"local {name}")
    end = PROFILE_SOURCE.index(f"local {next_name}", start)
    return PROFILE_SOURCE[start:end]


def _seed_values(section: str, profile_key: str) -> list[int]:
    match = re.search(rf"^\s*{re.escape(profile_key)}\s*=\s*\{{([^}}]*)\}},", section, re.MULTILINE)
    assert match, f"missing {profile_key} seed"
    values = [int(value) for value in re.findall(r"\d+", match.group(1))]
    return values


def test_configuration_table_default_window_seeds_are_exact() -> None:
    section = _seed_section("REFERENCE_TRIGGER_SEEDS", "REFERENCE_INJECTION_SEEDS")
    for profile_key, expected in EXPECTED["trigger"].items():
        assert _seed_values(section, profile_key) == expected


def test_configuration_table_default_injection_seeds_are_exact() -> None:
    section = _seed_section("REFERENCE_INJECTION_SEEDS", "REFERENCE_DURATION_SEEDS")
    for profile_key, expected in EXPECTED["injection"].items():
        assert _seed_values(section, profile_key) == expected


def test_configuration_table_mapping_remains_specialization_sequence_only() -> None:
    auto_burst = (ROOT / "addon" / "!TacticEcho" / "Tactics" / "AutoBurst.lua").read_text(encoding="utf-8")
    profiles = (ROOT / "addon" / "!TacticEcho" / "Tactics" / "BurstProfiles.lua").read_text(encoding="utf-8")
    assert "GetAutoBurstSequence" in auto_burst
    assert 'source = "profile_sequence"' in auto_burst
    assert "autoBurstUseProfileFallback" not in auto_burst
    assert "autoBurstWindowSpellID" not in auto_burst
    assert "AUTO_BURST_MAX_INJECTIONS = 3" in profiles
