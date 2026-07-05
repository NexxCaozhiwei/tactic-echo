"""CooldownTracker must not index protected tooltip strings directly."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TRACKER = ROOT / "addon" / "!TacticEcho" / "Tactics" / "CooldownTracker.lua"


def test_tooltip_cooldown_text_is_pcall_guarded() -> None:
    source = TRACKER.read_text(encoding="utf-8")
    assert "local function lineText(region)" in source
    assert "pcall(region.GetText, region)" in source
    assert "pcall(function()" in source
    assert "string.match(text" in source
    assert ":GetText())" not in source
    assert "text:match" not in source
