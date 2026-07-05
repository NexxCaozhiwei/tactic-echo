"""Executable P5.8 HUD manual-click routing with a minimal WoW frame stub."""
from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PRIORITY = ROOT / "addon" / "!TacticEcho" / "Tactics" / "ManualActionPriority.lua"
ROUTER = ROOT / "addon" / "!TacticEcho" / "UI" / "HudClickRouter.lua"


def run_texlua(script: str) -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "p57_hud_click_runtime.lua"
        path.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(path)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


def test_secure_proxy_visibility_mapping_and_manual_hold_priority() -> None:
    script = textwrap.dedent(
        f'''\
        local clock, inCombat = 10, false
        GetTime = function() return clock end
        InCombatLockdown = function() return inCombat end

        local function frame(name)
            local out = {{ name = name, shown = true, scripts = {{}}, attrs = {{}}, hooks = {{}} }}
            function out:SetFrameStrata(value) self.frameStrata = value end
            function out:SetFrameLevel(value) self.frameLevel = value end
            function out:SetToplevel(value) self.toplevel = value end
            function out:SetAllPoints(_) end
            function out:RegisterForClicks(...) self.clicks = {{...}} end
            function out:EnableMouse(_) end
            function out:SetAttribute(key, value) self.attrs[key] = value end
            function out:Show() self.shown = true end
            function out:Hide() self.shown = false end
            function out:IsShown() return self.shown == true end
            function out:IsVisible() return self.shown == true end
            function out:SetScript(kind, fn) self.scripts[kind] = fn end
            function out:GetScript(kind) return self.scripts[kind] end
            function out:HookScript(kind, fn) self.hooks[kind] = fn; return true end
            return out
        end
        UIParent = frame("UIParent")
        CreateFrame = function(_, name) return frame(name) end

        _G.TacticEcho = {{
            RegisterEventsSafe = function() return true end,
            SignalFrame = {{ refreshes = 0, Refresh = function(self) self.refreshes = self.refreshes + 1 end }},
        }}
        local actionA = frame("ActionButton1")
        local actionB = frame("ActionButton2")
        _G.ActionButton1 = actionA
        _G.ActionButton2 = actionB
        local current = actionA
        _G.TacticEcho.ActionBarBindingResolver = {{
            GetButtonCache = function() return {{ entries = {{{{ buttonName = "ActionButton1" }}}} }} end,
            ResolveManualHudAction = function()
                return {{ status = "Ready", button = current,
                    buttonName = current == actionA and "ActionButton1" or "ActionButton2",
                    actionSlot = current == actionA and 1 or 2, source = "spell" }}
            end,
        }}

        dofile({str(PRIORITY)!r})
        dofile({str(ROUTER)!r})
        local priority = _G.TacticEcho.ManualActionPriority
        local router = _G.TacticEcho.HudClickRouter

        local card = frame("HudCard")
        card.hudInteractionRole = "manual_action"
        function card:GetFrameStrata() return "MEDIUM" end
        function card:GetFrameLevel() return 10 end
        router:Attach(card)
        local layer = card.hudClickLayer
        if layer.proxy.frameStrata ~= "HIGH" or layer.blocker.frameStrata ~= "HIGH"
            or layer.proxy.clicks[1] ~= "LeftButtonDown" or layer.proxy.clicks[2] ~= "LeftButtonUp"
            or layer.blocker.clicks[1] ~= "AnyDown" or layer.blocker.clicks[2] ~= "AnyUp" then
            error("click_edge_or_input_layer_not_configured")
        end
        if not layer or layer.proxy.shown or layer.blocker.shown then
            error("initial_hidden_layers_required")
        end

        router:SetCardVisible(card, true)
        router:Configure(card, {{ spellID = 147362 }}, true)
        if card.manualClickReady ~= true or layer.blocker.shown ~= false
            or layer.proxy.attrs.type ~= "click" or layer.proxy.attrs.clickbutton ~= actionA then
            error("ready_mapping_not_installed")
        end

        local before = _G.TacticEcho.SignalFrame.refreshes
        layer.proxy.scripts.OnMouseDown(layer.proxy, "LeftButton")
        local active = priority:GetActive()
        if active.active ~= true or active.kind ~= "hud" or _G.TacticEcho.SignalFrame.refreshes ~= before + 1 then
            error("hud_manual_hold_not_recorded")
        end

        router:SetCardVisible(card, false)
        if layer.proxy.shown ~= false or layer.blocker.shown ~= false then
            error("hidden_card_left_click_surface_active")
        end

        router:SetCardVisible(card, true)
        inCombat = true
        current = actionB
        router:Configure(card, {{ spellID = 147362 }}, true)
        if card.manualClickReady ~= false or card.manualClickReason ~= "manual_actionbar_rebind_out_of_combat"
            or layer.blocker.shown ~= true or layer.proxy.attrs.clickbutton ~= actionA then
            error("combat_rebind_not_fail_closed")
        end

        -- A left click on an existing native default action-bar button creates
        -- the same short ownership window; it does not create a new action path.
        inCombat = false
        priority:AttachDefaultActionButtons("test")
        actionA.hooks.OnMouseDown(actionA, "LeftButton")
        active = priority:GetActive()
        if active.active ~= true or active.kind ~= "native_actionbar" or active.source ~= "ActionButton1" then
            error("native_actionbar_manual_hold_not_recorded")
        end
        '''
    )
    run_texlua(script)
