"""P3 read-only reaction observation is retired from the loaded addon."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def test_p3_observer_and_protocol_monitor_are_not_loaded() -> None:
    toc = read("!TacticEcho.toc")
    assert "Tactics/ReactionObservation.lua" not in toc
    assert "Tactics/ProtocolMonitor.lua" not in toc


def test_tactical_advisors_publish_retired_reaction_snapshot_only() -> None:
    advisors = read("Tactics/TacticalAdvisors.lua")
    assert "reaction = emptyReaction(\"retired_scope\")" in advisors
    assert "interrupt = emptyInterrupt(\"retired_scope\")" in advisors
    assert "applyReactionReadOnly(reaction, interrupt, advisory)" in advisors
    assert "Product scope is intentionally narrowed" in advisors


def test_hud_model_does_not_materialize_reaction_lanes() -> None:
    model = read("UI/TacticalHudModel.lua")
    assert "interrupt = nil" in model
    assert "control = nil" in model
    assert "mobility = nil" in model
    assert "Retired lanes stay structurally present as empty tables" in model
