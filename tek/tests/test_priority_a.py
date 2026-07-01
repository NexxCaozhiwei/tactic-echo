from tek.src.physical_input import PhysicalInputPause
from tek.app.settings_store import AppSettings

def test_manual_priority_profiles():
    assert PhysicalInputPause(profile="aggressive").snapshot().recovery_ms == 0
    assert PhysicalInputPause(profile="balanced").snapshot().recovery_ms == 30
    assert PhysicalInputPause(profile="manual_first").snapshot().recovery_ms == 250

def test_manual_priority_setting_normalizes():
    assert AppSettings.from_dict({"manual_priority_mode":"manual_first"}).manual_priority_mode == "manual_first"
    assert AppSettings.from_dict({"manual_priority_mode":"bad"}).manual_priority_mode == "balanced"
