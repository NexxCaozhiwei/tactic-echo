"""P5.10 current-action-bar macro identity: exact button, bounded joins, fail-closed."""
from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
MACRO = ADDON / "Actions" / "MacroSemantics.lua"
RESOLVER = ADDON / "Actions" / "ActionBarBindingResolver.lua"
REACTION = ADDON / "Tactics" / "ReactionBindings.lua"
PLANNER = ADDON / "Tactics" / "AdvisoryPlanner.lua"
ADVISORS = ADDON / "Tactics" / "TacticalAdvisors.lua"


def run_texlua(script: str) -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "p510_macro_identity.lua"
        path.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(path)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


def preamble() -> str:
    return f'''\
        _G.TacticEcho = {{ RegisterEventsSafe = function() end }}
        _G.NUM_ACTIONBAR_BUTTONS = 12
        _G.MAX_ACCOUNT_MACROS = 120
        _G.C_Spell = {{
            GetSpellInfo = function(value)
                if value == "冰冻陷阱" or value == 187650 then
                    return {{ spellID = 187650, name = "冰冻陷阱" }}
                end
                if value == "威慑" or value == 186265 then
                    return {{ spellID = 186265, name = "威慑" }}
                end
                return nil
            end,
        }}
        local action1 = 1
        _G.ActionButton1 = {{
            IsShown = function() return true end,
            IsVisible = function() return true end,
            GetAttribute = function(_, key) if key == "action" then return action1 end end,
            GetCenter = function() return 100, 100 end,
        }}
        _G.ActionButton2 = {{
            IsShown = function() return true end,
            IsVisible = function() return true end,
            GetAttribute = function(_, key) if key == "action" then return 2 end end,
            GetCenter = function() return 200, 100 end,
        }}
        _G.GetActionBarPage = function() return 1 end
        _G.GetBonusBarOffset = function() return 0 end
        _G.GetBindingKey = function(command)
            if command == "ACTIONBUTTON1" then return "CTRL-1" end
            if command == "ACTIONBUTTON2" then return "CTRL-2" end
            return nil
        end
        _G.GetActionText = function(slot)
            if slot == 1 then return "冰冻陷阱" end
            if slot == 2 then return "冰冻陷阱" end
            return nil
        end
        _G.CreateFrame = function() return {{ SetScript = function() end }} end
        _G.GetTime = function() return 1 end
        _G.__set_slot1_macro = function(_) end
        dofile({str(MACRO)!r})
        dofile({str(RESOLVER)!r})
    '''


def test_cursor_trap_macro_uses_current_ctrl1_button_not_same_spell_fallback() -> None:
    script = textwrap.dedent(
        preamble()
        + r'''
        _G.GetNumMacros = function() return 1, 0 end
        local slot1IsMacro = true
        _G.__set_slot1_macro = function(value) slot1IsMacro = value == true end
        _G.GetActionInfo = function(slot)
            if slot == 1 and slot1IsMacro then return "macro", 187650, nil, nil end
            if slot == 1 or slot == 2 then return "spell", 187650, nil, nil end
            return nil
        end
        _G.GetMacroInfo = function(index)
            -- Opaque Retail action-info handle: only its label is usable.
            if index == 187650 then return "冰冻陷阱宏", 1, nil end
            if index == 1 then return "冰冻陷阱宏", 1, [[#showtooltip
/cast [@cursor] 冰冻陷阱]] end
            return nil
        end
        _G.GetMacroSpell = function(index)
            if index == 1 then return "冰冻陷阱", nil, 187650 end
            return nil
        end

        local resolver = _G.TacticEcho.ActionBarBindingResolver
        local result = resolver:ResolveSpell(187650)
        if result.status ~= "Ready" or result.source ~= "macro"
            or result.macroID ~= 1 or result.buttonName ~= "ActionButton1"
            or result.actionSlot ~= 1 or result.binding ~= "CTRL+1" then
            error("cursor_trap_not_bound_to_ctrl1:" .. tostring(result.status)
                .. ":" .. tostring(result.buttonName) .. ":" .. tostring(result.actionSlot)
                .. ":" .. tostring(result.binding))
        end
        local diag = result.macroDiagnostic or {}
        if diag.macroIdentityVerified ~= true
            or diag.semanticNameSource ~= "action_info_macro_name"
            or diag.semanticLookupName ~= "冰冻陷阱宏"
            or diag.lookupSource ~= "action_info_name_unique_spell_semantic" then
            error("cursor_trap_identity_not_verified:" .. tostring(diag.semanticNameSource)
                .. ":" .. tostring(diag.lookupSource))
        end

        local card = { spellID = 187650, buttonName = "ActionButton1", actionSlot = 1, bindingSource = "macro", bindingInfo = result }
        local exact = resolver:ResolveManualHudAction(card)
        if exact.status ~= "Ready" or exact.buttonName ~= "ActionButton1" or exact.actionSlot ~= 1 then
            error("exact_hud_ctrl1_not_ready:" .. tostring(exact.status) .. ":" .. tostring(exact.reason))
        end

        -- Move the original button to a different action during a refresh while
        -- CTRL+2 still holds the same direct spell. HUD must block rather than
        -- redirecting the cursor macro card to CTRL+2.
        _G.__set_slot1_macro(false)
        resolver:Invalidate("p510_source_changed")
        local moved = resolver:ResolveManualHudAction(card)
        if moved.status ~= "Blocked" or moved.reason ~= "manual_actionbar_source_changed" then
            error("same_spell_fallback_not_blocked:" .. tostring(moved.status) .. ":" .. tostring(moved.reason))
        end
        '''
    )
    run_texlua(script)


