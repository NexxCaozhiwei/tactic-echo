from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / 'addon' / '!TacticEcho'

def test_tactical_engine_modules_loaded():
    toc = (ADDON / '!TacticEcho.toc').read_text(encoding='utf-8')
    assert 'Tactics/EnvironmentCompatibility.lua' in toc
    assert 'Tactics/RecommendationQueue.lua' in toc

def test_readonly_boundaries_are_explicit():
    for rel in ['Tactics/AdvisoryPlanner.lua','Tactics/RecommendationQueue.lua','Tactics/EnvironmentCompatibility.lua']:
        text=(ADDON/rel).read_text(encoding='utf-8')
        assert 'read-only' in text.lower() or 'readonly' in text.lower() or 'advisory-only' in text.lower()
    q=(ADDON/'Tactics/RecommendationQueue.lua').read_text(encoding='utf-8')
    for bucket in ['emergency','interrupt','primary','burst','control','mobility','candidate']:
        assert bucket in q

def test_environment_is_boolean_only_contract():
    text=(ADDON/'Tactics/EnvironmentCompatibility.lua').read_text(encoding='utf-8')
    for flag in ['dangerZone','knockbackRisk','highPressure']:
        assert flag in text
    assert 'UnitPosition' not in text
