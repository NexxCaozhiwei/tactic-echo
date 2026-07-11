-- Pure HUD projection adapter.
-- AutoBurst owns burst sequence, binding, cooldown and confirmation snapshots.
-- This module performs no WoW API reads and never resolves an action itself.
local TE = _G.TacticEcho

local BurstPlanner = {}
TE.BurstPlanner = BurstPlanner

local function perfCount(name, amount)
    local perf = TE.PerformanceDiagnostics
    if perf and type(perf.Count) == "function" then perf:Count(name, amount) end
end

local function perfBegin(name)
    local perf = TE.PerformanceDiagnostics
    return perf and type(perf.Begin) == "function" and perf:Begin(name) or nil
end

local function perfFinish(token)
    local perf = TE.PerformanceDiagnostics
    if perf and type(perf.Finish) == "function" then perf:Finish(token) end
end

function BurstPlanner:Build(primary, context, settings, runtime)
    perfCount("burst_planner_build")
    local timer = perfBegin("BurstPlanner.Build")
    runtime = type(runtime) == "table" and runtime or {}
    local snapshot = runtime.runtimeSnapshot
    if type(snapshot) ~= "table" and TE.RuntimeSnapshot and type(TE.RuntimeSnapshot.GetLatest) == "function" then
        snapshot = TE.RuntimeSnapshot:GetLatest()
    end

    local result
    if TE.AutoBurst and type(TE.AutoBurst.BuildHudSnapshot) == "function" then
        local perf = TE.PerformanceDiagnostics
        if perf and type(perf.Guard) == "function" then
            local ok, value = perf:Guard("AutoBurst.BuildHudSnapshot", TE.AutoBurst.BuildHudSnapshot,
                TE.AutoBurst, primary, context, settings, snapshot)
            if ok and type(value) == "table" then result = value end
        else
            local ok, value = pcall(TE.AutoBurst.BuildHudSnapshot, TE.AutoBurst, primary, context, settings, snapshot)
            if ok and type(value) == "table" then result = value end
        end
    end

    if type(result) ~= "table" then
        result = {
            schema = 2,
            active = false,
            state = "safe_mode",
            stateLabel = "安全模式",
            items = {},
            followups = {},
            advisoryOnly = true,
            displayOnly = true,
            source = "autoburst_snapshot_adapter",
            blockedReason = "autoburst_hud_snapshot_unavailable",
        }
    end
    perfFinish(timer)
    return result
end
