from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MACRO = ROOT / "addon" / "!TacticEcho" / "Actions" / "MacroSemantics.lua"


class MacroBroadRuntimeTests(unittest.TestCase):
    def test_common_targeted_conditional_and_sequence_macros_are_classified(self) -> None:
        texlua = shutil.which("texlua")
        if not texlua:
            self.skipTest("texlua not available")
        script = textwrap.dedent(
            f'''\
            _G.TacticEcho = {{}}
            dofile({str(MACRO)!r})
            local M = _G.TacticEcho.MacroSemantics
            local function expect(body, spellID, spellName, policy, wanted, wantedKind)
                local semantics = M:Analyze(body)
                local ok, kind = M:MatchSpell(semantics, spellID, spellName, policy)
                if ok ~= wanted or kind ~= wantedKind then
                    error("unexpected:" .. tostring(ok) .. ":" .. tostring(kind))
                end
            end
            expect("/stopcasting\\n/cast [@cursor] 260243", 260243, "Volley", "strict", true, "macro_body_single_spell")
            expect("/cast [mod] 288613; [@cursor] 260243", 260243, "Volley", "strict", false, "macro_body_ambiguous_spell_branch")
            expect("/cast [mod] 288613; [@cursor] 260243", 260243, "Volley", "broad", true, "macro_body_broad_multi_spell")
            expect("/castsequence reset=target 260243,288613", 260243, "Volley", "strict", false, "macro_castsequence_requires_current_macro_spell")
            expect("/castsequence reset=target 260243,288613", 260243, "Volley", "broad", true, "macro_body_broad_castsequence")
            '''
        )
        with tempfile.TemporaryDirectory() as tmp:
            test_file = Path(tmp) / "macro_runtime.lua"
            test_file.write_text(script, encoding="utf-8")
            result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_target_switch_fallback_interrupt_macro_is_recognized_for_macro_managed_auto(self) -> None:
        texlua = shutil.which("texlua")
        if not texlua:
            self.skipTest("texlua not available")
        script = textwrap.dedent(
            f'''\
            _G.TacticEcho = {{}}
            dofile({str(MACRO)!r})
            local M = _G.TacticEcho.MacroSemantics
            local body = [[#showtooltip 反制射击
            /stopcasting
            /cast [@focus,nodead] 反制射击
            /cleartarget
            /targetenemy
            /cast 反制射击
            /targetlasttarget]]
            local semantics = M:Analyze(body)
            if semantics.hasTargetMutation ~= true then error("target_mutation_not_recorded") end
            if #semantics.targetMutationCommands ~= 3 then error("target_mutation_count") end
            local matched, kind = M:MatchSpell(semantics, 147362, "反制射击", "broad")
            if matched ~= true or kind ~= "macro_body_single_spell" then
                error("association:" .. tostring(matched) .. ":" .. tostring(kind))
            end
            local detail = M:DescribeSpellRoutes(semantics, 147362, "反制射击")
            if detail.recognized ~= true or detail.hasTargetMutation ~= true
                or detail.singleSpellTargetSwitchFallback ~= true
                or detail.reason ~= "macro_target_switch_fallback_auto"
                or detail.macroManagedTargetAuto ~= true
                or detail.autoRouteMode ~= "macro_managed_target" then
                error("route:" .. tostring(detail.recognized) .. ":" .. tostring(detail.reason))
            end
            '''
        )
        with tempfile.TemporaryDirectory() as tmp:
            test_file = Path(tmp) / "target_switch_macro_runtime.lua"
            test_file.write_text(script, encoding="utf-8")
            result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class ReactionBindingTargetSwitchRuntimeTests(unittest.TestCase):
    def test_target_switch_fallback_macro_is_visible_and_macro_managed_auto_safe(self) -> None:
        texlua = shutil.which("texlua")
        if not texlua:
            self.skipTest("texlua not available")
        reaction = ROOT / "addon" / "!TacticEcho" / "Tactics" / "ReactionBindings.lua"
        script = textwrap.dedent(
            f'''\
            _G.TacticEcho = {{}}
            dofile({str(MACRO)!r})
            local M = _G.TacticEcho.MacroSemantics
            local body = [[#showtooltip 反制射击
            /stopcasting
            /cast [@focus,nodead] 反制射击
            /cleartarget
            /targetenemy
            /cast 反制射击
            /targetlasttarget]]
            _G.C_Spell = {{
                GetSpellInfo = function(spellID)
                    return {{ name = spellID == 147362 and "反制射击" or tostring(spellID), iconID = 1 }}
                end,
            }}
            _G.TacticEcho.Context = {{
                GetPlayer = function()
                    return {{ class = "HUNTER", specIndex = 1 }}
                end,
            }}
            _G.TacticEcho.AbilityProfiles = {{
                GetInterrupts = function() return {{ 147362 }} end,
                GetReactionControls = function() return {{}} end,
            }}
            _G.TacticEcho.ActionBarBindingResolver = {{
                GetButtonCache = function() return {{ generation = 11 }} end,
                ResolveSpell = function(_, spellID)
                    return {{
                        status = "Ready",
                        candidates = {{
                            {{
                                source = "macro",
                                parsed = {{ binding = "F", token = 4 }},
                                actionSlot = 1,
                                buttonName = "ActionButton1",
                                macroName = "focus_fallback_interrupt",
                                macroSemantics = M:Analyze(body),
                            }},
                        }},
                    }}
                end,
            }}
            dofile({str(reaction)!r})
            local snapshot = _G.TacticEcho.ReactionBindings:GetSnapshot(true)
            local entry = snapshot.interrupt[1]
            if entry.status ~= "ready" then error("status:" .. tostring(entry.status)) end
            if entry.macroRouteReason ~= "macro_target_switch_fallback_auto" then error("reason:" .. tostring(entry.macroRouteReason)) end
            if entry.routes.focus == nil or entry.routes.target == nil then error("routes_missing") end
            if entry.routes.focus.safeForFutureAuto ~= true or entry.routes.target.safeForFutureAuto ~= true then
                error("target_switch_macro_not_marked_auto_safe")
            end
            if entry.routes.focus.macroManagedTarget ~= true or entry.routes.target.macroManagedTarget ~= true then
                error("target_switch_macro_not_marked_macro_managed")
            end
            if entry.macroManagedTargetAuto ~= true or entry.targetSwitchAuto ~= true then
                error("entry_not_marked_macro_managed_auto")
            end
            '''
        )
        with tempfile.TemporaryDirectory() as tmp:
            test_file = Path(tmp) / "reaction_target_switch_runtime.lua"
            test_file.write_text(script, encoding="utf-8")
            result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()


