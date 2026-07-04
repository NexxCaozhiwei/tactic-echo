from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def test_macro_semantics_loaded_and_no_extra_dispatch_contract():
    toc=(ROOT/'addon/!TacticEcho/!TacticEcho.toc').read_text()
    body=(ROOT/'addon/!TacticEcho/Actions/MacroSemantics.lua').read_text()
    assert 'Actions/MacroSemantics.lua' in toc
    assert 'never creates a new dispatch path' in body
    assert 'macro_body_broad_castsequence' in body
    assert 'never creates a new dispatch path' in body

def test_priority_a_docs_and_rescan_events():
    resolver=(ROOT/'addon/!TacticEcho/Actions/ActionBarBindingResolver.lua').read_text()
    assert 'UPDATE_SHAPESHIFT_FORMS' in resolver
    assert (ROOT/'docs/PRIORITY_A_MANUAL_CALIBRATION.md').exists()
