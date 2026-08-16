from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def test_retired_tactical_engine_modules_are_not_loaded():
    toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
    assert "Tactics/EnvironmentCompatibility.lua" not in toc
    assert "Tactics/RecommendationQueue.lua" not in toc
    assert "Tactics/AdvisoryPlanner.lua" not in toc


def test_primary_burst_runtime_boundaries_are_explicit():
    advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
    for token in ("scope_primary_burst", "TE.BurstPlanner.Build", "retired_scope"):
        assert token in advisors
    narrowed = advisors.split("function TacticalAdvisors:Refresh(force)", 1)[1].split("function TacticalAdvisors:GetSnapshot()", 1)[0]
    for forbidden in ("TE.AdvisoryPlanner:Build", "TE.RecommendationQueue:Build", "TE.TacticalTelemetry:Record"):
        assert forbidden not in narrowed
