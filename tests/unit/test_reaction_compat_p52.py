"""P5.7 automatic-interrupt suspension contract.

Historical P5.6 eligibility routes remain read-only implementation detail while
P5.7 keeps automatic interrupt hard-paused: even old enabled SavedVariables,
positive cast evidence, and a safe binding may not create a candidate or a
TEAP/TEK reaction request.
"""
from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUTO = ROOT / "addon" / "!TacticEcho" / "Tactics" / "AutoReaction.lua"


def run_texlua(script: str) -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return
    with tempfile.TemporaryDirectory() as tmp:
        test_file = Path(tmp) / "reaction_api_event_p56.lua"
        test_file.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


def test_auto_interrupt_is_hard_suspended_even_when_legacy_settings_and_evidence_are_ready() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        TacticEchoDB = {{}}
        GetTime = function() return 1 end

        -- Deliberately retain a legacy enabled preference and provide all
        -- previously sufficient runtime evidence. P5.7 must still terminate
        -- before it can create a reaction candidate.
        local tactics = {{ autoReaction = {{ interrupt = {{
            enabled = true, compatibilityActiveCast = true,
            targetOrder = {{ "target" }}, targetEnabled = {{ target = true }},
        }} }} }}
        _G.TacticEcho.Config = {{ Normalize = {{ All = function() return {{}}, tactics end }} }}
        _G.TacticEcho.ReactionBindings = {{ GetSnapshot = function() return {{ interrupt = {{{{
            role = "interrupt", spellID = 147362, routes = {{ target = {{
                bindingReady = true, safeForFutureAuto = true, binding = "F", bindingToken = 133,
            }} }},
        }}}} }} end }}
        _G.TacticEcho.ReactionInterruptEvents = {{ GetEvidence = function()
            return {{ active = true, status = "interruptible", age = 0.01, reason = "unit_event_interruptible" }}
        end }}
        _G.TacticEcho.ReactionObservation = {{ Sample = function()
            return {{ observedAt = 1, sources = {{ target = {{
                exists = true, hostile = true, alive = true, cast = {{
                    active = true, continuity = "live", castSerial = 1, spellID = 900001,
                    startTimeMS = 100, endTimeMS = 3000, kind = "cast",
                    directInterruptibilityKnown = true, interruptibleKnown = true, interruptible = true,
                }},
            }} }} }}
        end }}
        dofile({str(AUTO)!r})
        local result = _G.TacticEcho.AutoReaction:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if result.kind ~= "none" or result.reason ~= "auto_interrupt_suspended"
            or result.suspended ~= true or result.bindingToken ~= nil then
            error("automatic_interrupt_not_hard_suspended:" .. tostring(result.kind) .. ":" .. tostring(result.reason))
        end
        local snapshot = _G.TacticEcho.AutoReaction:GetSnapshot()
        if snapshot.state ~= "suspended" or snapshot.enabled ~= false or snapshot.suspended ~= true then
            error("suspension_snapshot_not_persisted")
        end
        '''
    )
    run_texlua(script)


def test_p57_forces_suspension_in_defaults_normalization_and_ui() -> None:
    defaults = (ROOT / "addon" / "!TacticEcho" / "Config" / "Defaults.lua").read_text(encoding="utf-8")
    normalize = (ROOT / "addon" / "!TacticEcho" / "Config" / "Normalize.lua").read_text(encoding="utf-8")
    panel = (ROOT / "addon" / "!TacticEcho" / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
    auto = AUTO.read_text(encoding="utf-8")
    assert "compatibilityActiveCast = false" in defaults
    assert "interrupt.compatibilityActiveCast = false" in normalize
    assert "interrupt.enabled = false" in normalize
    assert "interrupt.suspended = true" in normalize
    assert "自动打断（当前不可用）" in panel
    assert "暂停边界：自动打断不扫描目标优先级" in panel
    assert 'suspensionReason = "auto_interrupt_suspended"' in auto
