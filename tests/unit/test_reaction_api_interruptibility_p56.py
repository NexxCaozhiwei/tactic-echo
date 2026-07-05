"""P5.6 regression: preserve direct `notInterruptible=false` from the WoW APIs."""
from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OBSERVATION = ROOT / "addon" / "!TacticEcho" / "Tactics" / "ReactionObservation.lua"


def run_texlua(script: str) -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return
    with tempfile.TemporaryDirectory() as tmp:
        test_file = Path(tmp) / "reaction_observation_api_false_p56.lua"
        test_file.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


def test_unit_casting_and_channel_false_materialize_as_interruptible() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        GetTime = function() return 1 end
        UnitExists = function(unit) return unit == "target" end
        UnitIsDeadOrGhost = function() return false end
        UnitCanAttack = function() return true end
        UnitIsPlayer = function() return false end
        UnitClassification = function() return "normal" end
        UnitLevel = function() return 70 end
        UnitIsBossMob = function() return false end

        local mode = "cast_false"
        UnitCastingInfo = function(unit)
            if unit ~= "target" or mode ~= "cast_false" and mode ~= "cast_true" then return end
            local notInterruptible = mode == "cast_true"
            return "opaque", nil, nil, 100, 3000, false, "Cast-1", notInterruptible, 147362
        end
        UnitChannelInfo = function(unit)
            if unit ~= "target" or mode ~= "channel_false" then return end
            return "opaque", nil, nil, 100, 3000, false, false, 23456
        end

        dofile({str(OBSERVATION)!r})
        local function sample()
            return _G.TacticEcho.ReactionObservation:Refresh().sources.target.cast
        end

        local castFalse = sample()
        if castFalse.active ~= true or castFalse.directInterruptibilityKnown ~= true
            or castFalse.interruptible ~= true or castFalse.interruptibilitySource ~= "unit_api" then
            error("casting_false_lost:" .. tostring(castFalse.directInterruptibilityKnown)
                .. ":" .. tostring(castFalse.interruptible))
        end

        mode = "cast_true"
        local castTrue = sample()
        if castTrue.active ~= true or castTrue.directInterruptibilityKnown ~= true
            or castTrue.interruptible ~= false then
            error("casting_true_not_steel:" .. tostring(castTrue.directInterruptibilityKnown)
                .. ":" .. tostring(castTrue.interruptible))
        end

        mode = "channel_false"
        local channelFalse = sample()
        if channelFalse.active ~= true or channelFalse.kind ~= "channel"
            or channelFalse.directInterruptibilityKnown ~= true
            or channelFalse.interruptible ~= true then
            error("channel_false_lost:" .. tostring(channelFalse.kind)
                .. ":" .. tostring(channelFalse.directInterruptibilityKnown)
                .. ":" .. tostring(channelFalse.interruptible))
        end
        '''
    )
    run_texlua(script)


def test_source_does_not_use_lua_and_or_for_direct_false() -> None:
    source = OBSERVATION.read_text(encoding="utf-8")
    assert "local directNotInterruptible = nil" in source
    assert "directNotInterruptible = plainBoolean(apiRecord.notInterruptible)" in source
    assert "apiRecord and plainBoolean(apiRecord.notInterruptible) or nil" not in source