class MacroInventorySlotRuntimeTests(unittest.TestCase):
    def test_single_trinket_macro_is_associated_and_dual_slot_macro_is_rejected(self) -> None:
        texlua = shutil.which("texlua")
        if not texlua:
            self.skipTest("texlua not available")
        script = textwrap.dedent(
            f'''\
            _G.TacticEcho = {{}}
            dofile({str(MACRO)!r})
            local M = _G.TacticEcho.MacroSemantics
            local function expect(body, slot, wanted, wantedKind)
                local semantics = M:Analyze(body)
                local ok, kind = M:MatchInventorySlot(semantics, slot, "broad")
                if ok ~= wanted or kind ~= wantedKind then
                    error("unexpected:" .. tostring(ok) .. ":" .. tostring(kind))
                end
            end
            expect("#showtooltip\\n/stopcasting\\n/use [combat] 13", 13, true, "macro_inventory_slot_broad")
            expect("/use [mod:shift] 13; 14", 13, false, "macro_multiple_trinket_slots")
            expect("/use 13\\n/use 14", 14, false, "macro_multiple_trinket_slots")
            '''
        )
        with tempfile.TemporaryDirectory() as tmp:
            test_file = Path(tmp) / "macro_inventory_runtime.lua"
            test_file.write_text(script, encoding="utf-8")
            result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