def test_hidden_default_action_slot_can_dispatch_but_not_manual_click() -> None:
    resolver_text = RESOLVER.read_text(encoding="utf-8")
    scan_start = resolver_text.index("local function scanStandardButton")
    scan_end = resolver_text.index("local function scanStanceButton", scan_start)
    scan_block = resolver_text[scan_start:scan_end]
    assert "if not buttonIsVisible(button) then return end" not in scan_block
    assert "local visible = buttonIsVisible(button)" in scan_block
    assert "buttonVisible = visible" in scan_block
    assert "local function manualButtonVisible(button)" in resolver_text
    assert "manual_actionbar_button_hidden" in resolver_text

    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{ RegisterEventsSafe = function() end }}
        _G.NUM_ACTIONBAR_BUTTONS = 12
        _G.MAX_ACCOUNT_MACROS = 120
        _G.C_Spell = {{
            GetSpellInfo = function(value)
                if value == 187650 then return {{ spellID = 187650, name = "Hidden Dispatch Spell" }} end
                return nil
            end,
        }}
        _G.ActionButton1 = {{
            IsShown = function() return false end,
            IsVisible = function() return false end,
            GetAttribute = function(_, key) if key == "action" then return 1 end end,
        }}
        _G.GetActionBarPage = function() return 1 end
        _G.GetBonusBarOffset = function() return 0 end
        _G.GetBindingKey = function(command)
            if command == "ACTIONBUTTON1" then return "SHIFT-3" end
            return nil
        end
        _G.GetActionInfo = function(slot)
            if slot == 1 then return "spell", 187650, nil, nil end
            return nil
        end
        _G.CreateFrame = function() return {{ SetScript = function() end }} end
        _G.GetTime = function() return 1 end

        dofile({str(RESOLVER)!r})

        local resolver = _G.TacticEcho.ActionBarBindingResolver
        local result = resolver:ResolveSpell(187650)
        if result.status ~= "Ready" or result.binding ~= "SHIFT+3" or tonumber(result.bindingToken) <= 0 then
            error("hidden_auto_dispatch_not_ready:" .. tostring(result.status) .. ":" .. tostring(result.binding) .. ":" .. tostring(result.reason))
        end
        if result.buttonVisible ~= false then
            error("hidden_visibility_not_recorded:" .. tostring(result.buttonVisible))
        end
        local manual = resolver:ResolveManualHudAction({{ spellID = 187650 }})
        if manual.status ~= "Blocked" or manual.reason ~= "manual_actionbar_button_hidden" then
            error("hidden_manual_click_not_blocked:" .. tostring(manual.status) .. ":" .. tostring(manual.reason))
        end
        '''
    )
    run_texlua(script)


def test_recovery_rejects_macro_spell_when_current_body_does_not_reference_trap() -> None:
    script = textwrap.dedent(
        preamble()
        + r'''
        _G.GetNumMacros = function() return 1, 0 end
        _G.GetActionInfo = function(slot)
            if slot == 1 then return "macro", 187650, nil, nil end
            return nil
        end
        _G.GetActionText = function() return "冰冻陷阱宏" end
        _G.GetMacroInfo = function(index)
            if index == 187650 then return "冰冻陷阱宏", 1, nil end
            if index == 1 then return "冰冻陷阱宏", 1, [[/cast 威慑]] end
            return nil
        end
        -- Deliberately stale/representative API evidence. It cannot authorise
        -- the macro because the unique body semantic is for a different spell.
        _G.GetMacroSpell = function(index)
            if index == 1 then return "冰冻陷阱", nil, 187650 end
            return nil
        end

        local result = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(187650)
        if result.status == "Ready" or result.bindingToken ~= 0 then
            error("macro_spell_only_fail_open:" .. tostring(result.status))
        end
        local diag = result.macroDiagnostics and result.macroDiagnostics[1] or {}
        if diag.identityFailureReason ~= "macro_semantic_identity_no_spell_match" then
            error("body_semantic_failure_missing:" .. tostring(diag.identityFailureReason))
        end
        '''
    )
    run_texlua(script)


def test_dual_readonly_labels_with_two_surviving_bodies_fail_closed() -> None:
    script = textwrap.dedent(
        preamble()
        + r'''
        _G.GetNumMacros = function() return 2, 0 end
        _G.GetActionInfo = function(slot)
            if slot == 1 then return "macro", 187650, nil, nil end
            return nil
        end
        _G.GetActionText = function() return "冰冻陷阱宏A" end
        _G.GetMacroInfo = function(index)
            if index == 187650 then return "冰冻陷阱宏B", 1, nil end
            if index == 1 then return "冰冻陷阱宏A", 1, [[/cast [@cursor] 冰冻陷阱]] end
            if index == 2 then return "冰冻陷阱宏B", 1, [[/cast 冰冻陷阱]] end
            return nil
        end
        _G.GetMacroSpell = function(index)
            if index == 1 or index == 2 then return "冰冻陷阱", nil, 187650 end
            return nil
        end

        local result = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(187650)
        if result.status == "Ready" then error("dual_label_ambiguity_fail_open") end
        local diag = result.macroDiagnostics and result.macroDiagnostics[1] or {}
        if diag.identityFailureReason ~= "macro_semantic_identity_ambiguous"
            or not diag.semanticCandidateIndexes
            or diag.semanticCandidateIndexes[1] ~= 1
            or diag.semanticCandidateIndexes[2] ~= 2 then
            error("dual_label_ambiguity_missing:" .. tostring(diag.identityFailureReason))
        end
        '''
    )
    run_texlua(script)


def test_opaque_identity_is_excluded_from_manual_cards_and_requires_real_p4_token() -> None:
    resolver = RESOLVER.read_text(encoding="utf-8")
    reaction = REACTION.read_text(encoding="utf-8")
    planner = PLANNER.read_text(encoding="utf-8")
    advisors = ADVISORS.read_text(encoding="utf-8")

    assert "readOpaqueActionInfoHandleName" in resolver
    assert "local ok, macroName = safeCall(GetMacroInfo, handle)" in resolver
    assert "actionInfoLabelProbeBodyLength" not in resolver
    assert "macro_semantic_identity_no_spell_match" in resolver
    assert "if diagnostic.macroIdentityVerified == true then" in resolver
    assert "opaqueActionInfoCompatibilityEligible" in resolver
    assert "function Resolver:IsAutoBurstMacroEligible(value)" in resolver
    assert "bodyVerifiedMacroAssociation(resolvedAssociation) ~= true" in resolver
    assert "macroIdentityVerified == true" in resolver
    assert "semantics and semantics.autoBurstEligible == true" in resolver

    assert "if not parsed or tonumber(parsed.token) == nil or tonumber(parsed.token) <= 0 then return false end" in reaction
    assert "resolver:IsVerifiedCurrentMacroSource(candidate, candidate.macroAssociation) == true" in reaction
    assert "addOpaqueActionSpellMacroRoute(routes, candidate, spellID)" in reaction
    assert "verifiedManualPresentationSource" in planner
    assert "verifiedManualPresentationSource" in advisors


def test_valid_action_info_index_never_scans_other_macro_indexes_after_same_index_failure() -> None:
    script = textwrap.dedent(
        preamble()
        + r'''
        _G.GetNumMacros = function() return 2, 0 end
        _G.GetActionInfo = function(slot)
            if slot == 1 then return "macro", 1, nil, nil end
            return nil
        end
        _G.GetActionText = function() return "冰冻陷阱宏" end
        local readOtherIndex = false
        _G.GetMacroInfo = function(index)
            if index == 1 then return "冰冻陷阱宏", 1, nil end
            if index == 2 then
                readOtherIndex = true
                return "冰冻陷阱宏", 1, [[/cast 冰冻陷阱]]
            end
            return nil
        end
        _G.GetMacroSpell = function() return nil, nil, nil end

        local result = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(187650)
        if result.status == "Ready" or readOtherIndex == true then
            error("valid_index_scanned_other_macro:" .. tostring(result.status) .. ":" .. tostring(readOtherIndex))
        end
        local diag = result.macroDiagnostics and result.macroDiagnostics[1] or {}
        if diag.identityFailureReason ~= "macro_body_unavailable_action_info_id"
            or diag.actionInfoLooksLikeMacroIndex ~= true then
            error("valid_index_failure_not_retained:" .. tostring(diag.identityFailureReason))
        end
        '''
    )
    run_texlua(script)
