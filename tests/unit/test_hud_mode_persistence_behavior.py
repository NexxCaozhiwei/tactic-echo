from pathlib import Path

from test_hud_cooldown_charge_behavior import run_lua

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def section(path, start, end):
    source = (ADDON / path).read_text(encoding="utf-8")
    return source[source.index(start):source.index(end, source.index(start))]


def test_mode_survives_all_runtime_states():
    helper = section("UI/TacticalBoard.lua", "local function statusText(primary)", "-- Do not use tostring")
    run_lua(helper + '''
for _, enabled in ipairs({true, false}) do
    TacticEchoDB = {tactics = {autoInjectionEnabled = enabled}}
    for _, state in ipairs({"paused", "standby", "dispatchable", "blocked", "channeling", "unknown"}) do
        local label = statusText({visual = {visualState = state}})
        assert(label:find(enabled and "HAD" or "LCC", 1, true))
        assert(label:find("  |  ", 1, true))
    end
end
assert(statusText(nil):find("LCC", 1, true))
''')


def test_native_digits_stay_opaque_above_effects_and_hide_with_cooldown():
    configure = section("UI/TacticalIconButton.lua", "local function configureCooldown", "local function showCooldown")
    native = section("UI/TacticalIconButton.lua", "local function setNativeCountdownNumbers", "local function applyPressedFrame")
    run_lua('local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end\n' + configure + native + '''
local text = {
    SetParent = function(self, v) self.parent = v end,
    SetDrawLayer = function(self, layer, sub) self.layer, self.sub = layer, sub end,
    SetAlpha = function(self, v) self.alpha = v end,
    SetShown = function(self, v) self.shown = v end,
}
local frame = {
    tacticEchoTextOverlay = {},
    SetAlpha = function(self, v) self.alpha = v end,
    SetSwipeColor = function(self, r, g, b, a) self.swipeAlpha = a end,
    SetDrawSwipe = function(self, v) self.swipe = v end,
    SetHideCountdownNumbers = function(self, v) self.hideNumbers = v end,
    GetCountdownFontString = function() return text end,
    Hide = function(self) self.hidden = true end,
}
configureCooldown(frame, {alpha = 0.3})
setNativeCountdownNumbers(frame, true)
assert(frame.alpha == 1 and frame.swipeAlpha == 0.3)
assert(text.alpha == 1 and text.parent == frame.tacticEchoTextOverlay)
assert(text.layer == "OVERLAY" and text.sub == 7 and text.shown)
hideCooldown(frame)
assert(frame.hideNumbers and not text.shown)
configureCooldown(frame, {enabled = false})
assert(not frame.swipe and frame.alpha == 1)
''')


def test_lcc_keeps_configured_cards_without_stale_active_owner():
    build = section("Tactics/AutoBurst.lua", "function AutoBurst:BuildHudSnapshot", "local function recentPriorityEvents")
    run_lua('''
local AutoBurst = {}
local TE = {BurstProfiles = {Get = function() return {}, "spec" end}}
local function hudPerfCount() end
local function hudMakeOutput() return {} end
local card = {bindingToken = 0, displayOnly = true, spellID = 123}
local function hudConfiguredGroups(snapshot, context, activeGroupId)
    assert(activeGroupId == nil, "disabled mode must ignore stale active owner")
    return {card}, "spec", {}, {{groupId = "group-1"}}
end
''' + build + '''
local snapshot = {autoBurst = {active = true, activeGroupId = "group-1"}}
local out = AutoBurst:BuildHudSnapshot(nil, {}, {autoInjectionEnabled = false}, snapshot)
assert(out.active and #out.items == 1 and out.items[1] == card)
assert(out.state == "DISPLAY_ONLY" and out.activeGroupId == nil)
assert(out.displayGroupCount == 1 and out.items[1].bindingToken == 0)
assert(snapshot.autoBurst.activeGroupId == "group-1", "HUD must not mutate runtime")
''')
