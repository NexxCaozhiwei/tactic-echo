"""P4/P5 automatic reaction transport is retired from the loaded addon."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def test_auto_reaction_modules_are_not_loaded() -> None:
    toc = read("!TacticEcho.toc")
    for module in (
        "Tactics/ReactionObservation.lua",
        "Tactics/ReactionInterruptEvents.lua",
        "Tactics/AutoReaction.lua",
    ):
        assert module not in toc


def test_signal_frame_keeps_reaction_path_optional_and_inactive_without_module() -> None:
    signal = read("Signal/SignalFrame.lua")
    assert "TE.AutoReaction and type(TE.AutoReaction.Evaluate)" in signal
    assert "reactionDecision" in signal
    assert "stableReactionCandidate" in signal


def test_reaction_protocol_bit_remains_parser_safe_but_no_addon_candidate_source_loaded() -> None:
    encoder = read("Signal/SignalEncoder.lua")
    toc = read("!TacticEcho.toc")
    assert 'dispatchOrigin ~= "burst" and dispatchOrigin ~= "reaction"' in encoder
    assert 'if dispatchOrigin == "reaction" then flags = flags + 64 end' in encoder
    assert "Tactics/AutoReaction.lua" not in toc
